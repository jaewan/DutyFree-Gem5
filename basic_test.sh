#!/usr/bin/env bash

mkdir -p logs/basic

echo "=== Launching all basic tests ==="

build_amd_zen4_PF_broadcast/gem5.opt --outdir=logs/basic/hello_m5out \
    configs/deprecated/example/se.py \
    --ruby --num-cpus=8 --mem-size=4GiB \
    --cmd=tests/test-progs/hello/bin/x86/linux/hello \
    > logs/basic/hello.log 2>&1 &
echo "  started: hello  (log: logs/basic/hello.log)"

build_amd_zen4_PF_broadcast/gem5.opt --outdir=logs/basic/coherence_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c testcase/coherence/coherence_tests -o "" \
    > logs/basic/coherence.log 2>&1 &
echo "  started: coherence  (log: logs/basic/coherence.log)"

echo ""
echo "All launched. Check logs in logs/basic/"
echo "Results: grep 'Exiting @ tick\|PASS\|FAIL\|Hello' logs/basic/*.log"
