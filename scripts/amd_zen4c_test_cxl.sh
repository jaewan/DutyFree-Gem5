#!/usr/bin/env bash
# test_cxl.sh — CXL/DRAM latency 분리 실험
#
# 가정: victim(CPU0) → DRAM 75ns (pool 0)
#       aggressor(CPU1-3) → CXL 200ns (pool 1)
#
# main_testcases.sh와 동일 케이스, 동일 구조.
# 차이점: build_amd_zen4_PF_CXL_latency 바이너리 + CXL 옵션 추가
#
# Usage: ./test_cxl.sh [all|A|B|C|D|E|F|results]   default=all

set -e

ROOT=/home/naivete/DutyFree-Gem5-pakeunji
GEM5="$ROOT/build_amd_zen4_PF_CXL_latency/gem5.opt"
CFG="$ROOT/configs/deprecated/example/se.py"
BASE_COMMON="--ruby --cpu-type=O3CPU --num-cpus=4 \
  --l1d_size=256KiB --l1d_assoc=8 \
  --l1i_size=64KiB  --l1i_assoc=8 \
  --mem-type=SimpleMemory \
  --mem-size=2GiB --cxl-mem-size=1GiB \
  --dram-latency=75ns --cxl-latency=200ns"
LOGBASE="$ROOT/logs/cxl_latency"

# ── 케이스 정의 ───────────────────────────────────────────────────────────────
declare -A CASE_COMMON=(
  [A]="$BASE_COMMON --l2_size=4MiB --l2_assoc=16 --pf-size=8MiB  --pf-assoc=128"
  [B]="$BASE_COMMON --l2_size=4MiB --l2_assoc=16 --pf-size=8MiB  --pf-assoc=128"
  [C]="$BASE_COMMON --l2_size=4MiB --l2_assoc=16 --pf-size=8MiB  --pf-assoc=256"
  [D]="$BASE_COMMON --l2_size=4MiB --l2_assoc=16 --pf-size=16MiB --pf-assoc=128"
  [E]="$BASE_COMMON --l2_size=4MiB --l2_assoc=16 --pf-size=8MiB  --pf-assoc=128"
  [F]="$BASE_COMMON --l2_size=4MiB --l2_assoc=16 --pf-size=32MiB --pf-assoc=128"
)
declare -A CASE_VKB=([A]=3072 [B]=4096 [C]=3072 [D]=3072 [E]=3072 [F]=3072)
declare -A CASE_ITERS=([A]=3145728 [B]=3145728 [C]=3145728 [D]=3145728 [E]=3145728 [F]=3145728)
declare -A CASE_AGG=([A]=16 [B]=16 [C]=16 [D]=16 [E]=4 [F]=16)
declare -A CASE_LABEL=(
  [A]="v3m_a16m_pf8m_a128_L2=4M"
  [B]="v4m_a16m_pf8m_a128_L2=4M"
  [C]="v3m_a16m_pf8m_a256_L2=4M"
  [D]="v3m_a16m_pf16m_a128_L2=4M"
  [E]="v3m_a4m_pf8m_a128_L2=4M"
  [F]="v3m_a16m_pf32m_a128_L2=4M"
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
            pfbypass)    vbin="dutyfree"; dbin="dutyfree"; extra="" ;;
            pfbypass_llc) vbin="dutyfree"; dbin="dutyfree"; extra="--llc-streaming-bypass" ;;
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
base = Path("/home/naivete/DutyFree-Gem5-pakeunji/logs/cxl_latency")
CASES = {"A":"v3m_a16m_pf8m_a128_L2=4M","B":"v4m_a16m_pf8m_a128_L2=4M",
         "C":"v3m_a16m_pf8m_a256_L2=4M","D":"v3m_a16m_pf16m_a128_L2=4M",
         "E":"v3m_a4m_pf8m_a128_L2=4M","F":"v3m_a16m_pf32m_a128_L2=4M"}

HDR = T.join(["case","conf","bl_diff","bl_same","pf_diff","pf_same","llc_diff","llc_same"])

print("[ Table 1: Victim Slowdown ]")
print(HDR)
for k, label in CASES.items():
    d = base / label
    bvo=ticks(d/"baseline/victim_only"); pvo=ticks(d/"pfbypass/victim_only"); lvo=ticks(d/"pfbypass_llc/victim_only")
    print(T.join([k, label,
        sv(ticks(d/"baseline/diff_L3"), bvo),  sv(ticks(d/"baseline/same_L3"), bvo),
        sv(ticks(d/"pfbypass/diff_L3"), pvo),  sv(ticks(d/"pfbypass/same_L3"), pvo),
        sv(ticks(d/"pfbypass_llc/diff_L3"),lvo), sv(ticks(d/"pfbypass_llc/same_L3"),lvo)]))

print("\n[ Table 2: PF Replacements ]")
print(HDR)
for k, label in CASES.items():
    d = base / label
    print(T.join([k, label,
        si(pf_repl(d/"baseline/diff_L3")),  si(pf_repl(d/"baseline/same_L3")),
        si(pf_repl(d/"pfbypass/diff_L3")),  si(pf_repl(d/"pfbypass/same_L3")),
        si(pf_repl(d/"pfbypass_llc/diff_L3")), si(pf_repl(d/"pfbypass_llc/same_L3"))]))

print("\n[ Table 3: Victim L2 Miss Count ]")
print(HDR)
for k, label in CASES.items():
    d = base / label
    print(T.join([k, label,
        si(l2_miss(d/"baseline/diff_L3")),  si(l2_miss(d/"baseline/same_L3")),
        si(l2_miss(d/"pfbypass/diff_L3")),  si(l2_miss(d/"pfbypass/same_L3")),
        si(l2_miss(d/"pfbypass_llc/diff_L3")), si(l2_miss(d/"pfbypass_llc/same_L3"))]))
PYEOF
}

# ── main ──────────────────────────────────────────────────────────────────────
MODE="${1:-all}"

case "$MODE" in
    all)
        for c in A B C D E F; do run_case "$c"; done
        ;;
    A|B|C|D|E|F)
        run_case "$MODE"
        ;;
    results)
        print_results; exit 0
        ;;
    *)
        echo "Usage: $0 [all|A|B|C|D|E|F|results]"; exit 1
        ;;
esac

wait
echo "All jobs done."
echo ""
print_results
