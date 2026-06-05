#!/usr/bin/env bash
# Intel Xeon 8592+ (Emerald Rapids) Directory Tax — 2 CPU
# LLC = 2 HNF × 5MiB = 10MiB
# victim: 25%/50%/75%/100% of LLC
# victim → DRAM 127ns, aggressors → CXL 218ns

ROOT=/home/naivete/DutyFree-Gem5-pakeunji
GEM5=$ROOT/build_Intel_8592/gem5.opt
CFG=$ROOT/configs/deprecated/example/se.py
LLC_KIB=10240   # 2 × 5MiB
AGG_MB=20.0     # LLC×2 = 10MiB×2

COMMON="$CFG
    --ruby --topology=Pt2Pt \
    --chi-config=$ROOT/configs/ruby/CHI_config_8592.py
    --num-l3caches=2 --num-dirs=1
    --cpu-type=O3CPU --num-cpus=2 --cpu-clock=1.9GHz
    --l1d_size=48KiB --l1d_assoc=12
    --l1i_size=32KiB --l1i_assoc=8
    --l2_size=2MiB   --l2_assoc=16
    --l3_size=5MiB   --l3_assoc=20
    --mem-type=SimpleMemory
    --mem-size=8GiB --cxl-mem-size=4GiB
    --dram-latency=150ns --cxl-latency=300ns"

V=$ROOT/testcase/dirtax/victim
A=$ROOT/testcase/dirtax/aggressor
D=$ROOT/testcase/dirtax/dummy

print_results() {
python3 - << 'PYEOF'
from pathlib import Path
base = Path("/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_8592_2cpu_dirtax")
def ticks(d):
    try:
        for line in open(d/"stats.txt"):
            if line.startswith("simTicks "): return int(line.split()[1])
    except: pass
    return None
print(f"{'pct':<6}  {'vs_kb':>8}  {'slowdown':>10}")
for pct, vs in [("25p",2560), ("40p",4096), ("45p",4608), ("50p",5120), ("53p",5427), ("55p",5632), ("60p",6144), ("75p",7680), ("100p",10240)]:
    a = ticks(base/f"alone_{pct}")
    w = ticks(base/f"with_agg_{pct}")
    sl = f"{w/a:.3f}x" if a and w else "n/a"
    print(f"{pct:<6}  {vs:>8}  {sl:>10}")
PYEOF
}

run_all() {
    mkdir -p $ROOT/logs/intel_8592_2cpu_dirtax
    echo "===== Intel 8592+ Directory Tax (2 CPU, LLC=10MiB) ====="

    for pct in 25 50 75 100; do
        vs=$((LLC_KIB * pct / 100))
        tag="${pct}p"
        iters=$((vs * 256))

        $GEM5 --outdir=$ROOT/logs/intel_8592_2cpu_dirtax/alone_${tag} \
            $COMMON \
            -c "$V;$D" \
            --options "$vs $iters;" \
            > $ROOT/logs/intel_8592_2cpu_dirtax/alone_${tag}.log 2>&1 &
        echo "  started: alone_${tag} [PID $!]"

        $GEM5 --outdir=$ROOT/logs/intel_8592_2cpu_dirtax/with_agg_${tag} \
            $COMMON \
            -c "$V;$A" \
            --options "$vs $iters;$AGG_MB" \
            > $ROOT/logs/intel_8592_2cpu_dirtax/with_agg_${tag}.log 2>&1 &
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
