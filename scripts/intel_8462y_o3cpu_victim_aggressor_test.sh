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

mkdir -p /home/naivete/DutyFree-Gem5-pakeunji/logs/intel_dirtax_o3

CHI_COMMON="/home/naivete/DutyFree-Gem5-pakeunji/configs/deprecated/example/se.py
    --ruby --topology=Pt2Pt
    --num-l3caches=8 --num-dirs=1
    --cpu-type=O3CPU --num-cpus=8 --cpu-clock=2.8GHz
    --l1d_size=48KiB --l1d_assoc=12
    --l1i_size=32KiB --l1i_assoc=8
    --l2_size=2MiB   --l2_assoc=16
    --l3_size=2MiB   --l3_assoc=16
    --mem-type=SimpleMemory
    --mem-size=2GiB --cxl-mem-size=1GiB
    --dram-latency=107ns --cxl-latency=214ns"

ROOT=/home/naivete/DutyFree-Gem5-pakeunji

# 8 CPUs: CPU0=victim, CPU1-7=aggressor (no dummy)
PROGS="$ROOT/testcase/dirtax/victim;$ROOT/testcase/dirtax/aggressor;$ROOT/testcase/dirtax/aggressor;$ROOT/testcase/dirtax/aggressor;$ROOT/testcase/dirtax/aggressor;$ROOT/testcase/dirtax/aggressor;$ROOT/testcase/dirtax/aggressor;$ROOT/testcase/dirtax/aggressor"

AGG_OPTS="8.0"   # 8MB sequential, infinite loop

run_case() {
    local label="$1"
    local victim_n="$2"
    local victim_iters="$3"
    local tag="$4"
    local outdir="/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_dirtax_o3/${tag}_m5out"
    local logfile="/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_dirtax_o3/${tag}.log"

    # victim;aggressor×7
    local OPTS="${victim_n} ${victim_iters};${AGG_OPTS};${AGG_OPTS};${AGG_OPTS};${AGG_OPTS};${AGG_OPTS};${AGG_OPTS};${AGG_OPTS}"

    echo "=== ${label} ==="
    echo "  victim size_kb=${victim_n} ITERS=${victim_iters}"
    /home/naivete/DutyFree-Gem5-pakeunji/build_X86_CHI/gem5.opt --outdir="${outdir}" \
        ${CHI_COMMON} \
        -c "${PROGS}" \
        -o "${OPTS}" \
        > "${logfile}" 2>&1 &
    echo "  started: ${tag} [PID $!]"
}

# Baseline: victim alone (CPU0=victim, CPU1-7=dummy)
run_baseline() {
    local label="$1"
    local victim_n="$2"
    local victim_iters="$3"
    local tag="$4"
    local outdir="$ROOT/logs/intel_dirtax_o3/${tag}_m5out"
    local logfile="$ROOT/logs/intel_dirtax_o3/${tag}.log"
    local D="$ROOT/testcase/dirtax/dummy"

    echo "=== ${label} (baseline, no aggressors) ==="
    /home/naivete/DutyFree-Gem5-pakeunji/build_X86_CHI/gem5.opt --outdir="${outdir}" \
        ${CHI_COMMON} \
        -c "$ROOT/testcase/dirtax/victim;$D;$D;$D;$D;$D;$D;$D" \
        -o "${victim_n} ${victim_iters};;;;;;;;" \
        > "${logfile}" 2>&1 &
    echo "  started: ${tag} [PID $!]"
}

