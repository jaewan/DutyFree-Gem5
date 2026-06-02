#!/usr/bin/env bash
# Intel Xeon 8462Y+ (Sapphire Rapids) Directory Tax — original scale
# 32 cores, LLC = 32 HNF × 2MiB = 64MiB (~60MB real)
# victim: ~34MB (53% of 64MiB)
# Layout: CPU0=victim, CPU1~8=aggressor×8, CPU9~31=dummy×23

ROOT=/home/naivete/DutyFree-Gem5-pakeunji
GEM5=$ROOT/build_Intel_8462Y/gem5.opt
CFG=$ROOT/configs/deprecated/example/se.py
ITERS=3145728

V=$ROOT/testcase/dirtax/victim
A=$ROOT/testcase/dirtax/aggressor
D=$ROOT/testcase/dirtax/dummy

# 32 CPUs: victim + 8 agg + 23 dummy
PROGS="$V"
OPTS_ALONE="34816 $ITERS"
OPTS_WITH="34816 $ITERS"
for i in $(seq 1 8);  do PROGS="$PROGS;$A"; OPTS_WITH="$OPTS_WITH;10.0"; done
for i in $(seq 9 31); do PROGS="$PROGS;$D"; OPTS_WITH="$OPTS_WITH;";    done

PROGS_ALONE="$V"
for i in $(seq 1 31); do PROGS_ALONE="$PROGS_ALONE;$D"; OPTS_ALONE="$OPTS_ALONE;"; done

COMMON="$CFG
    --ruby --topology=Pt2Pt \
    --chi-config=$ROOT/configs/ruby/CHI_config_8462Y.py
    --num-l3caches=32 --num-dirs=2
    --cpu-type=O3CPU --num-cpus=32 --cpu-clock=2.8GHz
    --l1d_size=48KiB --l1d_assoc=12
    --l1i_size=32KiB --l1i_assoc=8
    --l2_size=2MiB   --l2_assoc=16
    --l3_size=2MiB   --l3_assoc=16
    --mem-type=SimpleMemory
    --mem-size=2GiB --cxl-mem-size=1GiB
    --dram-latency=124ns --cxl-latency=467ns"

print_results() {
python3 - << 'PYEOF'
from pathlib import Path
base = Path("/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_noScale_8462y_dirtax")
def ticks(d):
    try:
        for line in open(d/"stats.txt"):
            if line.startswith("simTicks "): return int(line.split()[1])
    except: pass
    return None
a = ticks(base/"alone"); w = ticks(base/"with_agg")
sl = f"{w/a:.3f}x" if a and w else "n/a"
print(f"slowdown: {sl}")
PYEOF
}

run_all() {
    mkdir -p $ROOT/logs/intel_noScale_8462y_dirtax

echo "===== Intel 8462Y+ original scale (LLC=64MiB, 32 cores) ====="

$GEM5 --outdir=$ROOT/logs/intel_noScale_8462y_dirtax/alone \
    $COMMON -c "$PROGS_ALONE" --options "$OPTS_ALONE" \
    > $ROOT/logs/intel_noScale_8462y_dirtax/alone.log 2>&1 &
echo "  started: alone [PID $!]"

$GEM5 --outdir=$ROOT/logs/intel_noScale_8462y_dirtax/with_agg \
    $COMMON -c "$PROGS" --options "$OPTS_WITH" \
    > $ROOT/logs/intel_noScale_8462y_dirtax/with_agg.log 2>&1 &
echo "  started: with_agg [PID $!]"

    wait
    echo "Done."
    print_results
}

case "${1:-all}" in
    results) print_results ;;
    all)     run_all ;;
    *)       echo "Usage: $0 [all|results]"; exit 1 ;;
esac
