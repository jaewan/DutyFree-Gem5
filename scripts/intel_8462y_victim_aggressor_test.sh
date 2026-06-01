#!/usr/bin/env bash
# Intel Xeon 8462Y+ (Sapphire Rapids) -like CHI experiment
#
# Goal: reproduce "LLC fit ratio predicts streaming tax magnitude" from
#       "Separate Prefetching from Allocation for Immutable CXL Streams"
#
# Intel 8462Y+ relevant params:
#   L1D: 48KiB 12-way,  L1I: 32KiB 8-way,  L2: 2MiB 16-way
#   LLC: 60MB total / 32 tiles = ~1.875MiB per CHA
#   Here we use 8 HNF nodes × 2MiB = 16MiB total (scaled-down, preserves ratios)
#
# Victim working-set sweep (argv[1] = size_kb):
#   [1] WS = 512KB  → fits in L2 (2MiB),   fit_ratio ≈ 0  → no tax expected
#   [2] WS = 4MB    → 25% of 16MB LLC,     fit_ratio ≈ 0.25
#   [3] WS = 8MB    → 50% of 16MB LLC,     fit_ratio ≈ 0.50
#   [4] WS = 16MB   → 100% of 16MB LLC,    fit_ratio ≈ 1.0
#   [5] WS = 24MB   → overflows 16MB LLC   fit_ratio > 1  → victim spills
#
# Aggressor: 3 CPUs each scanning 8MB (argv[1] = size_mb) sequentially.
#   3 × 8MB = 24MB > 16MB LLC → guaranteed LLC pressure
#   Infinite loop — terminated by victim's gem5_exit.
#
# Layout (8 CPUs total):
#   CPU0: victim   CPU1: dummy  CPU2: aggressor  CPU3: dummy
#   CPU4: aggressor CPU5: dummy  CPU6: aggressor  CPU7: dummy

mkdir -p /home/naivete/DutyFree-Gem5-pakeunji/logs/intel_dirtax

CHI_COMMON="/home/naivete/DutyFree-Gem5-pakeunji/configs/deprecated/example/se.py
    --ruby --topology=Pt2Pt
    --num-l3caches=8 --num-dirs=1
    --cpu-type=TimingSimpleCPU --num-cpus=8
    --l1d_size=48KiB --l1d_assoc=12
    --l1i_size=32KiB --l1i_assoc=8
    --l2_size=2MiB   --l2_assoc=16
    --l3_size=2MiB   --l3_assoc=16"

ROOT=/home/naivete/DutyFree-Gem5-pakeunji

# 8 binaries: victim dummy aggressor dummy aggressor dummy aggressor dummy
PROGS="$ROOT/testcase/dirtax/victim;$ROOT/testcase/dirtax/dummy;$ROOT/testcase/dirtax/aggressor;$ROOT/testcase/dirtax/dummy;$ROOT/testcase/dirtax/aggressor;$ROOT/testcase/dirtax/dummy;$ROOT/testcase/dirtax/aggressor;$ROOT/testcase/dirtax/dummy"

AGG_OPTS="8.0"   # 8MB sequential, infinite loop

run_case() {
    local label="$1"
    local victim_n="$2"
    local victim_iters="$3"
    local tag="$4"
    local outdir="/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_dirtax/${tag}_m5out"
    local logfile="/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_dirtax/${tag}.log"

    # victim opts;dummy;;aggressor opts;;aggressor opts;;aggressor opts;
    local OPTS="${victim_n} ${victim_iters};;;${AGG_OPTS};;${AGG_OPTS};;${AGG_OPTS};"

    echo "=== ${label} ==="
    echo "  victim size_kb=${victim_n} ITERS=${victim_iters}"
    /home/naivete/DutyFree-Gem5-pakeunji/build_X86_CHI/gem5.opt --outdir="${outdir}" \
        ${CHI_COMMON} \
        -c "${PROGS}" \
        -o "${OPTS}" \
        > "${logfile}" 2>&1

    echo "  $(grep 'Exiting @ tick' ${logfile} | tail -1)"
    echo "--- victim (CPU0) stats ---"
    grep "system\.cpu0\.numCycles" "${outdir}/stats.txt"     | awk '{printf "  numCycles: %s\n", $2}'
    grep "system\.cpu0\.cpi"       "${outdir}/stats.txt"     | head -1 | awk '{printf "  CPI:       %s\n", $2}'
    echo ""
}

