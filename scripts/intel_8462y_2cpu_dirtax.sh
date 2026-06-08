#!/usr/bin/env bash
# Intel Xeon 8462Y+ (Sapphire Rapids) Directory Tax — 2 CPU
# LLC = 2 HNF × 2MiB = 4MiB
# victim → DRAM 150ns, aggressor → CXL 300ns

ROOT=/home/naivete/DutyFree-Gem5-pakeunji
GEM5=$ROOT/build_Intel_8462Y/gem5.opt
CFG=$ROOT/configs/deprecated/example/se.py
LLC_KIB=4096        # 2 × 2MiB
AGG_MB=16.0         # LLC×4 per aggressor
ITERS=2097152       # max_vs(4096KiB) × 256 × 2 passes

COMMON="$CFG
    --ruby --topology=Pt2Pt \
    --chi-config=$ROOT/configs/ruby/CHI_config_8462Y.py
    --num-l3caches=2 --num-dirs=1
    --cpu-type=O3CPU --num-cpus=2 --cpu-clock=2.8GHz
    --l1d_size=48KiB --l1d_assoc=12
    --l1i_size=32KiB --l1i_assoc=8
    --l2_size=2MiB   --l2_assoc=16
    --l3_size=2MiB   --l3_assoc=16
    --mem-type=SimpleMemory
    --mem-size=4GiB --cxl-mem-size=2GiB
    --dram-latency=150ns --cxl-latency=300ns"

V=$ROOT/testcase/dirtax/victim
A=$ROOT/testcase/dirtax/aggressor
D=$ROOT/testcase/dirtax/dummy

PCTS="25 40 45 50 53 55 60 75 100"

print_results() {
python3 - << 'PYEOF'
from pathlib import Path
base = Path("/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_8462y_2cpu_dirtax")
def ticks(d):
    try:
        for line in open(d/"stats.txt"):
            if line.startswith("simTicks "): return int(line.split()[1])
    except: pass
    return None
print(f"{'pct':<6}  {'vs_kb':>8}  {'slowdown':>10}")
for pct, vs in [("25p",1024),("40p",1638),("45p",1843),("50p",2048),
                ("53p",2170),("55p",2252),("60p",2457),("75p",3072),("100p",4096)]:
    a = ticks(base/f"alone_{pct}")
    w = ticks(base/f"with_agg_{pct}")
    sl = f"{w/a:.3f}x" if a and w else "n/a"
    print(f"{pct:<6}  {vs:>8}  {sl:>10}")
PYEOF
}

run_all() {
    mkdir -p $ROOT/logs/intel_8462y_2cpu_dirtax
    echo "===== Intel 8462Y+ Directory Tax (2 CPU, LLC=4MiB) ====="

    for pct in $PCTS; do
        vs=$(( LLC_KIB * pct / 100 ))
        tag="${pct}p"

        $GEM5 --outdir=$ROOT/logs/intel_8462y_2cpu_dirtax/alone_${tag} \
            $COMMON -c "$V;$D" --options "$vs $ITERS;" \
            > $ROOT/logs/intel_8462y_2cpu_dirtax/alone_${tag}.log 2>&1 &
        echo "  started: alone_${tag} [PID $!]"

        $GEM5 --outdir=$ROOT/logs/intel_8462y_2cpu_dirtax/with_agg_${tag} \
            $COMMON -c "$V;$A" --options "$vs $ITERS;$AGG_MB" \
            > $ROOT/logs/intel_8462y_2cpu_dirtax/with_agg_${tag}.log 2>&1 &
        echo "  started: with_agg_${tag} [PID $!]"
    done

    wait
    echo "Done."
    print_results
}

case "${1:-all}" in
    results) print_results ;;
    all)     run_all ;;
    *)       echo "Usage: $0 [all|results]"; exit 1 ;;
esac
