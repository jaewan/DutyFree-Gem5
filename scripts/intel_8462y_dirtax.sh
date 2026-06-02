#!/usr/bin/env bash
# Intel Xeon 8462Y+ (Sapphire Rapids) Directory Tax experiment
# LLC = 8 HNF × 2MiB = 16MiB  (1/4 scale of 60MB)
# victim: 8MB(50%) / 12MB(75%)
# victim → DRAM 107ns, aggressors → CXL 214ns

ROOT=/home/naivete/DutyFree-Gem5-pakeunji
GEM5=$ROOT/build_Intel_8462Y/gem5.opt
CFG=$ROOT/configs/deprecated/example/se.py
ITERS=3145728

COMMON="$CFG
    --ruby --topology=Pt2Pt \
    --chi-config=$ROOT/configs/ruby/CHI_config_8462Y.py
    --num-l3caches=8 --num-dirs=2
    --cpu-type=O3CPU --num-cpus=8 --cpu-clock=2.8GHz
    --l1d_size=48KiB --l1d_assoc=12
    --l1i_size=32KiB --l1i_assoc=8
    --l2_size=2MiB   --l2_assoc=16
    --l3_size=2MiB   --l3_assoc=16
    --mem-type=SimpleMemory
    --mem-size=2GiB --cxl-mem-size=1GiB
    --dram-latency=124ns --cxl-latency=467ns"

V=$ROOT/testcase/dirtax/victim
A=$ROOT/testcase/dirtax/aggressor
D=$ROOT/testcase/dirtax/dummy

mkdir -p $ROOT/logs/intel_8462y_dirtax

echo "===== Intel 8462Y+ Directory Tax (LLC=16MiB) ====="

for vs in 8192 12288; do
    tag=$([ $vs -eq 8192 ] && echo "8m" || echo "12m")

    $GEM5 --outdir=$ROOT/logs/intel_8462y_dirtax/alone_${tag} \
        $COMMON \
        -c "$V;$D;$D;$D;$D;$D;$D;$D" \
        --options "$vs $ITERS;;;;;;;;" \
        > $ROOT/logs/intel_8462y_dirtax/alone_${tag}.log 2>&1 &
    echo "  started: alone_${tag} [PID $!]"

    $GEM5 --outdir=$ROOT/logs/intel_8462y_dirtax/with_agg_${tag} \
        $COMMON \
        -c "$V;$A;$A;$A;$A;$A;$A;$A" \
        --options "$vs $ITERS;8.0;8.0;8.0;8.0;8.0;8.0;8.0" \
        > $ROOT/logs/intel_8462y_dirtax/with_agg_${tag}.log 2>&1 &
    echo "  started: with_agg_${tag} [PID $!]"
done

wait
echo "Done."

python3 - << 'PYEOF'
from pathlib import Path
base = Path("/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_8462y_dirtax")
def ticks(d):
    try:
        for line in open(d/"stats.txt"):
            if line.startswith("simTicks "): return int(line.split()[1])
    except: pass
    return None
print(f"{'WS':<8}  {'alone':>15}  {'with_agg':>15}  slowdown")
for tag, fit in [("8m","50%"), ("12m","75%")]:
    a = ticks(base/f"alone_{tag}")
    w = ticks(base/f"with_agg_{tag}")
    sl = f"{w/a:.3f}x" if a and w else "n/a"
    print(f"{tag:<8}  {str(a or ''):>15}  {str(w or ''):>15}  {sl}  (fit_ratio≈{fit})")
PYEOF