# Baseline: victim alone (2 CPUs)
run_baseline() {
    local label="$1"
    local victim_n="$2"
    local victim_iters="$3"
    local tag="$4"
    local outdir="/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_dirtax/${tag}_m5out"
    local logfile="/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_dirtax/${tag}.log"

    echo "=== ${label} (baseline, no aggressors) ==="
    /home/naivete/DutyFree-Gem5-pakeunji/build_X86_CHI/gem5.opt --outdir="${outdir}" \
        /home/naivete/DutyFree-Gem5-pakeunji/configs/deprecated/example/se.py \
        --ruby --topology=Pt2Pt \
        --num-l3caches=8 --num-dirs=1 \
        --cpu-type=TimingSimpleCPU --num-cpus=2 \
        --l1d_size=48KiB --l1d_assoc=12 \
        --l1i_size=32KiB --l1i_assoc=8 \
        --l2_size=2MiB   --l2_assoc=16 \
        --l3_size=2MiB   --l3_assoc=16 \
        -c "$ROOT/testcase/dirtax/victim;$ROOT/testcase/dirtax/dummy" \
        -o "${victim_n} ${victim_iters};" \
        > "${logfile}" 2>&1

    echo "  $(grep 'Exiting @ tick' ${logfile} | tail -1)"
    grep "system\.cpu0\.numCycles" "${outdir}/stats.txt" | awk '{printf "  numCycles (alone): %s\n", $2}'
    echo ""
}

ITERS=65536

echo "===== Intel 8462Y+-like LLC fit ratio experiment ====="
echo "  LLC: 8 HNFs × 2MiB = 16MiB total"
echo "  Aggressors: 3 × 8MB sequential (24MB > LLC)"
echo ""

# --- Baselines (alone) ---
run_baseline "WS=512KB  alone"  512   ${ITERS} "alone_512k"
run_baseline "WS=4MB    alone"  4096  ${ITERS} "alone_4m"
run_baseline "WS=8MB    alone"  8192  ${ITERS} "alone_8m"
run_baseline "WS=16MB   alone"  16384 ${ITERS} "alone_16m"
run_baseline "WS=24MB   alone"  24576 ${ITERS} "alone_24m"

# --- With aggressors ---
run_case "WS=512KB  + aggressors (fit_ratio≈0)"    512   ${ITERS} "with_512k"
run_case "WS=4MB    + aggressors (fit_ratio≈0.25)"  4096  ${ITERS} "with_4m"
run_case "WS=8MB    + aggressors (fit_ratio≈0.50)"  8192  ${ITERS} "with_8m"
run_case "WS=16MB   + aggressors (fit_ratio≈1.0)"   16384 ${ITERS} "with_16m"
run_case "WS=24MB   + aggressors (fit_ratio>1)"     24576 ${ITERS} "with_24m"

# --- Summary ---
echo "===== Summary: victim CPI slowdown by LLC fit ratio ====="
printf "%-10s  %-12s  %-12s  %-10s  %s\n" "WS" "CPI(alone)" "CPI(w/agg)" "slowdown" "fit_ratio"

summarize() {
    local ws="$1" tag_a="$2" tag_w="$3" fit="$4"
    cyc_a=$(grep "system\.cpu0\.numCycles" /home/naivete/DutyFree-Gem5-pakeunji/logs/intel_dirtax/${tag_a}_m5out/stats.txt | awk '{print $2}')
    cyc_w=$(grep "system\.cpu0\.numCycles" /home/naivete/DutyFree-Gem5-pakeunji/logs/intel_dirtax/${tag_w}_m5out/stats.txt | awk '{print $2}')
    cpi_a=$(grep "system\.cpu0\.cpi" /home/naivete/DutyFree-Gem5-pakeunji/logs/intel_dirtax/${tag_a}_m5out/stats.txt | head -1 | awk '{print $2}')
    cpi_w=$(grep "system\.cpu0\.cpi" /home/naivete/DutyFree-Gem5-pakeunji/logs/intel_dirtax/${tag_w}_m5out/stats.txt | head -1 | awk '{print $2}')
    if [ -n "$cyc_a" ] && [ -n "$cyc_w" ]; then
        slowdown=$(awk "BEGIN {printf \"%.3f\", ${cyc_w}/${cyc_a}}")
    else
        slowdown="n/a"
    fi
    printf "%-10s  %-12s  %-12s  %-10s  %s\n" "${ws}" "${cpi_a}" "${cpi_w}" "${slowdown}x" "${fit}"
}

summarize "512KB"  "alone_512k"  "with_512k"  "≈0"
summarize "4MB"    "alone_4m"    "with_4m"    "≈0.25"
summarize "8MB"    "alone_8m"    "with_8m"    "≈0.50"
summarize "16MB"   "alone_16m"   "with_16m"   "≈1.0"
summarize "24MB"   "alone_24m"   "with_24m"   ">1.0"
