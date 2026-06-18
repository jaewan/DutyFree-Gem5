#!/usr/bin/env bash
# Intel Xeon 8592+ (Emerald Rapids) — 4 CPU: DirTax + STREAMING (combined, agg2x)
# LLC = 4 HNF × 5MiB = 20MiB ; aggressor = 2 × LLC(total) = 40MB each
# victim → DRAM 150ns, aggressor → CXL 300ns
#
# WSS sweep × three run types, all jobs launched at once:
#   alone            victim + dummy×3
#   with_agg         victim + WB aggressor×3       (dirtax/aggressor   → LLC fill)
#   with_streaming   victim + STREAMING aggressor×3 (dutyfree/aggressor → LLC bypass)
#
# Seed: gem5 default RNG seed (5489) — RUBY_RANDOMIZATION=1 for fair SNF arbitration.
# NOTE: assumes store-fix aggressor build (register accumulation, 1 store per scan).
#       GEM5 build with the prefetch STREAMING patch is recommended.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; export ROOT
GEM5=$ROOT/build_Intel_8592/gem5.opt
CFG=$ROOT/configs/deprecated/example/se.py
LLC_KIB=20480       # 4 × 5MiB
AGG_MB=40.0         # 2 × LLC(total)
ITERS=10485760      # max_vs(20480KiB) × 256 × 2 passes

COMMON="$CFG
    --ruby --topology=Pt2Pt \
    --chi-config=$ROOT/configs/ruby/CHI_config_8592.py
    --num-l3caches=4 --num-dirs=1
    --cpu-type=O3CPU --num-cpus=4 --cpu-clock=1.9GHz
    --l1d_size=48KiB --l1d_assoc=12
    --l1i_size=32KiB --l1i_assoc=8
    --l2_size=2MiB   --l2_assoc=16
    --l3_size=5MiB   --l3_assoc=20
    --mem-type=SimpleMemory
    --mem-size=8GiB --cxl-mem-size=4GiB
    --dram-latency=150ns --cxl-latency=300ns"

V=$ROOT/testcase/dirtax/victim
A=$ROOT/testcase/dirtax/aggressor       # WB (dirtax)
SA=$ROOT/testcase/dutyfree/aggressor    # STREAMING
D=$ROOT/testcase/dirtax/dummy

OUT=$ROOT/logs/intel_8592_4cpu_dirtax_streaming
PCTS="10 25 53 75 100"

print_results() {
python3 - << 'PYEOF'
from pathlib import Path
import os; ROOT = Path(os.environ["ROOT"])
OUT  = ROOT / "logs" / "intel_8592_4cpu_dirtax_streaming"
TSV  = OUT / "results_intel_8592_4cpu_dirtax_streaming.tsv"
LABEL = "8592  4cpu dirtax_streaming (agg2x)"
LLC_KIB = 20480
NAGG = 3
def stat(d, key):
    try:
        for line in open(d / "stats.txt"):
            if line.startswith(key + " "): return float(line.split()[1])
    except: pass
    return None
def sl(a, w):
    return f"{w/a:.3f}" if a and w else ""
def bw(d):
    sec = stat(d, "simSeconds")
    mem = stat(d, "system.mem_ctrls1.bwTotal::total")
    cpus = [stat(d, f"system.cpu{c}.numRecvRespBytes") for c in range(1, NAGG+1)]
    if not sec: return None, [None]*NAGG
    cpu_bw = [(rb/sec)/1e9 if rb else None for rb in cpus]
    mem_bw = mem/1e9 if mem is not None else None
    return mem_bw, cpu_bw
def trio(t):
    return "(" + ", ".join(f"{x:.2f}" for x in t) + ")" if all(x is not None for x in t) else "n/a"
PCTS = [10, 25, 53, 75, 100]
rows = []
bw_rows = []
print(LABEL)
print("victim WSS (%)\ttax\tLLCbypass")
for pct in PCTS:
    vs  = LLC_KIB * pct // 100
    tag = f"{pct}p"
    a   = stat(OUT / f"alone_{tag}", "simTicks")
    w   = stat(OUT / f"with_agg_{tag}", "simTicks")
    ws  = stat(OUT / f"with_streaming_{tag}", "simTicks")
    sl_wb = sl(a, w)
    sl_st = sl(a, ws)
    print(f"{tag}\t{sl_wb or 'n/a'}\t{sl_st or 'n/a'}")
    rows.append((tag, sl_wb, sl_st))
    wb_mem, wb_cpu = bw(OUT / f"with_agg_{tag}")
    st_mem, st_cpu = bw(OUT / f"with_streaming_{tag}")
    wbm = f"{wb_mem:.3f}" if wb_mem is not None else "n/a"
    stm = f"{st_mem:.3f}" if st_mem is not None else "n/a"
    bw_rows.append((tag, wbm, stm, trio(wb_cpu), trio(st_cpu)))
print(f"\naggressor BW (GB/s): mem=CXL ctrl total, cpu=(agg1..agg{NAGG}) per-core")
print("victim WSS (%)\tWB_mem\tST_mem\tWB_cpu\tST_cpu")
for r in bw_rows:
    print("\t".join(r))
OUT.mkdir(parents=True, exist_ok=True)
with open(TSV, "w") as f:
    f.write(LABEL + "\n")
    f.write("victim WSS (%)\ttax\tLLCbypass\n")
    for tag, sl_wb, sl_st in rows:
        f.write(f"{tag}\t{sl_wb}\t{sl_st}\n")
    f.write(f"\naggressor BW (GB/s): mem=CXL ctrl total, cpu=(agg1..agg{NAGG}) per-core\n")
    f.write("victim WSS (%)\tWB_mem\tST_mem\tWB_cpu\tST_cpu\n")
    for r in bw_rows:
        f.write("\t".join(r) + "\n")
print(f"\n→ saved to {TSV}")
PYEOF
}

run_all() {
    mkdir -p $OUT
    echo "===== Intel 8592+ DirTax+STREAMING (4 CPU, LLC=20MiB, agg=2×LLC, all jobs at once) ====="

    for pct in $PCTS; do
        vs=$(( LLC_KIB * pct / 100 ))
        tag="${pct}p"

        env RUBY_RANDOMIZATION=1 $GEM5 --outdir=$OUT/alone_${tag} \
            $COMMON -c "$V;$D;$D;$D" --options "$vs $ITERS;;;" \
            > $OUT/alone_${tag}.log 2>&1 &
        echo "  started: alone_${tag} [PID $!]"

        env RUBY_RANDOMIZATION=1 $GEM5 --outdir=$OUT/with_agg_${tag} \
            $COMMON -c "$V;$A;$A;$A" --options "$vs $ITERS;$AGG_MB;$AGG_MB;$AGG_MB" \
            > $OUT/with_agg_${tag}.log 2>&1 &
        echo "  started: with_agg_${tag} [PID $!]"

        env RUBY_RANDOMIZATION=1 $GEM5 --outdir=$OUT/with_streaming_${tag} \
            $COMMON -c "$V;$SA;$SA;$SA" --options "$vs $ITERS;$AGG_MB;$AGG_MB;$AGG_MB" \
            > $OUT/with_streaming_${tag}.log 2>&1 &
        echo "  started: with_streaming_${tag} [PID $!]"
    done

    echo "jobs launched (WSS sweep × 3 run). check results: $0 results"
}

case "${1:-all}" in
    results) print_results ;;
    all)     run_all ;;
    *)       echo "Usage: $0 [all|results]"; exit 1 ;;
esac
