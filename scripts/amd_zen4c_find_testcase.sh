#!/usr/bin/env bash
# find_testcase.sh — comprehensive baseline sweep
#
# Victim:     16K / 32K / 64K / 128K / 512K / 1M / 2M / 3M / 3686K / 4M
# Aggressor:  8M / 16M
# PF:         oracle(32M) → 16M → 8M → 4M, assoc sweep
# cpu-clock:  2.25GHz   (Zen 4c)
# CXL:        DRAM=150ns victim, CXL=300ns aggressor
# Conditions: victim_only / diff_L3 / same_L3   (baseline only)
# Concurrency: max 32 gem5 processes at a time
#
# Usage: ./amd_zen4c_find_testcase.sh [all|results]

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEM5="${GEM5:-$ROOT/build_amd_zen4_PF/gem5.opt}"
CFG="$ROOT/configs/deprecated/example/se.py"
LOGBASE="$ROOT/logs/find_testcase"
export LOGBASE   # print_results의 python heredoc에서 참조
VICTIM="$ROOT/testcase/dirtax/victim"
AGG="$ROOT/testcase/dirtax/aggressor"
DUMMY="$ROOT/testcase/dirtax/dummy"

ITERS=3145728
MAX_JOBS=32

BASE_COMMON="--ruby --cpu-type=O3CPU --num-cpus=4
  --cpu-clock=2.25GHz
  --l1-latency=8 --l2-latency=39
  --l1d_size=256KiB --l1d_assoc=8
  --l1i_size=64KiB  --l1i_assoc=8
  --l2_size=4MiB    --l2_assoc=16
  --mem-type=SimpleMemory
  --mem-size=2GiB --cxl-mem-size=1GiB
  --dram-latency=150ns --cxl-latency=300ns"

# PF configurations: "pf_size assoc label"
PF_CONFIGS=(
    "32MiB 128 pf32m_a128"
    "16MiB 512 pf16m_a512"
    "16MiB 256 pf16m_a256"
    "16MiB 128 pf16m_a128"
    "16MiB  64 pf16m_a64"
    "16MiB  32 pf16m_a32"
    "16MiB  16 pf16m_a16"
    "8MiB  512 pf8m_a512"
    "8MiB  256 pf8m_a256"
    "8MiB  128 pf8m_a128"
    "8MiB   64 pf8m_a64"
    "8MiB   32 pf8m_a32"
    "8MiB   16 pf8m_a16"
    "4MiB  128 pf4m_a128"
    "4MiB   64 pf4m_a64"
)

mkdir -p "$LOGBASE"

throttle() {
    while [ "$(jobs -rp | wc -l)" -ge "$MAX_JOBS" ]; do
        sleep 2
    done
}

run_gem5() {
    throttle
    "$@" &
}

run_case() {
    local label="$1" v_kb="$2" agg_mb="$3" pf_size="$4" pf_assoc="$5"
    local d="$LOGBASE/$label"
    mkdir -p "$d/victim_only" "$d/diff_L3" "$d/same_L3"

    local COMMON="$BASE_COMMON --pf-size=$pf_size --pf-assoc=$pf_assoc"

    run_gem5 $GEM5 --outdir="$d/victim_only" $CFG $COMMON \
        -c "$VICTIM;$DUMMY;$DUMMY;$DUMMY" \
        --options "$v_kb $ITERS;;;" \
        > "$d/victim_only.log" 2>&1

    run_gem5 $GEM5 --outdir="$d/diff_L3" $CFG $COMMON \
        -c "$VICTIM;$DUMMY;$AGG;$DUMMY" \
        --options "$v_kb $ITERS;;$agg_mb;" \
        > "$d/diff_L3.log" 2>&1

    run_gem5 $GEM5 --outdir="$d/same_L3" $CFG $COMMON \
        -c "$VICTIM;$AGG;$DUMMY;$DUMMY" \
        --options "$v_kb $ITERS;$agg_mb;;" \
        > "$d/same_L3.log" 2>&1

    echo "  queued: $label"
}

print_results() {
python3 - << 'PYEOF'
import os
from pathlib import Path

def stat(p, key):
    try:
        for line in open(p / "stats.txt"):
            if line.startswith(key + " "):
                v = line.split()[1]
                if v not in ('nan', 'inf'): return float(v)
    except: pass
    return None

def ticks(p): return stat(p, "simTicks")
def sv(c, v): return f"{c/v:.3f}" if c and v else ""

base = Path(os.environ["LOGBASE"])
out  = base / "results.tsv"

T = "\t"
HDR = T.join(["label", "diff_L3", "same_L3", "target?"])
lines = ["find_testcase (cpu=2.25GHz, DRAM=150ns, CXL=300ns)", HDR]

for d in sorted(base.iterdir()):
    if not d.is_dir(): continue
    vo   = ticks(d / "victim_only")
    diff = sv(ticks(d / "diff_L3"), vo)
    same = sv(ticks(d / "same_L3"), vo)
    try:
        hit = "★" if float(diff) <= 2.0 and float(same) >= 3.0 else ""
    except: hit = ""
    lines.append(T.join([d.name, diff, same, hit]))

content = "\n".join(lines)
print(content)
out.write_text(content + "\n")
print(f"\n→ saved: {out}")
PYEOF
}

MODE="${1:-all}"

if [ "$MODE" = "results" ]; then
    print_results; exit 0
fi

echo "===== find_testcase sweep ====="
echo "  victim:     16K 32K 64K 128K 512K 1M 2M 3M 3686K 4M (10종)"
echo "  aggressor:  8M / 16M"
echo "  PF configs: ${#PF_CONFIGS[@]}종"
echo "  total:      $((10 * 2 * ${#PF_CONFIGS[@]})) cases × 3 conditions"
echo "  concurrent: max $MAX_JOBS"
echo ""

for v_kb in 16 32 64 128 512 1024 2048 3072 3686 4096; do
    for agg_mb in 8 16; do
        for pf_entry in "${PF_CONFIGS[@]}"; do
            pf_size=$(echo $pf_entry | awk '{print $1}')
            pf_assoc=$(echo $pf_entry | awk '{print $2}')
            pf_label=$(echo $pf_entry | awk '{print $3}')
            run_case "v${v_kb}k_a${agg_mb}m_${pf_label}" $v_kb $agg_mb $pf_size $pf_assoc
        done
    done
done

wait
echo ""
echo "All done."
echo ""
print_results