# nagg aggressors (1-7): CPU0=victim, CPU1..nagg=aggressor, rest=dummy
run_nagg() {
    local nagg="$1"
    local victim_n="$2"
    local victim_iters="$3"
    local ws_tag="$4"
    local V="$ROOT/testcase/dirtax/victim"
    local A="$ROOT/testcase/dirtax/aggressor"
    local D="$ROOT/testcase/dirtax/dummy"
    local outdir="$ROOT/logs/intel_dirtax_o3/nagg${nagg}/${ws_tag}_m5out"
    local logfile="$ROOT/logs/intel_dirtax_o3/nagg${nagg}/${ws_tag}.log"

    local progs="$V"
    local opts="${victim_n} ${victim_iters}"
    for ((i=1; i<=nagg; i++));    do progs="$progs;$A"; opts="$opts;${AGG_OPTS}"; done
    for ((i=nagg+1; i<=7; i++)); do progs="$progs;$D"; opts="$opts;"; done

    mkdir -p "$ROOT/logs/intel_dirtax_o3/nagg${nagg}"
    /home/naivete/DutyFree-Gem5-pakeunji/build_X86_CHI/gem5.opt --outdir="${outdir}" \
        ${CHI_COMMON} \
        -c "${progs}" \
        -o "${opts}" \
        > "${logfile}" 2>&1 &
    echo "  started: nagg${nagg}/${ws_tag} [PID $!]"
}

ITERS=3145728

WS_TAGS=("512k:512:≈0%" "2m:2048:≈12.5%" "4m:4096:≈25%" "8m:8192:≈50%" "12m:12288:≈75%" "16m:16384:≈100%" "24m:24576:>100%")

# ── 결과 출력 ────────────────────────────────────────────────────────────────
print_results() {
python3 - << 'PYEOF'
from pathlib import Path

BASE = Path("/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_dirtax_o3")
WS   = [("512k","≈0%"),("2m","≈12.5%"),("4m","≈25%"),
        ("8m","≈50%"),("12m","≈75%"),("16m","≈100%"),("24m",">100%")]

def ticks(p):
    try:
        for line in open(p/"stats.txt"):
            if line.startswith("simTicks "):
                return int(line.split()[1])
    except: pass
    return None

def sv(c, b): return f"{c/b:.3f}" if c and b else ""

T = "\t"
# Header
header = ["ws","fit_ratio","alone"] + [f"nagg{n}" for n in range(1,8)]
print(T.join(header))

for ws_tag, fit in WS:
    alone = ticks(BASE / f"alone_{ws_tag}_m5out")
    row = [ws_tag, fit, f"{alone}" if alone else ""]
    for n in range(1, 8):
        w = ticks(BASE / f"nagg{n}" / f"ws_{ws_tag}_m5out")
        row.append(sv(w, alone))
    print(T.join(row))
PYEOF
}

# ── 실행 ─────────────────────────────────────────────────────────────────────
run_all() {
    echo "===== Intel 8462Y+-like LLC fit ratio experiment ====="
    echo "  LLC: 8 HNFs × 2MiB = 16MiB total"
    echo "  순서: baseline → nagg1 → nagg2 → ... → nagg7 (set 내 7개 동시)"
    echo ""

    # Phase 0: Baselines (victim alone, 7개 동시)
    echo "--- Phase 0: baselines (7개 동시) ---"
    for entry in "${WS_TAGS[@]}"; do
        IFS=: read -r tag size fit <<< "$entry"
        run_baseline "WS=${tag} alone" $size ${ITERS} "alone_${tag}"
    done
    wait
    echo "  baselines done."

    # Phase 1..7: nagg sweep (set 내 7개 동시, set 간 순차)
    for nagg in 1 2 3 4 5 6 7; do
        echo "--- Phase ${nagg}: nagg=${nagg} (7개 동시) ---"
        for entry in "${WS_TAGS[@]}"; do
            IFS=: read -r tag size fit <<< "$entry"
            run_nagg $nagg $size ${ITERS} "ws_${tag}"
        done
        wait
        echo "  nagg=${nagg} done."
    done

    echo "All jobs done."
    echo ""
    print_results
}

# ── main ─────────────────────────────────────────────────────────────────────
case "${1:-all}" in
    all)     run_all ;;
    results) print_results ;;
    *)       echo "Usage: $0 [all|results]"; exit 1 ;;
esac
