#!/usr/bin/env bash
# intel_cxl_verify.sh — verify CXL/DRAM latency separation (CHI protocol)
#
# A: no CXL (default 75ns)
# B: CXL separated, victim(CPU0)→DRAM 75ns  → should equal A
# C: CXL separated, victim(CPU0)→DRAM 200ns → should be slower than A

ROOT=/home/naivete/DutyFree-Gem5-pakeunji
GEM5=$ROOT/build_Intel_8462Y/gem5.opt
CFG=$ROOT/configs/deprecated/example/se.py

# L2=512KiB, L3=512KiB → victim 1MiB does not fit in L3 → DRAM access
COMMON="--ruby --topology=Pt2Pt
    --num-l3caches=1 --num-dirs=1
    --cpu-type=TimingSimpleCPU --num-cpus=2
    --l1d_size=48KiB --l1d_assoc=12
    --l1i_size=32KiB --l1i_assoc=8
    --l2_size=512KiB --l2_assoc=8
    --l3_size=512KiB --l3_assoc=8
    --mem-type=SimpleMemory"

VICTIM="$ROOT/testcase/dirtax/victim"
DUMMY="$ROOT/testcase/dirtax/dummy"
OPTS="1024 5000;"   # size_kb=1024, iters=5000, dummy=empty

mkdir -p $ROOT/logs/cxl_verify

echo "=== A: no CXL (default 75ns) ==="
$GEM5 --outdir=$ROOT/logs/cxl_verify/A $CFG $COMMON \
    -c "$VICTIM;$DUMMY" --options "$OPTS" \
    > $ROOT/logs/cxl_verify/A.log 2>&1
grep "^simTicks" $ROOT/logs/cxl_verify/A/stats.txt

echo ""
echo "=== B: CXL separated, victim→DRAM 107ns (should equal A) ==="
$GEM5 --outdir=$ROOT/logs/cxl_verify/B $CFG $COMMON \
    --mem-size=2GiB --cxl-mem-size=1GiB \
    --dram-latency=150ns --cxl-latency=300ns \
    -c "$VICTIM;$DUMMY" --options "$OPTS" \
    > $ROOT/logs/cxl_verify/B.log 2>&1
grep "^simTicks" $ROOT/logs/cxl_verify/B/stats.txt

echo ""
echo "=== C: CXL separated, victim→DRAM 214ns (should be slower than A) ==="
$GEM5 --outdir=$ROOT/logs/cxl_verify/C $CFG $COMMON \
    --mem-size=2GiB --cxl-mem-size=1GiB \
    --dram-latency=150ns --cxl-latency=300ns \
    -c "$VICTIM;$DUMMY" --options "$OPTS" \
    > $ROOT/logs/cxl_verify/C.log 2>&1
grep "^simTicks" $ROOT/logs/cxl_verify/C/stats.txt

echo ""
echo "=== results summary ==="
python3 - << 'PYEOF'
from pathlib import Path
base = Path("/home/naivete/DutyFree-Gem5-pakeunji/logs/cxl_verify")
def ticks(d):
    try:
        for line in open(d/"stats.txt"):
            if line.startswith("simTicks "):
                return int(line.split()[1])
    except: pass
    return None

a = ticks(base/"A"); b = ticks(base/"B"); c = ticks(base/"C")
print(f"A (no CXL,  75ns): {a:>15,}")
print(f"B (CXL, DRAM=75ns): {b:>15,}  ratio={b/a:.3f}x  (expected: ~1.00)")
print(f"C (CXL, DRAM=200ns): {c:>14,}  ratio={c/a:.3f}x  (expected: >1.5)")
PYEOF
