#!/usr/bin/env bash

# repo 루트 기준으로 실행 (어느 디렉토리에서 호출하든 동작)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
GEM5="${GEM5:-$ROOT/build_amd_zen4_PF/gem5.opt}"

mkdir -p logs/basic

echo "=== Launching all basic tests ==="

# ── hello (2c / 8c) ─────────────────────────────────────────
"$GEM5" --outdir=logs/basic/hello_2c_m5out \
    configs/deprecated/example/se.py \
    --ruby --num-cpus=2 --mem-size=4GiB \
    --mem-type=SimpleMemory --l1-latency=3 --l2-latency=14 \
    --cmd=tests/test-progs/hello/bin/x86/linux/hello \
    > logs/basic/hello_2c.log 2>&1 &
echo "  started: hello_2c  (log: logs/basic/hello_2c.log)"

"$GEM5" --outdir=logs/basic/hello_8c_m5out \
    configs/deprecated/example/se.py \
    --ruby --num-cpus=8 --mem-size=4GiB \
    --mem-type=SimpleMemory --l1-latency=3 --l2-latency=14 \
    --cmd=tests/test-progs/hello/bin/x86/linux/hello \
    > logs/basic/hello_8c.log 2>&1 &
echo "  started: hello_8c  (log: logs/basic/hello_8c.log)"

# ── num-cpus=2 (tests 10-14: 2c variants, main+1 pthread) ───

"$GEM5" --outdir=logs/basic/2c_t10_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=O3CPU --num-cpus=2 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    --mem-type=SimpleMemory --l1-latency=3 --l2-latency=14 \
    -c testcase/coherence/coherence_tests -o "10" \
    > logs/basic/2c_t10.log 2>&1 &
echo "  started: 2c test 10 invalidation_2c"

"$GEM5" --outdir=logs/basic/2c_t11_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=O3CPU --num-cpus=2 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    --mem-type=SimpleMemory --l1-latency=3 --l2-latency=14 \
    -c testcase/coherence/coherence_tests -o "11" \
    > logs/basic/2c_t11.log 2>&1 &
echo "  started: 2c test 11 sharing_2c"

"$GEM5" --outdir=logs/basic/2c_t12_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=O3CPU --num-cpus=2 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    --mem-type=SimpleMemory --l1-latency=3 --l2-latency=14 \
    -c testcase/coherence/coherence_tests -o "12" \
    > logs/basic/2c_t12.log 2>&1 &
echo "  started: 2c test 12 pingpong_2c"

"$GEM5" --outdir=logs/basic/2c_t13_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=O3CPU --num-cpus=2 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    --mem-type=SimpleMemory --l1-latency=3 --l2-latency=14 \
    -c testcase/coherence/coherence_tests -o "13" \
    > logs/basic/2c_t13.log 2>&1 &
echo "  started: 2c test 13 ostate_2c"

"$GEM5" --outdir=logs/basic/2c_t14_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=O3CPU --num-cpus=2 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    --mem-type=SimpleMemory --l1-latency=3 --l2-latency=14 \
    -c testcase/coherence/coherence_tests -o "14" \
    > logs/basic/2c_t14.log 2>&1 &
echo "  started: 2c test 14 false_sharing_2c"

# ── num-cpus=8 ──────────────────────────────────────────────

"$GEM5" --outdir=logs/basic/8c_t0_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=O3CPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    --mem-type=SimpleMemory --l1-latency=3 --l2-latency=14 \
    -c testcase/coherence/coherence_tests -o "0" \
    > logs/basic/8c_t0.log 2>&1 &
echo "  started: 8c test 0 invalidation"

"$GEM5" --outdir=logs/basic/8c_t1_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=O3CPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    --mem-type=SimpleMemory --l1-latency=3 --l2-latency=14 \
    -c testcase/coherence/coherence_tests -o "1" \
    > logs/basic/8c_t1.log 2>&1 &
echo "  started: 8c test 1 sharing"

"$GEM5" --outdir=logs/basic/8c_t2_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=O3CPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    --mem-type=SimpleMemory --l1-latency=3 --l2-latency=14 \
    -c testcase/coherence/coherence_tests -o "2" \
    > logs/basic/8c_t2.log 2>&1 &
echo "  started: 8c test 2 pingpong"

"$GEM5" --outdir=logs/basic/8c_t3_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=O3CPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    --mem-type=SimpleMemory --l1-latency=3 --l2-latency=14 \
    -c testcase/coherence/coherence_tests -o "3" \
    > logs/basic/8c_t3.log 2>&1 &
echo "  started: 8c test 3 ostate"

"$GEM5" --outdir=logs/basic/8c_t4_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=O3CPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    --mem-type=SimpleMemory --l1-latency=3 --l2-latency=14 \
    -c testcase/coherence/coherence_tests -o "4" \
    > logs/basic/8c_t4.log 2>&1 &
echo "  started: 8c test 4 false_sharing"

"$GEM5" --outdir=logs/basic/8c_t5_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=O3CPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    --mem-type=SimpleMemory --l1-latency=3 --l2-latency=14 \
    -c testcase/coherence/coherence_tests -o "5" \
    > logs/basic/8c_t5.log 2>&1 &
echo "  started: 8c test 5 inter_cp_share"

"$GEM5" --outdir=logs/basic/8c_t6_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=O3CPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    --mem-type=SimpleMemory --l1-latency=3 --l2-latency=14 \
    -c testcase/coherence/coherence_tests -o "6" \
    > logs/basic/8c_t6.log 2>&1 &
echo "  started: 8c test 6 inter_cp_inv"

"$GEM5" --outdir=logs/basic/8c_t7_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=O3CPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    --mem-type=SimpleMemory --l1-latency=3 --l2-latency=14 \
    -c testcase/coherence/coherence_tests -o "7" \
    > logs/basic/8c_t7.log 2>&1 &
echo "  started: 8c test 7 o_state_inter_cp"

"$GEM5" --outdir=logs/basic/8c_t8_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=O3CPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    --mem-type=SimpleMemory --l1-latency=3 --l2-latency=14 \
    -c testcase/coherence/coherence_tests -o "8" \
    > logs/basic/8c_t8.log 2>&1 &
echo "  started: 8c test 8 multi_sharer_inv"

echo ""
echo "All launched. Check logs in logs/basic/"
echo "Results: grep 'Exiting @ tick\|PASS\|FAIL\|Hello\|INFO' logs/basic/*.log"
