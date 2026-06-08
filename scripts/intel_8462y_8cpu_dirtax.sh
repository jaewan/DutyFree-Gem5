#!/usr/bin/env bash
# Intel Xeon 8462Y+ (Sapphire Rapids) Directory Tax — 8 CPU
# LLC = 8 HNF × 2MiB = 16MiB
# victim: 25%/50%/75%/100% of LLC
# victim → DRAM 150ns, aggressors → CXL 300ns

ROOT=/home/naivete/DutyFree-Gem5-pakeunji
GEM5=$ROOT/build_Intel_8462Y/gem5.opt
CFG=$ROOT/configs/deprecated/example/se.py
LLC_KIB=16384   # 8 × 2MiB
AGG_MB=64.0     # LLC×4 = 16MiB×4

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
    --mem-size=4GiB --cxl-mem-size=2GiB
    --dram-latency=150ns --cxl-latency=300ns"

V=$ROOT/testcase/dirtax/victim
A=$ROOT/testcase/dirtax/aggressor
D=$ROOT/testcase/dirtax/dummy

print_results() {
python3 - << 'PYEOF'
from pathlib import Path
base = Path("/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_8462y_8cpu_dirtax")
def ticks(d):
    try:
        for line in open(d/"stats.txt"):
            if line.startswith("simTicks "): return int(line.split()[1])
    except: pass
    return None
print(f"{'pct':<6}  {'vs_kb':>8}  {'slowdown':>10}")
for pct, vs in [("25p",4096), ("40p",6553), ("45p",7372), ("50p",8192), ("53p",8683), ("55p",9011), ("60p",9830), ("75p",12288), ("100p",16384)]:
    a = ticks(base/f"alone_{pct}")
    w = ticks(base/f"with_agg_{pct}")
    sl = f"{w/a:.3f}x" if a and w else "n/a"
    print(f"{pct:<6}  {vs:>8}  {sl:>10}")
PYEOF
}

run_all() {
    mkdir -p $ROOT/logs/intel_8462y_8cpu_dirtax
    echo "===== Intel 8462Y+ Directory Tax (8 CPU, LLC=16MiB) ====="

    batch=0
    for pct in 50 53 60 25 40 45 55 75 100; do
        vs=$((LLC_KIB * pct / 100))
        tag="${pct}p"
        iters=8388608   # LLC_KIB(16384) × 512

        $GEM5 --outdir=$ROOT/logs/intel_8462y_8cpu_dirtax/alone_${tag} \
            $COMMON \
            -c "$V;$D;$D;$D;$D;$D;$D;$D" \
            --options "$vs $iters;;;;;;;" \
            > $ROOT/logs/intel_8462y_8cpu_dirtax/alone_${tag}.log 2>&1 &
        echo "  started: alone_${tag} [PID $!]"

        $GEM5 --outdir=$ROOT/logs/intel_8462y_8cpu_dirtax/with_agg_${tag} \
            $COMMON \
            -c "$V;$A;$A;$A;$A;$A;$A;$A" \
            --options "$vs $iters;$AGG_MB;$AGG_MB;$AGG_MB;$AGG_MB;$AGG_MB;$AGG_MB;$AGG_MB" \
            > $ROOT/logs/intel_8462y_8cpu_dirtax/with_agg_${tag}.log 2>&1 &
        echo "  started: with_agg_${tag} [PID $!]"

        batch=$((batch + 2))
        if [ $batch -ge 4 ]; then
            wait
            batch=0
        fi
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
