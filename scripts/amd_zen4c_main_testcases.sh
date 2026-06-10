#!/usr/bin/env bash
# test_cxl_zen4c_tuned.sh — Zen 4c latency 최대한 반영한 CXL 실험
#
# 가정: victim(CPU0) → DRAM 150ns (pool 0)
#       aggressor(CPU1-3) → CXL 300ns (pool 1)
#
# Zen 4c 매핑:
#   gem5 L1 (256KiB)  = Zen 4c L1(32KB) + L2(1MB) 통합 private
#   gem5 L2 (4MiB)    = Zen 4c L3 shared CCX
#
# 조정값 (vs 기본):
#   --cpu-clock=3.1GHz   (Zen 4c base, boost off)
#   캐시 latency (ruby clock 2GHz = 0.5ns/cyc, 증분 입력):
#     --l1-latency=8  → sim L1 누적 8cyc(4ns)   = 서버 L1·L2 평균
#     --l2-latency=39 → sim L2 누적 8+39=47cyc(23.4ns) = 서버 L3
#   DRAM=150ns, CXL=300ns (절대 ns)
#
# Usage: ./test_cxl_zen4c_tuned.sh [all|A|B|C|D|E|F|G|results]

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEM5="${GEM5:-$ROOT/build_amd_zen4_PF/gem5.opt}"
CFG="$ROOT/configs/deprecated/example/se.py"
BASE_COMMON="--ruby --cpu-type=O3CPU --num-cpus=4 \
  --cpu-clock=3.1GHz \
  --l1-latency=8 --l2-latency=39 \
  --l1d_size=256KiB --l1d_assoc=8 \
  --l1i_size=64KiB  --l1i_assoc=8 \
  --mem-type=SimpleMemory \
  --mem-size=2GiB --cxl-mem-size=1GiB \
  --dram-latency=150ns --cxl-latency=300ns"
LOGBASE="$ROOT/logs/main_cases"
export LOGBASE   # print_results의 python heredoc에서 참조

# ── 케이스 정의 ───────────────────────────────────────────────────────────────
declare -A CASE_COMMON=(
  [A]="$BASE_COMMON --l2_size=4MiB --l2_assoc=16 --pf-size=8MiB  --pf-assoc=128"
  [B]="$BASE_COMMON --l2_size=4MiB --l2_assoc=16 --pf-size=8MiB  --pf-assoc=128"
  [C]="$BASE_COMMON --l2_size=4MiB --l2_assoc=16 --pf-size=8MiB  --pf-assoc=256"
  [D]="$BASE_COMMON --l2_size=4MiB --l2_assoc=16 --pf-size=16MiB --pf-assoc=128"
  [E]="$BASE_COMMON --l2_size=4MiB --l2_assoc=16 --pf-size=8MiB  --pf-assoc=128"
  [F]="$BASE_COMMON --l2_size=4MiB --l2_assoc=16 --pf-size=32MiB --pf-assoc=128"
  [G]="$BASE_COMMON --l2_size=4MiB --l2_assoc=16 --pf-size=32MiB --pf-assoc=128"
  [H]="$BASE_COMMON --l2_size=4MiB --l2_assoc=16 --pf-size=16MiB --pf-assoc=128"
)
declare -A CASE_VKB=([A]=3072 [B]=4096 [C]=3072 [D]=3072 [E]=3072 [F]=3072 [G]=4096 [H]=4096)
declare -A CASE_ITERS=([A]=3145728 [B]=3145728 [C]=3145728 [D]=3145728 [E]=3145728 [F]=3145728 [G]=3145728 [H]=3145728)
declare -A CASE_AGG=([A]=16 [B]=16 [C]=16 [D]=16 [E]=4 [F]=16 [G]=16 [H]=16)
declare -A CASE_LABEL=(
  [A]="v3m_a16m_pf8m_a128_L2=4M"
  [B]="v4m_a16m_pf8m_a128_L2=4M"
  [C]="v3m_a16m_pf8m_a256_L2=4M"
  [D]="v3m_a16m_pf16m_a128_L2=4M"
  [E]="v3m_a4m_pf8m_a128_L2=4M"
  [F]="v3m_a16m_pf32m_a128_L2=4M"
  [G]="v4m_a16m_pf32m_a128_L2=4M"
  [H]="v4m_a16m_pf16m_a128_L2=4M"
)

