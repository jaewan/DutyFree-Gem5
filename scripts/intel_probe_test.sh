#!/usr/bin/env bash
# CHI protocol version of probe_test.sh
#
# CHI snoop stats are on the HNF (Home Node):
#   system.ruby.hnf0.cntrl.snpOut.m_msg_count  -- snoops sent by HNF
#   system.ruby.rnf*.cntrl*.snpIn.m_msg_count  -- snoops received per RNF CPU
#
# Section 1: Private  - 4 independent latency_bench (each CPU has its own array)
# Section 2: Shared   - 1 shared_bench with 4 threads (same array, all CPUs)
#
# Expected after CHI targeted-snoop optimization:
#   Private: HNF sends snoops only to the owning RNF → low snoop count per CPU
#   Shared:  HNF must snoop all sharers → high snoop count per CPU

mkdir -p logs/intel_probe

echo "=== Launching CHI probe tests in parallel ==="

# ── Section 1: Private ────────────────────────────────────────────────────────
build_X86_CHI/gem5.opt --outdir=logs/intel_probe/private_m5out \
    configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=4 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "524288 324011 512 r 8;524288 324011 512 r 8;524288 324011 512 r 8;524288 324011 512 r 8" \
    > logs/intel_probe/private.log 2>&1 &
echo "  started: private  (log: logs/intel_probe/private.log)"

# ── Section 2: Shared ─────────────────────────────────────────────────────────
build_X86_CHI/gem5.opt --outdir=logs/intel_probe/shared_m5out \
    configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=4 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c testcase/latency/shared_bench \
    -o "262144 324011 4096 4" \
    > logs/intel_probe/shared.log 2>&1 &
echo "  started: shared  (log: logs/intel_probe/shared.log)"

echo ""
echo "Waiting for both to finish..."
wait

echo ""
echo "=== [Private] 4 independent workloads (one per CPU) ==="
grep "Exiting @ tick" logs/intel_probe/private.log || true
echo "--- CHI Snoop Counts (Private) ---"
grep "system\.ruby\.hnf\.cntrl\.snpOut\.m_msg_count" logs/intel_probe/private_m5out/stats.txt | awk '{print "HNF snpOut:          ", $2}' || echo "HNF snpOut:           0"
grep "system\.cpu0\.l1d\.snpIn\.m_msg_count"  logs/intel_probe/private_m5out/stats.txt | awk '{print "CPU0 l1d snpIn:      ", $2}'
grep "system\.cpu1\.l1d\.snpIn\.m_msg_count"  logs/intel_probe/private_m5out/stats.txt | awk '{print "CPU1 l1d snpIn:      ", $2}'
grep "system\.cpu2\.l1d\.snpIn\.m_msg_count"  logs/intel_probe/private_m5out/stats.txt | awk '{print "CPU2 l1d snpIn:      ", $2}'
grep "system\.cpu3\.l1d\.snpIn\.m_msg_count"  logs/intel_probe/private_m5out/stats.txt | awk '{print "CPU3 l1d snpIn:      ", $2}'

echo ""
echo "=== [Shared] 4 threads sharing the same array ==="
grep "Exiting @ tick" logs/intel_probe/shared.log || true
echo "--- CHI Snoop Counts (Shared) ---"
grep "system\.ruby\.hnf\.cntrl\.snpOut\.m_msg_count" logs/intel_probe/shared_m5out/stats.txt | awk '{print "HNF snpOut:          ", $2}' || echo "HNF snpOut:           0"
grep "system\.cpu0\.l1d\.snpIn\.m_msg_count"  logs/intel_probe/shared_m5out/stats.txt | awk '{print "CPU0 l1d snpIn:      ", $2}'
grep "system\.cpu1\.l1d\.snpIn\.m_msg_count"  logs/intel_probe/shared_m5out/stats.txt | awk '{print "CPU1 l1d snpIn:      ", $2}'
grep "system\.cpu2\.l1d\.snpIn\.m_msg_count"  logs/intel_probe/shared_m5out/stats.txt | awk '{print "CPU2 l1d snpIn:      ", $2}'
grep "system\.cpu3\.l1d\.snpIn\.m_msg_count"  logs/intel_probe/shared_m5out/stats.txt | awk '{print "CPU3 l1d snpIn:      ", $2}'

echo ""
echo "# 예상:"
echo "#   Private: HNF가 owning RNF에만 snoop → 다른 RNF는 수신 거의 없음"
echo "#   Shared:  모든 RNF가 sharer → HNF가 전체에 snoop"
echo ""
echo "# 실제 stat 경로 (CHI):"
echo "#   HNF:  system.ruby.hnf.cntrl.snpOut.m_msg_count"
echo "#   CPU:  system.cpuN.l1d.snpIn.m_msg_count"
