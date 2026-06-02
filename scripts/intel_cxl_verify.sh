#!/usr/bin/env bash
# intel_cxl_verify.sh — CXL/DRAM latency 분리 동작 검증 (CHI 프로토콜)
#
# A: CXL 없음 (기본 75ns)
# B: CXL 분리, victim(CPU0)→DRAM 75ns  → A와 같아야 함
# C: CXL 분리, victim(CPU0)→DRAM 200ns → A보다 느려야 함

ROOT=/home/naivete/DutyFree-Gem5-pakeunji
GEM5=$ROOT/build_Intel_8462Y/gem5.opt
CFG=$ROOT/configs/deprecated/example/se.py

# L2=512KiB, L3=512KiB → victim 1MiB가 L3 못 들어감 → DRAM 접근
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

echo "=== A: CXL 없음 (default 75ns) ==="
$GEM5 --outdir=$ROOT/logs/cxl_verify/A $CFG $COMMON \
    -c "$VICTIM;$DUMMY" --options "$OPTS" \
    > $ROOT/logs/cxl_verify/A.log 2>&1
grep "^simTicks" $ROOT/logs/cxl_verify/A/stats.txt

echo ""
echo "=== B: CXL 분리, victim→DRAM 107ns (A와 같아야 함) ==="
$GEM5 --outdir=$ROOT/logs/cxl_verify/B $CFG $COMMON \
    --mem-size=2GiB --cxl-mem-size=1GiB \
    --dram-latency=107ns --cxl-latency=214ns \
    -c "$VICTIM;$DUMMY" --options "$OPTS" \
    > $ROOT/logs/cxl_verify/B.log 2>&1
grep "^simTicks" $ROOT/logs/cxl_verify/B/stats.txt

echo ""
echo "=== C: CXL 분리, victim→DRAM 214ns (A보다 느려야 함) ==="
$GEM5 --outdir=$ROOT/logs/cxl_verify/C $CFG $COMMON \
    --mem-size=2GiB --cxl-mem-size=1GiB \
    --dram-latency=214ns --cxl-latency=214ns \
    -c "$VICTIM;$DUMMY" --options "$OPTS" \
    > $ROOT/logs/cxl_verify/C.log 2>&1
grep "^simTicks" $ROOT/logs/cxl_verify/C/stats.txt

echo ""
echo "=== 결과 요약 ==="
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
print(f"B (CXL, DRAM=75ns): {b:>15,}  ratio={b/a:.3f}x  (기대: ~1.00)")
print(f"C (CXL, DRAM=200ns): {c:>14,}  ratio={c/a:.3f}x  (기대: >1.5)")
PYEOF
