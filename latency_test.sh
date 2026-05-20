#!/usr/bin/env bash
# Zen 4c latency benchmark
#   L1D: 32KB 8-way  L1I: 64KB 8-way  L2: 16MB 16-way (acts as CCX L3)
#
# Working sets:
#   L1:  N=2048    (8KB  << 32KB L1D),  iters=4096
#   L2:  N=524288  (2MB  << 16MB L2),   iters=1024,  flush=262144
#   MEM: N=4194304 (16MB >= 16MB L2),   iters=256,   flush=N

mkdir -p logs/latency

echo "=== Launching latency tests ==="

# ── L1 read ───────────────────────────────────────────────────────────────
build_pf/gem5.opt --outdir=logs/latency/l1_read_1t_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=2 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c testcase/latency/latency_bench \
    -o "2048 1277 4096 r 0" \
    > logs/latency/l1_read_1t.log 2>&1 &
echo "  started: l1_read_1t"

build_pf/gem5.opt --outdir=logs/latency/l1_read_8t_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0" \
    > logs/latency/l1_read_8t.log 2>&1 &
echo "  started: l1_read_8t"

# ── L1 write ──────────────────────────────────────────────────────────────
build_pf/gem5.opt --outdir=logs/latency/l1_write_1t_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=2 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c testcase/latency/latency_bench \
    -o "2048 1277 4096 w 0" \
    > logs/latency/l1_write_1t.log 2>&1 &
echo "  started: l1_write_1t"

build_pf/gem5.opt --outdir=logs/latency/l1_write_8t_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "2048 1277 4096 w 0;2048 1277 4096 w 0;2048 1277 4096 w 0;2048 1277 4096 w 0;2048 1277 4096 w 0;2048 1277 4096 w 0;2048 1277 4096 w 0;2048 1277 4096 w 0" \
    > logs/latency/l1_write_8t.log 2>&1 &
echo "  started: l1_write_8t"

# ── L2 read ───────────────────────────────────────────────────────────────
build_pf/gem5.opt --outdir=logs/latency/l2_read_1t_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=2 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c testcase/latency/latency_bench \
    -o "524288 324011 1024 r 262144" \
    > logs/latency/l2_read_1t.log 2>&1 &
echo "  started: l2_read_1t"

build_pf/gem5.opt --outdir=logs/latency/l2_read_8t_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "524288 324011 1024 r 262144;524288 324011 1024 r 262144;524288 324011 1024 r 262144;524288 324011 1024 r 262144;524288 324011 1024 r 262144;524288 324011 1024 r 262144;524288 324011 1024 r 262144;524288 324011 1024 r 262144" \
    > logs/latency/l2_read_8t.log 2>&1 &
echo "  started: l2_read_8t"

# ── L2 write ──────────────────────────────────────────────────────────────
build_pf/gem5.opt --outdir=logs/latency/l2_write_1t_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=2 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c testcase/latency/latency_bench \
    -o "524288 324011 1024 w 262144" \
    > logs/latency/l2_write_1t.log 2>&1 &
echo "  started: l2_write_1t"

build_pf/gem5.opt --outdir=logs/latency/l2_write_8t_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "524288 324011 1024 w 262144;524288 324011 1024 w 262144;524288 324011 1024 w 262144;524288 324011 1024 w 262144;524288 324011 1024 w 262144;524288 324011 1024 w 262144;524288 324011 1024 w 262144;524288 324011 1024 w 262144" \
    > logs/latency/l2_write_8t.log 2>&1 &
echo "  started: l2_write_8t"

# ── MEM read ──────────────────────────────────────────────────────────────
build_pf/gem5.opt --outdir=logs/latency/mem_read_1t_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=2 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c testcase/latency/latency_bench \
    -o "4194304 2592089 256 r 4194304" \
    > logs/latency/mem_read_1t.log 2>&1 &
echo "  started: mem_read_1t"

build_pf/gem5.opt --outdir=logs/latency/mem_read_8t_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "4194304 2592089 256 r 4194304;4194304 2592089 256 r 4194304;4194304 2592089 256 r 4194304;4194304 2592089 256 r 4194304;4194304 2592089 256 r 4194304;4194304 2592089 256 r 4194304;4194304 2592089 256 r 4194304;4194304 2592089 256 r 4194304" \
    > logs/latency/mem_read_8t.log 2>&1 &
echo "  started: mem_read_8t"

# ── MEM write ─────────────────────────────────────────────────────────────
build_pf/gem5.opt --outdir=logs/latency/mem_write_1t_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=2 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c testcase/latency/latency_bench \
    -o "4194304 2592089 256 w 4194304" \
    > logs/latency/mem_write_1t.log 2>&1 &
echo "  started: mem_write_1t"

build_pf/gem5.opt --outdir=logs/latency/mem_write_8t_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "4194304 2592089 256 w 4194304;4194304 2592089 256 w 4194304;4194304 2592089 256 w 4194304;4194304 2592089 256 w 4194304;4194304 2592089 256 w 4194304;4194304 2592089 256 w 4194304;4194304 2592089 256 w 4194304;4194304 2592089 256 w 4194304" \
    > logs/latency/mem_write_8t.log 2>&1 &
echo "  started: mem_write_8t"

echo ""
echo "All launched (12 tests). Check logs in logs/latency/"
echo "Results: grep 'Exiting @ tick' logs/latency/*.log"
