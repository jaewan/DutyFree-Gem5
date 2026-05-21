#!/usr/bin/env bash

mkdir -p logs/victim_aggressor

# ── Scenario 1: victim + dummy (no aggressors) ─────────────────────────────
echo ""
echo "=== [1] victim + dummy  (2 CPUs, no aggressors) ==="

build_amd_zen4_PF_broadcast/gem5.opt --outdir=logs/victim_aggressor/alone_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=2 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c "testcase/dirtax/victim;testcase/dirtax/dummy" \
    -o ";" \
    2>&1 | tee logs/victim_aggressor/alone.log | grep -E "victim|aggressor|Exiting|FAIL|panic" || true

echo "--- Stats (CPU0 = victim) ---"
grep -E "^system\.cpu0\.numCycles\s"        logs/victim_aggressor/alone_m5out/stats.txt 2>/dev/null || echo "  numCycles: (n/a)"
grep -E "^system\.cpu0\.cpi\b"              logs/victim_aggressor/alone_m5out/stats.txt 2>/dev/null || echo "  cpi: (n/a)"
grep -E "^system\.cpu0\.ipc\b"              logs/victim_aggressor/alone_m5out/stats.txt 2>/dev/null || echo "  ipc: (n/a)"
grep -E "^system\.cpu0\.(numInsts|committedInsts)\s" logs/victim_aggressor/alone_m5out/stats.txt 2>/dev/null | head -1 || echo "  numInsts: (n/a)"
grep -E "^sim_ticks\s"                      logs/victim_aggressor/alone_m5out/stats.txt 2>/dev/null || echo "  sim_ticks: (n/a)"
grep -E "^sim_seconds\s"                    logs/victim_aggressor/alone_m5out/stats.txt 2>/dev/null || echo "  sim_seconds: (n/a)"


# ── Scenario 2: victim + 3 aggressors (8 CPUs) ────────────────────────────
echo ""
echo "=== [2] victim + 3 aggressors  (8 CPUs) ==="

build_amd_zen4_PF_broadcast/gem5.opt --outdir=logs/victim_aggressor/with_m5out \
    configs/deprecated/example/se.py \
    --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 --l2_size=16MiB --l2_assoc=16 \
    -c "testcase/dirtax/victim;testcase/dirtax/dummy;testcase/dirtax/aggressor;testcase/dirtax/dummy;testcase/dirtax/aggressor;testcase/dirtax/dummy;testcase/dirtax/aggressor;testcase/dirtax/dummy" \
    -o ";;;;;;;" \
    2>&1 | tee logs/victim_aggressor/with.log | grep -E "victim|aggressor|Exiting|FAIL|panic" || true

echo "--- Stats (CPU0 = victim) ---"
grep -E "^system\.cpu0\.numCycles\s"        logs/victim_aggressor/with_m5out/stats.txt 2>/dev/null || echo "  numCycles: (n/a)"
grep -E "^system\.cpu0\.cpi\b"              logs/victim_aggressor/with_m5out/stats.txt 2>/dev/null || echo "  cpi: (n/a)"
grep -E "^system\.cpu0\.ipc\b"              logs/victim_aggressor/with_m5out/stats.txt 2>/dev/null || echo "  ipc: (n/a)"
grep -E "^system\.cpu0\.(numInsts|committedInsts)\s" logs/victim_aggressor/with_m5out/stats.txt 2>/dev/null | head -1 || echo "  numInsts: (n/a)"
grep -E "^sim_ticks\s"                      logs/victim_aggressor/with_m5out/stats.txt 2>/dev/null || echo "  sim_ticks: (n/a)"
grep -E "^sim_seconds\s"                    logs/victim_aggressor/with_m5out/stats.txt 2>/dev/null || echo "  sim_seconds: (n/a)"


# ── Comparison ─────────────────────────────────────────────────────────────
echo ""
echo "=== Comparison: victim (CPU0) performance degradation ==="
CYCLES_ALONE=$(grep -E "^system\.cpu0\.numCycles\s" logs/victim_aggressor/alone_m5out/stats.txt 2>/dev/null | awk '{print $2}')
CYCLES_WITH=$(grep -E "^system\.cpu0\.numCycles\s"  logs/victim_aggressor/with_m5out/stats.txt  2>/dev/null | awk '{print $2}')
echo "  [1] alone  numCycles: ${CYCLES_ALONE:-(n/a)}"
echo "  [2] w/agg  numCycles: ${CYCLES_WITH:-(n/a)}"
if [ -n "$CYCLES_ALONE" ] && [ -n "$CYCLES_WITH" ] && [ "$CYCLES_ALONE" -gt 0 ] 2>/dev/null; then
    awk -v a="$CYCLES_ALONE" -v b="$CYCLES_WITH" \
        'BEGIN { printf "  Slowdown: %.2fx  (degradation: %.1f%%)\n", b/a, (b-a)/a*100 }'
else
    echo "  (cannot compute slowdown — check stat name with: grep -i cycles logs/victim_aggressor/alone_m5out/stats.txt | head -10)"
fi
