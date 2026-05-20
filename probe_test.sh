#!/usr/bin/env bash
# probe_test.sh
# Run 8 private latency_bench instances (one per CPU) and report probe counts.
# Use this to compare broadcast (before Step 3) vs targeted (after Step 3).

set -e

echo "=== Running probe test (8 private workloads, one per CPU) ==="
build_pf/gem5.opt configs/deprecated/example/se.py \
  --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 \
  --l1d_size=32KiB --l1i_size=32KiB --l2_size=512KiB \
  -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
  -o "65536 40459 512 r 65536;65536 40459 512 r 65536;65536 40459 512 r 65536;65536 40459 512 r 65536;65536 40459 512 r 65536;65536 40459 512 r 65536;65536 40459 512 r 65536;65536 40459 512 r 65536" \
  2>&1 | grep "Exiting @ tick"

echo ""
echo "=== Probe Counts ==="
DIR=$(grep "dir_cntrl0.probeToCore.m_msg_count" m5out/stats.txt | awk '{print $2}')
CP0=$(grep "cp_cntrl0.probeToCore.m_msg_count" m5out/stats.txt | awk '{print $2}')
CP1=$(grep "cp_cntrl1.probeToCore.m_msg_count" m5out/stats.txt | awk '{print $2}')
CP2=$(grep "cp_cntrl2.probeToCore.m_msg_count" m5out/stats.txt | awk '{print $2}')
CP3=$(grep "cp_cntrl3.probeToCore.m_msg_count" m5out/stats.txt | awk '{print $2}')
TOTAL=$((CP0 + CP1 + CP2 + CP3))

echo "Dir probes sent:      $DIR"
echo "CorePair0 received:   $CP0"
echo "CorePair1 received:   $CP1"
echo "CorePair2 received:   $CP2"
echo "CorePair3 received:   $CP3"
echo "Total received:       $TOTAL"
echo "Avg probes per send:  $(echo "scale=2; $TOTAL / $DIR" | bc)"
echo ""
echo "# Step 3 후 'Avg probes per send' 이 1.0에 가까워져야 함 (broadcast=~3.0)"
