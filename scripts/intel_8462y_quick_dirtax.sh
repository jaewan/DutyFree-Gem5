#!/usr/bin/env bash
# Intel 8462Y+ quick dirtax — 2 CPUs, scaled-down caches
# O3CPU + prefetch (CHI_config_8462Y.py) + DRAM/CXL latency 유지
# Scale: L3 2M→256K (x2HNF=512K total), L1/L2 원본 유지
# victim(CPU0)→DRAM, aggressor(CPU1)→CXL

ROOT=/home/naivete/DutyFree-Gem5-pakeunji
GEM5=$ROOT/build_Intel_8462Y/gem5.opt
OUTDIR=$ROOT/logs/intel_8462y_quick_dirtax
mkdir -p $OUTDIR

COMMON="$ROOT/configs/deprecated/example/se.py
    --ruby --topology=Pt2Pt
    --chi-config=$ROOT/configs/ruby/CHI_config_8462Y.py
    --num-l3caches=2 --num-dirs=1
    --cpu-type=O3CPU --num-cpus=2 --cpu-clock=2.8GHz
    --l1d_size=8KiB  --l1d_assoc=4
    --l1i_size=8KiB  --l1i_assoc=4
    --l2_size=256KiB --l2_assoc=8
    --l3_size=256KiB --l3_assoc=8
    --mem-type=SimpleMemory
    --mem-size=2GiB --cxl-mem-size=1GiB
    --dram-latency=127ns --cxl-latency=218ns"

V=$ROOT/testcase/dirtax/victim
A=$ROOT/testcase/dirtax/aggressor
D=$ROOT/testcase/dirtax/dummy

# victim: 384KB WS (< 512KB L3 → fits alone, evicted by aggressor), 500 iters
VS=384
ITERS=500
# aggressor: 2MB WS (>> 512KB L3)
AS="2.0"

run_all() {
    echo "=== Intel 8462Y+ quick dirtax ==="
    echo "    L3=512KB(2x256KB), victim=${VS}KB(<L3), iters=${ITERS}, aggressor=${AS}MB(>>L3)"

    echo "  [alone]    victim only"
    $GEM5 --outdir=$OUTDIR/alone \
        $COMMON -c "$V;$D" --options "$VS $ITERS;0" \
        > $OUTDIR/alone.log 2>&1 &
    echo "  PID=$!"

    echo "  [with_agg] victim + aggressor"
    $GEM5 --outdir=$OUTDIR/with_agg \
        $COMMON -c "$V;$A" --options "$VS $ITERS;$AS" \
        > $OUTDIR/with_agg.log 2>&1 &
    echo "  PID=$!"

    wait
    echo ""
    print_results
}

print_results() {
python3 - << 'PYEOF'
from pathlib import Path
base = Path("/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_8462y_quick_dirtax")
def ticks(d):
    try:
        for line in open(d/"stats.txt"):
            if line.startswith("simTicks "): return int(line.split()[1])
    except: pass
    return None
def hnf(d):
    h=m=0
    try:
        for line in open(d/"stats.txt"):
            if "hnf" in line and "m_demand_hits" in line and "cache" in line: h+=int(line.split()[1])
            if "hnf" in line and "m_demand_misses" in line and "cache" in line: m+=int(line.split()[1])
    except: pass
    return h,m
def cpu0_cyc(d):
    try:
        for line in open(d/"stats.txt"):
            if "cpu0" in line and "numCycles" in line: return int(line.split()[1])
    except: pass
    return None

a = ticks(base/"alone");    ha,ma = hnf(base/"alone");    ca = cpu0_cyc(base/"alone")
w = ticks(base/"with_agg"); hw,mw = hnf(base/"with_agg"); cw = cpu0_cyc(base/"with_agg")

print(f"{'':12s}  {'simTicks':>15}  {'cpu0_cycles':>12}  {'L3_hits':>8}  {'L3_miss':>8}")
print(f"{'alone':12s}  {str(a or 'n/a'):>15}  {str(ca or 'n/a'):>12}  {ha:>8}  {ma:>8}")
print(f"{'with_agg':12s}  {str(w or 'n/a'):>15}  {str(cw or 'n/a'):>12}  {hw:>8}  {mw:>8}")
if a and w:
    print(f"\nslowdown: {w/a:.3f}x")
PYEOF
}

case "${1:-all}" in
    all)     run_all ;;
    results) print_results ;;
    *)       echo "Usage: $0 [all|results]"; exit 1 ;;
esac
