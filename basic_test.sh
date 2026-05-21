#!/usr/bin/env bash

mkdir -p logs/basic

echo "=== Launching all basic tests ==="

build_amd_zen4_PF/gem5.opt --outdir=logs/basic/hello_m5out \
    configs/deprecated/example/se.py \
    --ruby --num-cpus=8 --mem-size=4GiB \
    --cmd=tests/test-progs/hello/bin/x86/linux/hello \
    > logs/basic/hello.log 2>&1 &
echo "  started: hello  (log: logs/basic/hello.log)"

# ── num-cpus=2 (tests 10-14: 2c variants, main+1 pthread) ───

build_amd_zen4_PF/gem5.opt --outdir=logs/basic/2c_t10_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=2 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c testcase/coherence/coherence_tests -o "10" \
    > logs/basic/2c_t10.log 2>&1 &
echo "  started: 2c test 10 invalidation_2c"

build_amd_zen4_PF/gem5.opt --outdir=logs/basic/2c_t11_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=2 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c testcase/coherence/coherence_tests -o "11" \
    > logs/basic/2c_t11.log 2>&1 &
echo "  started: 2c test 11 sharing_2c"

build_amd_zen4_PF/gem5.opt --outdir=logs/basic/2c_t12_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=2 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c testcase/coherence/coherence_tests -o "12" \
    > logs/basic/2c_t12.log 2>&1 &
echo "  started: 2c test 12 pingpong_2c"

build_amd_zen4_PF/gem5.opt --outdir=logs/basic/2c_t13_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=2 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c testcase/coherence/coherence_tests -o "13" \
    > logs/basic/2c_t13.log 2>&1 &
echo "  started: 2c test 13 ostate_2c"

build_amd_zen4_PF/gem5.opt --outdir=logs/basic/2c_t14_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=2 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c testcase/coherence/coherence_tests -o "14" \
    > logs/basic/2c_t14.log 2>&1 &
echo "  started: 2c test 14 false_sharing_2c"

# ── num-cpus=4 ──────────────────────────────────────────────

build_amd_zen4_PF/gem5.opt --outdir=logs/basic/4c_t0_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=4 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c testcase/coherence/coherence_tests -o "0" \
    > logs/basic/4c_t0.log 2>&1 &
echo "  started: 4c test 0 invalidation"

build_amd_zen4_PF/gem5.opt --outdir=logs/basic/4c_t1_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=4 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c testcase/coherence/coherence_tests -o "1" \
    > logs/basic/4c_t1.log 2>&1 &
echo "  started: 4c test 1 sharing"

build_amd_zen4_PF/gem5.opt --outdir=logs/basic/4c_t2_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=4 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c testcase/coherence/coherence_tests -o "2" \
    > logs/basic/4c_t2.log 2>&1 &
echo "  started: 4c test 2 pingpong"

build_amd_zen4_PF/gem5.opt --outdir=logs/basic/4c_t3_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=4 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c testcase/coherence/coherence_tests -o "3" \
    > logs/basic/4c_t3.log 2>&1 &
echo "  started: 4c test 3 ostate"

build_amd_zen4_PF/gem5.opt --outdir=logs/basic/4c_t4_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=4 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c testcase/coherence/coherence_tests -o "4" \
    > logs/basic/4c_t4.log 2>&1 &
echo "  started: 4c test 4 false_sharing"

build_amd_zen4_PF/gem5.opt --outdir=logs/basic/4c_t5_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=4 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c testcase/coherence/coherence_tests -o "5" \
    > logs/basic/4c_t5.log 2>&1 &
echo "  started: 4c test 5 inter_cp_share"

build_amd_zen4_PF/gem5.opt --outdir=logs/basic/4c_t6_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=4 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c testcase/coherence/coherence_tests -o "6" \
    > logs/basic/4c_t6.log 2>&1 &
echo "  started: 4c test 6 inter_cp_inv"

build_amd_zen4_PF/gem5.opt --outdir=logs/basic/4c_t7_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=4 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c testcase/coherence/coherence_tests -o "7" \
    > logs/basic/4c_t7.log 2>&1 &
echo "  started: 4c test 7 o_state_inter_cp"

build_amd_zen4_PF/gem5.opt --outdir=logs/basic/4c_t8_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=4 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c testcase/coherence/coherence_tests -o "8" \
    > logs/basic/4c_t8.log 2>&1 &
echo "  started: 4c test 8 multi_sharer_inv"

echo ""
echo "All launched. Check logs in logs/basic/"
echo "Results: grep 'Exiting @ tick\|PASS\|FAIL\|Hello\|INFO' logs/basic/*.log"
