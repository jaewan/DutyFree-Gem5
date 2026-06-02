#!/usr/bin/env bash
# Intel Xeon 8592+ (Emerald Rapids) Directory Tax — original scale
# 64 cores, LLC = 64 HNF × 5MiB = 320MiB (20-way, 4096 sets — exact match)
# victim: ~170MB (53% of 320MiB)
# Layout: CPU0=victim, CPU1~8=aggressor×8, CPU9~63=dummy×55

ROOT=/home/naivete/DutyFree-Gem5-pakeunji
GEM5=$ROOT/build_Intel_8592/gem5.opt
CFG=$ROOT/configs/deprecated/example/se.py
ITERS=3145728

V=$ROOT/testcase/dirtax/victim
A=$ROOT/testcase/dirtax/aggressor
D=$ROOT/testcase/dirtax/dummy

# 64 CPUs: victim + 8 agg + 55 dummy
PROGS="$V"
OPTS_ALONE="174080 $ITERS"
OPTS_WITH="174080 $ITERS"
for i in $(seq 1 8);  do PROGS="$PROGS;$A"; OPTS_WITH="$OPTS_WITH;50.0"; done
for i in $(seq 9 63); do PROGS="$PROGS;$D"; OPTS_WITH="$OPTS_WITH;";     done

PROGS_ALONE="$V"
for i in $(seq 1 63); do PROGS_ALONE="$PROGS_ALONE;$D"; OPTS_ALONE="$OPTS_ALONE;"; done

COMMON="$CFG
    --ruby --topology=Pt2Pt \
    --chi-config=$ROOT/configs/ruby/CHI_config_8592.py
    --num-l3caches=64 --num-dirs=2
    --cpu-type=O3CPU --num-cpus=64 --cpu-clock=1.9GHz
    --l1d_size=48KiB --l1d_assoc=12
    --l1i_size=32KiB --l1i_assoc=8
    --l2_size=2MiB   --l2_assoc=16
    --l3_size=5MiB   --l3_assoc=20
    --mem-type=SimpleMemory
    --mem-size=2GiB --cxl-mem-size=1GiB
    --dram-latency=127ns --cxl-latency=218ns"

print_results() {
python3 - << 'PYEOF'
from pathlib import Path
base = Path("/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_noScale_8592_dirtax")
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
    mkdir -p $ROOT/logs/intel_noScale_8592_dirtax

echo "===== Intel 8592+ original scale (LLC=320MiB, 64 cores, 20-way) ====="

$GEM5 --outdir=$ROOT/logs/intel_noScale_8592_dirtax/alone \
    $COMMON -c "$PROGS_ALONE" --options "$OPTS_ALONE" \
    > $ROOT/logs/intel_noScale_8592_dirtax/alone.log 2>&1 &
echo "  started: alone [PID $!]"

$GEM5 --outdir=$ROOT/logs/intel_noScale_8592_dirtax/with_agg \
    $COMMON -c "$PROGS" --options "$OPTS_WITH" \
    > $ROOT/logs/intel_noScale_8592_dirtax/with_agg.log 2>&1 &
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
