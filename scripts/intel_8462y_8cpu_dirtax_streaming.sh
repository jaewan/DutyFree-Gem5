#!/usr/bin/env bash
# Intel Xeon 8462Y+ (Sapphire Rapids) — 8 CPU: DirTax + STREAMING (combined)
# LLC = 8 HNF × 2MiB = 16MiB ; aggressor = 2 × LLC(total) = 32MB each
# victim → DRAM 150ns, aggressor → CXL 300ns
#
# 53% WSS만, 3 run(alone/with_agg/with_streaming)을 동시에 전부 실행.
#   alone            victim + dummy×7
#   with_agg         victim + WB aggressor×7       (dirtax/aggressor   → LLC fill)
#   with_streaming   victim + STREAMING aggressor×7 (dutyfree/aggressor → LLC bypass)
#
# NOTE: streaming 정확도를 위해 GEM5는 prefetch STREAMING 패치 포함 빌드를 권장.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; export ROOT
GEM5=$ROOT/build_Intel_8462Y/gem5.opt
CFG=$ROOT/configs/deprecated/example/se.py
LLC_KIB=16384       # 8 × 2MiB
AGG_MB=32.0         # 2 × LLC(total)
ITERS=1048576       # 8 CPU 전용 iter
MAXJOBS=3           # 53% 한 케이스의 3 run을 동시에 전부 실행

COMMON="$CFG
    --ruby --topology=Pt2Pt \
    --chi-config=$ROOT/configs/ruby/CHI_config_8462Y.py
    --num-l3caches=8 --num-dirs=1
    --cpu-type=O3CPU --num-cpus=8 --cpu-clock=2.8GHz
    --l1d_size=48KiB --l1d_assoc=12
    --l1i_size=32KiB --l1i_assoc=8
    --l2_size=2MiB   --l2_assoc=16
    --l3_size=2MiB   --l3_assoc=16
    --mem-type=SimpleMemory
    --mem-size=16GiB --cxl-mem-size=2GiB
    --dram-latency=150ns --cxl-latency=300ns"

V=$ROOT/testcase/dirtax/victim
A=$ROOT/testcase/dirtax/aggressor       # WB (dirtax)
SA=$ROOT/testcase/dutyfree/aggressor    # STREAMING
D=$ROOT/testcase/dirtax/dummy

OUT=$ROOT/logs/intel_8462y_8cpu_dirtax_streaming
PCTS="53"

# 실행 중 백그라운드 작업이 MAXJOBS 이상이면 하나 끝날 때까지 대기
throttle() { while (( $(jobs -rp | wc -l) >= MAXJOBS )); do wait -n; done; }

print_results() {
python3 - << 'PYEOF'
from pathlib import Path
import os; ROOT = Path(os.environ["ROOT"])
OUT  = ROOT / "logs" / "intel_8462y_8cpu_dirtax_streaming"
TSV  = OUT / "results_intel_8462y_8cpu_dirtax_streaming.tsv"
LABEL = "8462Y  8cpu"
LLC_KIB = 16384
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
    echo "===== Intel 8462Y+ DirTax+STREAMING (8 CPU, LLC=16MiB, agg=2×LLC, 53% only, max ${MAXJOBS} jobs) ====="

    for pct in $PCTS; do
        vs=$(( LLC_KIB * pct / 100 ))
        tag="${pct}p"

        throttle
        $GEM5 --outdir=$OUT/alone_${tag} \
            $COMMON -c "$V;$D;$D;$D;$D;$D;$D;$D" --options "$vs $ITERS;;;;;;;" \
            > $OUT/alone_${tag}.log 2>&1 &
        echo "  started: alone_${tag} [PID $!]"

        throttle
        $GEM5 --outdir=$OUT/with_agg_${tag} \
            $COMMON -c "$V;$A;$A;$A;$A;$A;$A;$A" --options "$vs $ITERS;$AGG_MB;$AGG_MB;$AGG_MB;$AGG_MB;$AGG_MB;$AGG_MB;$AGG_MB" \
            > $OUT/with_agg_${tag}.log 2>&1 &
        echo "  started: with_agg_${tag} [PID $!]"

        throttle
        $GEM5 --outdir=$OUT/with_streaming_${tag} \
            $COMMON -c "$V;$SA;$SA;$SA;$SA;$SA;$SA;$SA" --options "$vs $ITERS;$AGG_MB;$AGG_MB;$AGG_MB;$AGG_MB;$AGG_MB;$AGG_MB;$AGG_MB" \
            > $OUT/with_streaming_${tag}.log 2>&1 &
        echo "  started: with_streaming_${tag} [PID $!]"
    done

    wait
    echo "Done."
    print_results
}

case "${1:-all}" in
    results) print_results ;;
    all)     run_all ;;
    *)       echo "Usage: $0 [all|results]"; exit 1 ;;
esac