# ── 실행 함수 ─────────────────────────────────────────────────────────────────
run_case() {
    local case_id="$1"
    local common="${CASE_COMMON[$case_id]}"
    local v_kb="${CASE_VKB[$case_id]}"
    local iters="${CASE_ITERS[$case_id]}"
    local agg_mb="${CASE_AGG[$case_id]}"
    local label="${CASE_LABEL[$case_id]}"
    local outbase="${LOGBASE}/${label}"

    echo "=== Case ${case_id}: ${label} (v=${v_kb}K agg=${agg_mb}M) ==="

    for variant in baseline pfbypass pfbypass_llc; do
        local vbin dbin extra
        case "$variant" in
            baseline)    vbin="dirtax";   dbin="dirtax";   extra="" ;;
            pfbypass)    vbin="dirtax";   dbin="dutyfree"; extra="" ;;
            pfbypass_llc) vbin="dirtax";  dbin="dutyfree"; extra="--llc-streaming-bypass" ;;
        esac
        local d="${outbase}/${variant}"
        mkdir -p "${d}/victim_only" "${d}/diff_L3" "${d}/same_L3"

        $GEM5 --outdir="${d}/victim_only" $CFG $common $extra \
            -c "$ROOT/testcase/${vbin}/victim;$ROOT/testcase/${dbin}/dummy;$ROOT/testcase/${dbin}/dummy;$ROOT/testcase/${dbin}/dummy" \
            --options "${v_kb} ${iters};;;" \
            > "${d}/victim_only.log" 2>&1 &
        echo "  started: ${variant}/victim_only [PID $!]"

        $GEM5 --outdir="${d}/diff_L3" $CFG $common $extra \
            -c "$ROOT/testcase/${vbin}/victim;$ROOT/testcase/${dbin}/dummy;$ROOT/testcase/${dbin}/aggressor;$ROOT/testcase/${dbin}/dummy" \
            --options "${v_kb} ${iters};;${agg_mb};" \
            > "${d}/diff_L3.log" 2>&1 &
        echo "  started: ${variant}/diff_L3   [PID $!]"

        $GEM5 --outdir="${d}/same_L3" $CFG $common $extra \
            -c "$ROOT/testcase/${vbin}/victim;$ROOT/testcase/${dbin}/aggressor;$ROOT/testcase/${dbin}/dummy;$ROOT/testcase/${dbin}/dummy" \
            --options "${v_kb} ${iters};${agg_mb};;" \
            > "${d}/same_L3.log" 2>&1 &
        echo "  started: ${variant}/same_L3   [PID $!]"
    done
    echo ""
}

# ── 결과 출력 ─────────────────────────────────────────────────────────────────
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

def ticks(p):   return stat(p, "simTicks")
def pf_repl(p): return stat(p, "system.ruby.Directory_Controller.PF_Repl")
def l2_miss(p): return stat(p, "system.cp_cntrl0.L2cache.m_demand_misses")
def sv(c, v):   return f"{c/v:.3f}" if c and v else ""
def si(v):      return f"{int(v)}"  if v is not None else ""

T = "\t"
base = Path(os.environ["LOGBASE"])
out  = base / "results.tsv"
CASES = {
    "A (pf8m/a128)":  "v3m_a16m_pf8m_a128_L2=4M",
    "B (vic=4M)":     "v4m_a16m_pf8m_a128_L2=4M",
    "C (pf8m/a256)":  "v3m_a16m_pf8m_a256_L2=4M",
    "D (pf16m/a128)": "v3m_a16m_pf16m_a128_L2=4M",
    "E oracle":       "v3m_a4m_pf8m_a128_L2=4M",
    "F oracle":       "v3m_a16m_pf32m_a128_L2=4M",
    "G (B oracle)":   "v4m_a16m_pf32m_a128_L2=4M",
    "H (vic=4M pf16m)": "v4m_a16m_pf16m_a128_L2=4M",
}
HDR = T.join(["Case","bl/diff","bl/same","pf/diff","pf/same","pfl/diff","pfl/same"])

