#!/usr/bin/env bash
# CHI protocol version of basic_test.sh
#
# Cache hierarchy (per CPU):
#   L1D 32KiB 8-way  |  L1I 64KiB 8-way  |  private L2 512KiB 8-way
#   shared L3 (HNF) 16MiB 16-way
#
# Topology: Pt2Pt  |  1 HNF  |  1 SNF

mkdir -p logs/intel_basic

echo "=== Launching CHI basic tests ==="

build_X86_CHI/gem5.opt --outdir=logs/intel_basic/hello_m5out \
    configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=1 --mem-size=4GiB \
    --cmd=tests/test-progs/hello/bin/x86/linux/hello \
    > logs/intel_basic/hello.log 2>&1 &
echo "  started: hello  (log: logs/intel_basic/hello.log)"

# ── num-cpus=2 (tests 10-14: 2c variants) ───────────────────────────────────

build_X86_CHI/gem5.opt --outdir=logs/intel_basic/2c_t10_m5out \
    configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=2 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c testcase/coherence/coherence_tests -o "10" \
    > logs/intel_basic/2c_t10.log 2>&1 &
echo "  started: 2c test 10 invalidation_2c"

build_X86_CHI/gem5.opt --outdir=logs/intel_basic/2c_t11_m5out \
    configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=2 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c testcase/coherence/coherence_tests -o "11" \
    > logs/intel_basic/2c_t11.log 2>&1 &
echo "  started: 2c test 11 sharing_2c"

build_X86_CHI/gem5.opt --outdir=logs/intel_basic/2c_t12_m5out \
    configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=2 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c testcase/coherence/coherence_tests -o "12" \
    > logs/intel_basic/2c_t12.log 2>&1 &
echo "  started: 2c test 12 pingpong_2c"

build_X86_CHI/gem5.opt --outdir=logs/intel_basic/2c_t13_m5out \
    configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=2 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c testcase/coherence/coherence_tests -o "13" \
    > logs/intel_basic/2c_t13.log 2>&1 &
echo "  started: 2c test 13 ostate_2c"

build_X86_CHI/gem5.opt --outdir=logs/intel_basic/2c_t14_m5out \
    configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=2 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c testcase/coherence/coherence_tests -o "14" \
    > logs/intel_basic/2c_t14.log 2>&1 &
echo "  started: 2c test 14 false_sharing_2c"

# ── num-cpus=4 ───────────────────────────────────────────────────────────────

build_X86_CHI/gem5.opt --outdir=logs/intel_basic/4c_t0_m5out \
    configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=4 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c testcase/coherence/coherence_tests -o "0" \
    > logs/intel_basic/4c_t0.log 2>&1 &
echo "  started: 4c test 0 invalidation"

build_X86_CHI/gem5.opt --outdir=logs/intel_basic/4c_t1_m5out \
    configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=4 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c testcase/coherence/coherence_tests -o "1" \
    > logs/intel_basic/4c_t1.log 2>&1 &
echo "  started: 4c test 1 sharing"

build_X86_CHI/gem5.opt --outdir=logs/intel_basic/4c_t2_m5out \
    configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=4 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c testcase/coherence/coherence_tests -o "2" \
    > logs/intel_basic/4c_t2.log 2>&1 &
echo "  started: 4c test 2 pingpong"

build_X86_CHI/gem5.opt --outdir=logs/intel_basic/4c_t3_m5out \
    configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=4 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c testcase/coherence/coherence_tests -o "3" \
    > logs/intel_basic/4c_t3.log 2>&1 &
echo "  started: 4c test 3 ostate"

build_X86_CHI/gem5.opt --outdir=logs/intel_basic/4c_t4_m5out \
    configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=4 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c testcase/coherence/coherence_tests -o "4" \
    > logs/intel_basic/4c_t4.log 2>&1 &
echo "  started: 4c test 4 false_sharing"

build_X86_CHI/gem5.opt --outdir=logs/intel_basic/4c_t5_m5out \
    configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=4 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c testcase/coherence/coherence_tests -o "5" \
    > logs/intel_basic/4c_t5.log 2>&1 &
echo "  started: 4c test 5 inter_cp_share"

build_X86_CHI/gem5.opt --outdir=logs/intel_basic/4c_t6_m5out \
    configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=4 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c testcase/coherence/coherence_tests -o "6" \
    > logs/intel_basic/4c_t6.log 2>&1 &
echo "  started: 4c test 6 inter_cp_inv"

build_X86_CHI/gem5.opt --outdir=logs/intel_basic/4c_t7_m5out \
    configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=4 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c testcase/coherence/coherence_tests -o "7" \
    > logs/intel_basic/4c_t7.log 2>&1 &
echo "  started: 4c test 7 o_state_inter_cp"

build_X86_CHI/gem5.opt --outdir=logs/intel_basic/4c_t8_m5out \
    configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=4 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c testcase/coherence/coherence_tests -o "8" \
    > logs/intel_basic/4c_t8.log 2>&1 &
echo "  started: 4c test 8 multi_sharer_inv"

echo ""
echo "All launched. Check logs in logs/intel_basic/"
echo "Results: grep 'Exiting @ tick\|PASS\|FAIL\|Hello\|INFO' logs/intel_basic/*.log"
