#!/usr/bin/env bash
# probe_test.sh
# Section 1: Private  - 4 independent latency_bench processes (one per CPU)
# Section 2: Shared   - 1 shared_bench with 4 threads (all CorePairs access same array)
#
# Compare broadcast (Step 4) vs targeted (Step 5):
#   Private:  broadcast ~3.0  → targeted ~1.0  (big improvement)
#   Shared:   broadcast ~3.0  → targeted ~3.0  (no improvement, data genuinely shared)

mkdir -p logs/probe

echo "=== Launching probe tests in parallel ==="

# ── Section 1: Private ──────────────────────────────────────────────────────
build_amd_zen4_PF/gem5.opt --outdir=logs/probe/private_m5out \
  configs/deprecated/example/se.py \
  --ruby --cpu-type=O3CPU --num-cpus=4 \
  --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
  --mem-type=SimpleMemory --l2-latency=9 \
  -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
  -o "524288 324011 512 r 8;524288 324011 512 r 8;524288 324011 512 r 8;524288 324011 512 r 8" \
  > logs/probe/private.log 2>&1 &
echo "  started: private  (log: logs/probe/private.log)"

# ── Section 2: Shared ───────────────────────────────────────────────────────
build_amd_zen4_PF/gem5.opt --outdir=logs/probe/shared_m5out \
  configs/deprecated/example/se.py \
  --ruby --cpu-type=O3CPU --num-cpus=4 \
  --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
  --mem-type=SimpleMemory --l2-latency=9 \
  -c testcase/latency/shared_bench \
  -o "262144 324011 4096 4" \
  > logs/probe/shared.log 2>&1 &
echo "  started: shared  (log: logs/probe/shared.log)"

echo ""
echo "Waiting for both to finish..."
wait

echo ""
echo "=== [Private] 4 independent workloads (one per CPU) ==="
grep "Exiting @ tick" logs/probe/private.log || true
echo "--- Private Probe Counts ---"
grep "dir_cntrl0.probeToCore.m_msg_count" logs/probe/private_m5out/stats.txt | awk '{print "Dir probes sent:     ", $2}'
grep "cp_cntrl0.probeToCore.m_msg_count" logs/probe/private_m5out/stats.txt | awk '{print "CorePair0 received:  ", $2}'
grep "cp_cntrl1.probeToCore.m_msg_count" logs/probe/private_m5out/stats.txt | awk '{print "CorePair1 received:  ", $2}'
grep "cp_cntrl2.probeToCore.m_msg_count" logs/probe/private_m5out/stats.txt | awk '{print "CorePair2 received:  ", $2}'
grep "cp_cntrl3.probeToCore.m_msg_count" logs/probe/private_m5out/stats.txt | awk '{print "CorePair3 received:  ", $2}'

echo ""
echo "=== [Shared] 4 threads sharing the same array ==="
grep "Exiting @ tick" logs/probe/shared.log || true
echo "--- Shared Probe Counts ---"
grep "dir_cntrl0.probeToCore.m_msg_count" logs/probe/shared_m5out/stats.txt | awk '{print "Dir probes sent:     ", $2}'
grep "cp_cntrl0.probeToCore.m_msg_count" logs/probe/shared_m5out/stats.txt | awk '{print "CorePair0 received:  ", $2}'
grep "cp_cntrl1.probeToCore.m_msg_count" logs/probe/shared_m5out/stats.txt | awk '{print "CorePair1 received:  ", $2}'
grep "cp_cntrl2.probeToCore.m_msg_count" logs/probe/shared_m5out/stats.txt | awk '{print "CorePair2 received:  ", $2}'
grep "cp_cntrl3.probeToCore.m_msg_count" logs/probe/shared_m5out/stats.txt | awk '{print "CorePair3 received:  ", $2}'

echo ""
echo "# Step 5 후 예상:"
echo "#   Private: Avg ~1.0  (targeted to owning CorePair only)"
echo "#   Shared:  Avg ~3.0  (all CorePairs share the data, broadcast = targeted)"
