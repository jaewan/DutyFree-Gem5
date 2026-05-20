#!/usr/bin/env bash
# Zen 4c cache config:
#   L1D: 32KB 8-way  L1I: 64KB 8-way  L2: 16MB 16-way (acts as CCX L3)
#
# Latency bench params:
#   L1 hit:  N=2048    (8KB  << 32KB L1D)
#   L2 hit:  N=524288  (2MB  << 16MB L2),  flush=262144
#   MEM hit: N=4194304 (16MB >= 16MB L2),  flush=N

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
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c testcase/coherence/coherence_tests -o "" \
    > logs/basic/coherence.log 2>&1 &
echo "  started: coherence  (log: logs/basic/coherence.log)"

build_pf/gem5.opt --outdir=logs/basic/latency_l1_shared_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c testcase/latency/latency_bench \
    -o "2048 1277 4096 r 0" \
    > logs/basic/latency_l1_shared.log 2>&1 &
echo "  started: latency_l1_shared  (log: logs/basic/latency_l1_shared.log)"

build_pf/gem5.opt --outdir=logs/basic/latency_l1_private_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0" \
    > logs/basic/latency_l1_private.log 2>&1 &
echo "  started: latency_l1_private  (log: logs/basic/latency_l1_private.log)"

build_pf/gem5.opt --outdir=logs/basic/latency_l2_shared_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c testcase/latency/latency_bench \
    -o "524288 324011 4096 r 262144" \
    > logs/basic/latency_l2_shared.log 2>&1 &
echo "  started: latency_l2_shared  (log: logs/basic/latency_l2_shared.log)"

build_pf/gem5.opt --outdir=logs/basic/latency_l2_private_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "524288 324011 4096 r 262144;524288 324011 4096 r 262144;524288 324011 4096 r 262144;524288 324011 4096 r 262144;524288 324011 4096 r 262144;524288 324011 4096 r 262144;524288 324011 4096 r 262144;524288 324011 4096 r 262144" \
    > logs/basic/latency_l2_private.log 2>&1 &
echo "  started: latency_l2_private  (log: logs/basic/latency_l2_private.log)"

echo ""
echo "All launched. Check logs in logs/basic/"
echo "Results: grep 'Exiting @ tick\|PASS\|FAIL\|Hello' logs/basic/*.log"
