#!/usr/bin/env bash

mkdir -p logs/basic

echo "=== Launching all basic tests ==="

build_pf/gem5.opt --outdir=logs/basic/hello_m5out \
    configs/deprecated/example/se.py \
    --ruby --num-cpus=8 --mem-size=4GiB \
    --cmd=tests/test-progs/hello/bin/x86/linux/hello \
    > logs/basic/hello.log 2>&1 &
echo "  started: hello  (log: logs/basic/hello.log)"

build_pf/gem5.opt --outdir=logs/basic/coherence_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 --l1d_size=32KiB --l1i_size=32KiB --l2_size=512KiB \
    -c testcase/coherence/coherence_tests -o "" \
    > logs/basic/coherence.log 2>&1 &
echo "  started: coherence  (log: logs/basic/coherence.log)"

build_pf/gem5.opt --outdir=logs/basic/latency_l1_shared_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 --l1d_size=32KiB --l1i_size=32KiB --l2_size=512KiB \
    -c testcase/latency/latency_bench \
    -o "2048 1277 4096 r 0" \
    > logs/basic/latency_l1_shared.log 2>&1 &
echo "  started: latency_l1_shared  (log: logs/basic/latency_l1_shared.log)"

build_pf/gem5.opt --outdir=logs/basic/latency_l1_private_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 --l1d_size=32KiB --l1i_size=32KiB --l2_size=512KiB \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0" \
    > logs/basic/latency_l1_private.log 2>&1 &
echo "  started: latency_l1_private  (log: logs/basic/latency_l1_private.log)"

build_pf/gem5.opt --outdir=logs/basic/latency_l2_shared_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 --l1d_size=32KiB --l1i_size=32KiB --l2_size=512KiB \
    -c testcase/latency/latency_bench \
    -o "32768 20219 4096 r 16384" \
    > logs/basic/latency_l2_shared.log 2>&1 &
echo "  started: latency_l2_shared  (log: logs/basic/latency_l2_shared.log)"

build_pf/gem5.opt --outdir=logs/basic/latency_l2_private_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 --l1d_size=32KiB --l1i_size=32KiB --l2_size=512KiB \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "32768 20219 4096 r 16384;32768 20219 4096 r 16384;32768 20219 4096 r 16384;32768 20219 4096 r 16384;32768 20219 4096 r 16384;32768 20219 4096 r 16384;32768 20219 4096 r 16384;32768 20219 4096 r 16384" \
    > logs/basic/latency_l2_private.log 2>&1 &
echo "  started: latency_l2_private  (log: logs/basic/latency_l2_private.log)"

build_pf/gem5.opt --outdir=logs/basic/latency_mem_shared_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 --l1d_size=32KiB --l1i_size=32KiB --l2_size=512KiB \
    -c testcase/latency/latency_bench \
    -o "262144 173971 4096 r 262144" \
    > logs/basic/latency_mem_shared.log 2>&1 &
echo "  started: latency_mem_shared  (log: logs/basic/latency_mem_shared.log)"

build_pf/gem5.opt --outdir=logs/basic/latency_mem_private_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 --l1d_size=32KiB --l1i_size=32KiB --l2_size=512KiB \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "262144 173971 4096 r 262144;262144 173971 4096 r 262144;262144 173971 4096 r 262144;262144 173971 4096 r 262144;262144 173971 4096 r 262144;262144 173971 4096 r 262144;262144 173971 4096 r 262144;262144 173971 4096 r 262144" \
    > logs/basic/latency_mem_private.log 2>&1 &
echo "  started: latency_mem_private  (log: logs/basic/latency_mem_private.log)"

echo ""
echo "All launched. Check logs in logs/basic/"
echo "Results: grep 'Exiting @ tick\|PASS\|FAIL\|Hello' logs/basic/*.log"
