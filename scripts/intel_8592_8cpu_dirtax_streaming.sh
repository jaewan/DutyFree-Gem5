#!/usr/bin/env bash
# Intel Xeon 8592+ (Emerald Rapids) — 8 CPU: DirTax + STREAMING (combined)
# LLC = 8 HNF × 5MiB = 40MiB ; aggressor = 2 × LLC(total) = 80MB each
# victim → DRAM 150ns, aggressor → CXL 300ns
#
# 53% WSS만, 3 run(alone/with_agg/with_streaming)을 동시에 전부 실행.
#   alone            victim + dummy×7
#   with_agg         victim + WB aggressor×7       (dirtax/aggressor   → LLC fill)
#   with_streaming   victim + STREAMING aggressor×7 (dutyfree/aggressor → LLC bypass)
#
# NOTE: streaming 정확도를 위해 GEM5는 prefetch STREAMING 패치 포함 빌드를 권장.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; export ROOT
GEM5=$ROOT/build_Intel_8592/gem5.opt
CFG=$ROOT/configs/deprecated/example/se.py
LLC_KIB=40960       # 8 × 5MiB
AGG_MB=80.0         # 2 × LLC(total)
ITERS=2621440       # 8 CPU 전용 iter

COMMON="$CFG
    --ruby --topology=Pt2Pt \
    --chi-config=$ROOT/configs/ruby/CHI_config_8592.py
    --num-l3caches=8 --num-dirs=1
    --cpu-type=O3CPU --num-cpus=8 --cpu-clock=1.9GHz
    --l1d_size=48KiB --l1d_assoc=12
    --l1i_size=32KiB --l1i_assoc=8
    --l2_size=2MiB   --l2_assoc=16
    --l3_size=5MiB   --l3_assoc=20
    --mem-type=SimpleMemory
    --mem-size=512GiB --cxl-mem-size=64GiB
    --dram-latency=150ns --cxl-latency=300ns"

V=$ROOT/testcase/dirtax/victim
A=$ROOT/testcase/dirtax/aggressor       # WB (dirtax)
SA=$ROOT/testcase/dutyfree/aggressor    # STREAMING
D=$ROOT/testcase/dirtax/dummy

OUT=$ROOT/logs/intel_8592_8cpu_dirtax_streaming
PCTS="53"

print_results() {
python3 - << 'PYEOF'
from pathlib import Path
import os; ROOT = Path(os.environ["ROOT"])
OUT  = ROOT / "logs" / "intel_8592_8cpu_dirtax_streaming"
TSV  = OUT / "results_intel_8592_8cpu_dirtax_streaming.tsv"
LABEL = "8592   8cpu"
LLC_KIB = 40960
def ticks(d):
    try:
        for line in open(d / "stats.txt"):
            if line.startswith("simTicks "): return int(line.split()[1])
    except: pass
    return None
def sl(a, w):
    return f"{w/a:.3f}" if a and w else ""
PCTS = [53]
rows = []
print(f"{'pct':<6}  {'vs_kb':>6}  {'slowdown(with tax)':>18}  {'LLCbypass':>18}")
for pct in PCTS:
    vs  = LLC_KIB * pct // 100
    tag = f"{pct}p"
    a   = ticks(OUT / f"alone_{tag}")
    w   = ticks(OUT / f"with_agg_{tag}")
    ws  = ticks(OUT / f"with_streaming_{tag}")
    sl_wb = sl(a, w)
    sl_st = sl(a, ws)
    print(f"{tag:<6}  {vs:>6}  {sl_wb or 'n/a':>18}  {sl_st or 'n/a':>18}")
    rows.append((tag, sl_wb, sl_st))
OUT.mkdir(parents=True, exist_ok=True)
with open(TSV, "w") as f:
    f.write(LABEL + "\n")
    f.write("victim WSS (%)\ttax\tLLCbypass\n")
    for tag, sl_wb, sl_st in rows:
        f.write(f"{tag}\t{sl_wb}\t{sl_st}\n")
print(f"\n→ saved to {TSV}")
PYEOF
}

run_all() {
    mkdir -p $OUT
    echo "===== Intel 8592+ DirTax+STREAMING (8 CPU, LLC=40MiB, agg=2×LLC, 53% only) ====="

    for pct in $PCTS; do
        vs=$(( LLC_KIB * pct / 100 ))
        tag="${pct}p"

        $GEM5 --outdir=$OUT/with_agg_${tag} \
            $COMMON -c "$V;$A;$A;$A;$A;$A;$A;$A" --options "$vs $ITERS;$AGG_MB;$AGG_MB;$AGG_MB;$AGG_MB;$AGG_MB;$AGG_MB;$AGG_MB" \
            > $OUT/with_agg_${tag}.log 2>&1 &
        echo "  started: with_agg_${tag} [PID $!]"

        $GEM5 --outdir=$OUT/with_streaming_${tag} \
            $COMMON -c "$V;$SA;$SA;$SA;$SA;$SA;$SA;$SA" --options "$vs $ITERS;$AGG_MB;$AGG_MB;$AGG_MB;$AGG_MB;$AGG_MB;$AGG_MB;$AGG_MB" \
            > $OUT/with_streaming_${tag}.log 2>&1 &
        echo "  started: with_streaming_${tag} [PID $!]"
    done

    echo "All launched. Use \"$0 results\" once jobs finish."
}

case "${1:-all}" in
    results) print_results ;;
    all)     run_all ;;
    *)       echo "Usage: $0 [all|results]"; exit 1 ;;
esac
