#!/usr/bin/env bash
# test_cxl_zen4c_tuned.sh — Zen 4c latency 최대한 반영한 CXL 실험
#
# 가정: victim(CPU0) → DRAM 112ns (pool 0)
#       aggressor(CPU1-3) → CXL 224ns (pool 1)
#
# Zen 4c 매핑:
#   gem5 L1 (256KiB)  = Zen 4c L1(32KB) + L2(1MB) 통합 private
#   gem5 L2 (4MiB)    = Zen 4c L3 shared CCX
#
# 조정값 (vs 기본):
#   --cpu-clock=3.1GHz   (Zen 4c single-thread boost)
#   캐시 latency (컨트롤러 = sys-clock 1GHz = 1ns/cyc, 증분 입력):
#     --l1-latency=3  → sim L1 누적 3cyc(3ns)   = 서버 L1·L2 평균 @3.1GHz
#     --l2-latency=14 → sim L2 누적 3+14=17cyc(17ns) = 서버 L3 @3.1GHz
#   DRAM=112ns(실측), CXL=224ns(≈DRAM×2, 통상 CXL 페널티) — 절대 ns
#
# Usage: ./test_cxl_zen4c_tuned.sh [all|A|B|C|D|E|F|G|results]

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEM5="${GEM5:-$ROOT/build_amd_zen4_PF/gem5.opt}"
CFG="$ROOT/configs/deprecated/example/se.py"
BASE_COMMON="--ruby --cpu-type=O3CPU --num-cpus=4 \
  --cpu-clock=3.1GHz \
  --l1-latency=3 --l2-latency=14 \
  --l1d_size=256KiB --l1d_assoc=8 \
  --l1i_size=64KiB  --l1i_assoc=8 \
  --mem-type=SimpleMemory \
  --mem-size=2GiB --cxl-mem-size=1GiB \
  --dram-latency=112ns --cxl-latency=224ns"
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

    # victim_only: aggressor 없음 → variant(baseline/pf/llc)와 무관하게 동일.
    # 한 번만 돌려서 모든 variant의 slowdown 분모로 공유한다.
    mkdir -p "${outbase}/victim_only"
    $GEM5 --outdir="${outbase}/victim_only" $CFG $common \
        -c "$ROOT/testcase/dirtax/victim;$ROOT/testcase/dirtax/dummy;$ROOT/testcase/dirtax/dummy;$ROOT/testcase/dirtax/dummy" \
        --options "${v_kb} ${iters};;;" \
        > "${outbase}/victim_only.log" 2>&1 &
    echo "  started: victim_only [PID $!]"

    # llcbypass(H2-only) 제외: diff_L3엔 보호할 공유 L3가 없어 PF churn만 증폭됨.
    # 필요 시 아래 loop와 case에 llcbypass를 되살리면 됨.
    for variant in baseline pfbypass pf_llc_bypass; do
        local vbin dbin extra
        case "$variant" in
            baseline)      vbin="dirtax"; dbin="dirtax";   extra="" ;;
            pfbypass)      vbin="dirtax"; dbin="dutyfree"; extra="--pf-streaming-bypass" ;;                          # H3
          # llcbypass)     vbin="dirtax"; dbin="dutyfree"; extra="--llc-streaming-bypass" ;;                         # H2 (disabled)
            pf_llc_bypass) vbin="dirtax"; dbin="dutyfree"; extra="--pf-streaming-bypass --llc-streaming-bypass" ;;  # H2+H3
        esac
        local d="${outbase}/${variant}"
        mkdir -p "${d}/diff_L3" "${d}/same_L3"

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

def ticks(p):    return stat(p, "simTicks")
def run_done(p): return ticks(p) is not None    # stats.txt 존재 & sim 완료
def pf_repl(p):  return stat(p, "system.ruby.Directory_Controller.PF_Repl")
def l2_miss(p):  return stat(p, "system.cp_cntrl0.L2cache.m_demand_misses")

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
# (subdir, column tag) — bl baseline / pf H3 / llc H2 / pfllc H2+H3
# llcbypass(H2-only) 비활성: 실행 루프에서 제외됨. 되살리려면 아래 줄 주석 해제.
VARIANTS = [("baseline","bl"), ("pfbypass","pf"),
          # ("llcbypass","llc"),
            ("pf_llc_bypass","pfllc")]
PLACES   = [("diff_L3","diff"), ("same_L3","same")]
HDR = ["Case"] + [f"{tag}/{pl}" for _, tag in VARIANTS for _, pl in PLACES]

MISS = "-"   # run not executed yet

def slowdown(d, sub, place):
    p, vo = d/sub/place, ticks(d/"victim_only")
    if not run_done(p) or not vo: return MISS
    return f"{ticks(p)/vo:.3f}"

def count(fn):
    # run 완료 후 해당 stat이 없으면(=gem5가 0값 stat 생략) 0으로 표기.
    def f(d, sub, place):
        p = d/sub/place
        if not run_done(p): return MISS
        v = fn(p)
        return "0" if v is None else f"{int(v)}"
    return f

def build(cellfn):
    rows = [HDR]
    for k, label in CASES.items():
        d = base / label
        rows.append([k] + [cellfn(d, sub, place)
                           for sub, _ in VARIANTS for place, _ in PLACES])
    return rows

TABLES = [
    ("Table 1: Victim Slowdown (ticks / victim_only)", build(slowdown)),
    ("Table 2: PF Replacement Count",                  build(count(pf_repl))),
    ("Table 3: Victim L2 Miss Count",                  build(count(l2_miss))),
]

def pretty(rows):
    w = [max(len(r[c]) for r in rows) for c in range(len(rows[0]))]
    lines = []
    for ri, r in enumerate(rows):
        cells = [r[0].ljust(w[0])] + [r[c].rjust(w[c]) for c in range(1, len(r))]
        lines.append("  ".join(cells))
        if ri == 0:
            lines.append("  ".join("-"*w[c] for c in range(len(r))))
    return "\n".join(lines)

# 화면: 정렬된 표
for title, rows in TABLES:
    print(f"\n{title}")
    print(pretty(rows))

# 파일: tab-separated (기계 판독용)
tsv = []
for title, rows in TABLES:
    tsv.append(title)
    tsv += ["\t".join(r) for r in rows]
    tsv.append("")
out.write_text("\n".join(tsv) + "\n")
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
