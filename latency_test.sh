#!/usr/bin/env bash

mkdir -p logs/latency

echo "=== Launching all latency tests ==="

build_pf/gem5.opt --outdir=logs/latency/l1_read_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 --l1d_size=32KiB --l1i_size=32KiB --l2_size=512KiB \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0" \
    > logs/latency/l1_read.log 2>&1 &
echo "  started: l1_read  (log: logs/latency/l1_read.log)"

build_pf/gem5.opt --outdir=logs/latency/l2_read_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 --l1d_size=32KiB --l1i_size=32KiB --l2_size=512KiB \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "32768 20219 4096 r 16384;32768 20219 4096 r 16384;32768 20219 4096 r 16384;32768 20219 4096 r 16384;32768 20219 4096 r 16384;32768 20219 4096 r 16384;32768 20219 4096 r 16384;32768 20219 4096 r 16384" \
    > logs/latency/l2_read.log 2>&1 &
echo "  started: l2_read  (log: logs/latency/l2_read.log)"

build_pf/gem5.opt --outdir=logs/latency/l3_read_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 --l1d_size=32KiB --l1i_size=32KiB --l2_size=512KiB \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "262144 173971 4096 r 262144;262144 173971 4096 r 262144;262144 173971 4096 r 262144;262144 173971 4096 r 262144;262144 173971 4096 r 262144;262144 173971 4096 r 262144;262144 173971 4096 r 262144;262144 173971 4096 r 262144" \
    > logs/latency/l3_read.log 2>&1 &
echo "  started: l3_read  (log: logs/latency/l3_read.log)"

build_pf/gem5.opt --outdir=logs/latency/mem_read_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 --l1d_size=32KiB --l1i_size=32KiB --l2_size=512KiB \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "262144 173971 4096 r 262144;262144 173971 4096 r 262144;262144 173971 4096 r 262144;262144 173971 4096 r 262144;262144 173971 4096 r 262144;262144 173971 4096 r 262144;262144 173971 4096 r 262144;262144 173971 4096 r 262144" \
    > logs/latency/mem_read.log 2>&1 &
echo "  started: mem_read  (log: logs/latency/mem_read.log)"

build_pf/gem5.opt --outdir=logs/latency/l1_write_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 --l1d_size=32KiB --l1i_size=32KiB --l2_size=512KiB \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "2048 1277 4096 w 0;2048 1277 4096 w 0;2048 1277 4096 w 0;2048 1277 4096 w 0;2048 1277 4096 w 0;2048 1277 4096 w 0;2048 1277 4096 w 0;2048 1277 4096 w 0" \
    > logs/latency/l1_write.log 2>&1 &
echo "  started: l1_write  (log: logs/latency/l1_write.log)"

build_pf/gem5.opt --outdir=logs/latency/l2_write_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 --l1d_size=32KiB --l1i_size=32KiB --l2_size=512KiB \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "32768 20219 4096 w 16384;32768 20219 4096 w 16384;32768 20219 4096 w 16384;32768 20219 4096 w 16384;32768 20219 4096 w 16384;32768 20219 4096 w 16384;32768 20219 4096 w 16384;32768 20219 4096 w 16384" \
    > logs/latency/l2_write.log 2>&1 &
echo "  started: l2_write  (log: logs/latency/l2_write.log)"

build_pf/gem5.opt --outdir=logs/latency/l3_write_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 --l1d_size=32KiB --l1i_size=32KiB --l2_size=512KiB \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "262144 173971 4096 w 262144;262144 173971 4096 w 262144;262144 173971 4096 w 262144;262144 173971 4096 w 262144;262144 173971 4096 w 262144;262144 173971 4096 w 262144;262144 173971 4096 w 262144;262144 173971 4096 w 262144" \
    > logs/latency/l3_write.log 2>&1 &
echo "  started: l3_write  (log: logs/latency/l3_write.log)"

build_pf/gem5.opt --outdir=logs/latency/mem_write_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 --l1d_size=32KiB --l1i_size=32KiB --l2_size=512KiB \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "262144 173971 4096 w 262144;262144 173971 4096 w 262144;262144 173971 4096 w 262144;262144 173971 4096 w 262144;262144 173971 4096 w 262144;262144 173971 4096 w 262144;262144 173971 4096 w 262144;262144 173971 4096 w 262144" \
    > logs/latency/mem_write.log 2>&1 &
echo "  started: mem_write  (log: logs/latency/mem_write.log)"

echo ""
echo "All launched. Check logs in logs/latency/"
echo "Results: grep 'Exiting @ tick' logs/latency/*.log"
