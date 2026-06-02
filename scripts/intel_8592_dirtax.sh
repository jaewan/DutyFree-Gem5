#!/usr/bin/env bash
# Intel Xeon 8592+ (Emerald Rapids) Directory Tax experiment
# LLC = 8 HNF × 5MiB = 40MiB  (20-way, 4096 sets, scaled)
# victim: 22MB(55%) / 28MB(70%)
# victim → DRAM 107ns, aggressors → CXL 214ns

ROOT=/home/naivete/DutyFree-Gem5-pakeunji
GEM5=$ROOT/build_Intel_8592/gem5.opt
CFG=$ROOT/configs/deprecated/example/se.py
ITERS=3145728

COMMON="$CFG
    --ruby --topology=Pt2Pt \
    --chi-config=$ROOT/configs/ruby/CHI_config_8592.py
    --num-l3caches=8 --num-dirs=2
    --cpu-type=O3CPU --num-cpus=8 --cpu-clock=1.9GHz
    --l1d_size=48KiB --l1d_assoc=12
    --l1i_size=32KiB --l1i_assoc=8
    --l2_size=2MiB   --l2_assoc=16
    --l3_size=5MiB   --l3_assoc=20
    --mem-type=SimpleMemory
    --mem-size=2GiB --cxl-mem-size=1GiB
    --dram-latency=127ns --cxl-latency=218ns"

V=$ROOT/testcase/dirtax/victim
A=$ROOT/testcase/dirtax/aggressor
D=$ROOT/testcase/dirtax/dummy

print_results() {
python3 - << 'PYEOF'
from pathlib import Path
base = Path("/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_8592_dirtax")
def ticks(d):
    try:
        for line in open(d/"stats.txt"):
            if line.startswith("simTicks "): return int(line.split()[1])
    except: pass
    return None
print(f"{'WS':<6}  {'fit_ratio':>10}  {'slowdown':>10}")
    a = ticks(base/f"alone_22m")
    w = ticks(base/f"with_agg_22m")
    sl = f"{w/a:.3f}x" if a and w else "n/a"
    print(f"22m            55%  {sl:>10}")
    a = ticks(base/f"alone_28m")
    w = ticks(base/f"with_agg_28m")
    sl = f"{w/a:.3f}x" if a and w else "n/a"
    print(f"28m            70%  {sl:>10}")
PYEOF
}

run_all() {
    mkdir -p $ROOT/logs/intel_8592_dirtax

echo "===== Intel 8592+ Directory Tax (LLC=40MiB, 20-way) ====="

for vs in 22528 28672; do
    tag=$([ $vs -eq 22528 ] && echo "22m" || echo "28m")

    $GEM5 --outdir=$ROOT/logs/intel_8592_dirtax/alone_${tag} \
        $COMMON \
        -c "$V;$D;$D;$D;$D;$D;$D;$D" \
        --options "$vs $ITERS;;;;;;;;" \
        > $ROOT/logs/intel_8592_dirtax/alone_${tag}.log 2>&1 &
    echo "  started: alone_${tag} [PID $!]"

    $GEM5 --outdir=$ROOT/logs/intel_8592_dirtax/with_agg_${tag} \
        $COMMON \
        -c "$V;$A;$A;$A;$A;$A;$A;$A" \
        --options "$vs $ITERS;16.0;16.0;16.0;16.0;16.0;16.0;16.0" \
        > $ROOT/logs/intel_8592_dirtax/with_agg_${tag}.log 2>&1 &
    echo "  started: with_agg_${tag} [PID $!]"
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
