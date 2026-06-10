#!/usr/bin/env bash
# CHI protocol version of basic_test.sh — runs the suite on BOTH Intel builds
# (8462Y, 8592). The two builds share an identical kconfig, so this is a pure
# correctness/coherence smoke test; logs are kept separate per platform.
#
# Cache hierarchy (per CPU):
#   L1D 32KiB 8-way  |  L1I 64KiB 8-way  |  private L2 512KiB 8-way
#   shared L3 (HNF) 16MiB 16-way
#
# Topology: Pt2Pt  |  1 HNF  |  1 SNF

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CFG=$ROOT/configs/deprecated/example/se.py
COH=$ROOT/testcase/coherence/coherence_tests

# 4c coherence test names (index = -o option value)
# Note: num-cpus=2 cannot host the 2-thread coherence tests, because gem5 SE
# allocates one ThreadContext per CPU and main itself occupies one — leaving
# only one TC for workers. The 2c suite was removed for that reason.
names_4c=([0]=invalidation [1]=sharing [2]=pingpong [3]=ostate [4]=false_sharing \
          [5]=inter_cp_share [6]=inter_cp_inv [7]=o_state_inter_cp [8]=multi_sharer_inv)

run_suite() {
    local GEM5=$1 LOG=$2
    mkdir -p "$LOG"

    "$GEM5" --outdir=$LOG/hello_m5out \
        $CFG --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
        --cpu-type=TimingSimpleCPU --num-cpus=1 --mem-size=4GiB \
        --cmd=tests/test-progs/hello/bin/x86/linux/hello \
        > $LOG/hello.log 2>&1 &
    echo "  started: hello  (log: $LOG/hello.log)"

    # ── num-cpus=4 (tests 0-8) ──────────────────────────────────────────────
    for t in 0 1 2 3 4 5 6 7 8; do
        "$GEM5" --outdir=$LOG/4c_t${t}_m5out \
            $CFG --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
            --cpu-type=TimingSimpleCPU --num-cpus=4 \
            --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
            --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
            -c $COH -o "$t" \
            > $LOG/4c_t${t}.log 2>&1 &
        echo "  started: 4c test $t ${names_4c[$t]}"
    done
}

echo "=== Launching CHI basic tests (8462Y) ==="
run_suite "$ROOT/build_Intel_8462Y/gem5.opt" "$ROOT/logs/basic_test/8462Y"

echo "=== Launching CHI basic tests (8592) ==="
run_suite "$ROOT/build_Intel_8592/gem5.opt"  "$ROOT/logs/basic_test/8592"

echo ""
echo "All launched. Logs in $ROOT/logs/basic_test/{8462Y,8592}/"
echo "Results: grep 'Exiting @ tick\|PASS\|FAIL\|Hello\|INFO' $ROOT/logs/basic_test/*/*.log"