lines = []
lines.append("Table 1: Victim Slowdown")
lines.append(HDR)
for k, label in CASES.items():
    d = base / label
    bvo=ticks(d/"baseline/victim_only"); pvo=ticks(d/"pfbypass/victim_only"); lvo=ticks(d/"pfbypass_llc/victim_only")
    lines.append(T.join([k,
        sv(ticks(d/"baseline/diff_L3"), bvo),  sv(ticks(d/"baseline/same_L3"), bvo),
        sv(ticks(d/"pfbypass/diff_L3"), pvo),  sv(ticks(d/"pfbypass/same_L3"), pvo),
        sv(ticks(d/"pfbypass_llc/diff_L3"),lvo), sv(ticks(d/"pfbypass_llc/same_L3"),lvo)]))

lines.append("")
lines.append("Table 2: PF Replacement Count")
lines.append(HDR)
for k, label in CASES.items():
    d = base / label
    lines.append(T.join([k,
        si(pf_repl(d/"baseline/diff_L3")),  si(pf_repl(d/"baseline/same_L3")),
        si(pf_repl(d/"pfbypass/diff_L3")),  si(pf_repl(d/"pfbypass/same_L3")),
        si(pf_repl(d/"pfbypass_llc/diff_L3")), si(pf_repl(d/"pfbypass_llc/same_L3"))]))

lines.append("")
lines.append("Table 3: Victim L2 Miss Count")
lines.append(HDR)
for k, label in CASES.items():
    d = base / label
    lines.append(T.join([k,
        si(l2_miss(d/"baseline/diff_L3")),  si(l2_miss(d/"baseline/same_L3")),
        si(l2_miss(d/"pfbypass/diff_L3")),  si(l2_miss(d/"pfbypass/same_L3")),
        si(l2_miss(d/"pfbypass_llc/diff_L3")), si(l2_miss(d/"pfbypass_llc/same_L3"))]))

content = "\n".join(lines)
print(content)
out.write_text(content + "\n")
print(f"\n→ saved: {out}")
PYEOF
}

# ── command guide ───────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") <CASE|all|results>

  A B C D E F G H   run a single case
  all               run every case A-H (up to 72 gem5 procs in parallel)
  results           aggregate existing logs only -> $LOGBASE/results.tsv
                    (no simulation; run after a case/all finishes)

Prereqs (one-time):
  ./scripts/amd_zen4c_compile.sh     # build build_amd_zen4_PF/gem5.opt
  make -C testcase/dirtax            # victim / aggressor / dummy
  make -C testcase/dutyfree          # STREAMING variants

Examples:
  $(basename "$0") B          # run case B, then:
  $(basename "$0") results    # print the result tables
EOF
}

# ── main ──────────────────────────────────────────────────────────────────────
MODE="${1:-}"

case "$MODE" in
    results)            print_results; exit 0 ;;
    -h|--help|help|"")  usage; exit 0 ;;
    all|A|B|C|D|E|F|G|H) ;;                       # fall through to run
    *)                  echo "unknown argument: $MODE"; echo; usage; exit 1 ;;
esac

# prereq check (gem5 binary + testcase binaries)
[ -x "$GEM5" ] || { echo "ERROR: gem5 not found: $GEM5"; echo "  -> ./scripts/amd_zen4c_compile.sh"; exit 1; }
for b in dirtax/victim dirtax/aggressor dirtax/dummy \
         dutyfree/victim dutyfree/aggressor dutyfree/dummy; do
    [ -x "$ROOT/testcase/$b" ] || {
        echo "ERROR: testcase binary missing: testcase/$b"
        echo "  -> make -C testcase/dirtax && make -C testcase/dutyfree"; exit 1; }
done

if [ "$MODE" = "all" ]; then
    for c in A B C D E F G H; do run_case "$c"; done
else
    run_case "$MODE"
fi

wait
echo "All jobs done. Aggregate results with: $(basename "$0") results"
