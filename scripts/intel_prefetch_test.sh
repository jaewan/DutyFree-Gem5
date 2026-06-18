#!/usr/bin/env bash
# Prefetch ON/OFF × TimingSimpleCPU/O3CPU sweep with aggressor_finite
# 4 cases: {pf_off, pf_on} × {timing, o3}
# GEM5_STRIDE_PREFETCH=0 → prefetcher off, =1 (default) → StridePrefetcher on

set -uo pipefail
cd "$(dirname "$0")/.."

GEM5=./build_PREF/gem5.opt
CFG=configs/deprecated/example/se.py
BIN=testcase/dirtax/aggressor_finite
WS=4.0
PASSES=2

COMMON_ARGS=(
    --ruby --topology=Pt2Pt
    --num-l3caches=8 --num-dirs=1
    --num-cpus=1 --cpu-clock=2.8GHz
    --l1d_size=48KiB --l1d_assoc=12
    --l1i_size=32KiB --l1i_assoc=8
    --l2_size=2MiB  --l2_assoc=16
    --l3_size=2MiB  --l3_assoc=16
    --mem-type=SimpleMemory --dram-latency=150ns --cxl-latency=300ns
    -c "$BIN" --options "$WS $PASSES"
)

mkdir -p logs/prefetch_test

run_case() {
    local label=$1   # e.g. pf_off_timing
    local pf=$2      # 0 or 1
    local cpu=$3     # TimingSimpleCPU or O3CPU
    local outdir="logs/prefetch_test/${label}"

    echo "=== $label (GEM5_STRIDE_PREFETCH=$pf, cpu=$cpu) ==="
    mkdir -p "$outdir"
    GEM5_STRIDE_PREFETCH=$pf $GEM5 --outdir="$outdir" \
        $CFG "${COMMON_ARGS[@]}" --cpu-type="$cpu" \
        > "logs/prefetch_test/${label}.log" 2>&1
    echo "    done -> $outdir/stats.txt"
}

run_case pf_off_timing 0 TimingSimpleCPU &
run_case pf_off_o3     0 O3CPU           &
run_case pf_on_timing  1 TimingSimpleCPU &
run_case pf_on_o3      1 O3CPU           &
wait

echo ""
echo "=== Results ==="
python3 - << 'EOF'
from pathlib import Path
base = Path("logs/prefetch_test")

def ticks(label):
    p = base / label / "stats.txt"
    if not p.exists():
        return None
    for line in open(p):
        if line.startswith("simTicks "):
            return int(line.split()[1])
    return None

cases = ["pf_off_timing", "pf_off_o3", "pf_on_timing", "pf_on_o3"]
vals = {c: ticks(c) for c in cases}

for c, v in vals.items():
    print(f"  {c:<18}: {v:>16,}" if v else f"  {c:<18}: MISSING")

print()
for cpu in ("timing", "o3"):
    off = vals.get(f"pf_off_{cpu}")
    on  = vals.get(f"pf_on_{cpu}")
    if off and on:
        ratio = on / off
        delta = "faster" if on < off else "slower"
        print(f"  {cpu}: pf_on/pf_off = {ratio:.3f}x  ({delta})")
EOF
