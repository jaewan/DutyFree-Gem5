#!/usr/bin/env bash
# Fixed-simulated-tick diagnostic for the frozen 4-CPU DirTax STREAMING setup.
#
# This is deliberately not a runtime/tax experiment. It gives every arm the
# same simulated-time prefix and exits normally, producing comparable named
# mechanism counters even when the full workload cannot finish economically.
# Usage: intel_8592_4cpu_dirtax_streaming_prefix.sh <10|25|53|75|100> <ticks>

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PCT=${1:?usage: $0 '<10|25|53|75|100>' '<positive ticks>'}
TICKS=${2:?usage: $0 '<10|25|53|75|100>' '<positive ticks>'}
case "$PCT" in 10|25|53|75|100) ;; *) echo "invalid WSS percentage: $PCT" >&2; exit 2 ;; esac
[[ "$TICKS" =~ ^[1-9][0-9]*$ ]] || { echo "ticks must be a positive integer" >&2; exit 2; }

GEM5="$ROOT/build_Intel_8592/gem5.opt"
CFG="$ROOT/configs/deprecated/example/se.py"
WSS_KIB=$((20480 * PCT / 100))
OUT=${OUT:-"$ROOT/logs/intel_8592_4cpu_dirtax_streaming_prefix/$(date -u +%Y%m%dT%H%M%SZ)_${PCT}p_${TICKS}ticks"}
mkdir -p "$OUT"

COMMON=("$CFG" --abs-max-tick="$TICKS" --ruby --topology=Pt2Pt
  "--chi-config=$ROOT/configs/ruby/CHI_config_8592.py" --num-l3caches=4 --num-dirs=1
  --cpu-type=O3CPU --num-cpus=4 --cpu-clock=1.9GHz --l1d_size=48KiB --l1d_assoc=12
  --l1i_size=32KiB --l1i_assoc=8 --l2_size=2MiB --l2_assoc=16 --l3_size=5MiB --l3_assoc=20
  --mem-type=SimpleMemory --mem-size=8GiB --cxl-mem-size=4GiB --dram-latency=100ns --cxl-latency=200ns)

run_arm() {
  local arm=$1 binaries=$2 options=$3
  local arm_out="$OUT/$arm"
  mkdir -p "$arm_out"
  printf '%q ' env RUBY_RANDOMIZATION=1 "$GEM5" "--outdir=$arm_out" "${COMMON[@]}" \
    -c "$binaries" --options "$options" > "$arm_out/command.txt"
  printf '\n' >> "$arm_out/command.txt"
  env RUBY_RANDOMIZATION=1 "$GEM5" "--outdir=$arm_out" "${COMMON[@]}" \
    -c "$binaries" --options "$options" > "$arm_out/run.log" 2>&1
  test -s "$arm_out/stats.txt"
}

V="$ROOT/testcase/dirtax/victim"; D="$ROOT/testcase/dirtax/dummy"
A="$ROOT/testcase/dirtax/aggressor"; SA="$ROOT/testcase/dutyfree/aggressor"
run_arm alone "$V;$D;$D;$D" "$WSS_KIB 10485760;;;"
run_arm with_agg "$V;$A;$A;$A" "$WSS_KIB 10485760;40.0;40.0;40.0"
run_arm with_streaming "$V;$SA;$SA;$SA" "$WSS_KIB 10485760;40.0 stream;40.0 stream;40.0 stream"
