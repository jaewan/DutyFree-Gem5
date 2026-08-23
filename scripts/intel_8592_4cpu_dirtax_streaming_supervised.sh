#!/usr/bin/env bash
# Supervised single-WSS executor for the frozen Intel-8592 4-CPU DirTax sweep.
#
# It deliberately preserves the command line/geometry from
# intel_8592_4cpu_dirtax_streaming.sh, but runs the matched trio serially.
# This avoids the uncontrolled 15-way O3+Ruby fan-out of the historical
# sweep and enforces the session's 90-minute zero-stats tripwire per arm.
#
# Usage: intel_8592_4cpu_dirtax_streaming_supervised.sh <10|25|53|75|100>

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEM5="$ROOT/build_Intel_8592/gem5.opt"
CFG="$ROOT/configs/deprecated/example/se.py"
PCT=${1:?usage: $0 '<10|25|53|75|100>'}
case "$PCT" in 10|25|53|75|100) ;; *) echo "invalid WSS percentage: $PCT" >&2; exit 2 ;; esac

LLC_KIB=20480
AGG_MB=40.0
ITERS=10485760
WSS_KIB=$((LLC_KIB * PCT / 100))
TIMEOUT_S=${TIMEOUT_S:-5400}
RUN_ID=${RUN_ID:-"$(date -u +%Y%m%dT%H%M%SZ)_${PCT}p"}
OUT=${OUT:-"$ROOT/logs/intel_8592_4cpu_dirtax_streaming_supervised/$RUN_ID"}

COMMON=(
  "$CFG" --ruby --topology=Pt2Pt
  "--chi-config=$ROOT/configs/ruby/CHI_config_8592.py"
  --num-l3caches=4 --num-dirs=1
  --cpu-type=O3CPU --num-cpus=4 --cpu-clock=1.9GHz
  --l1d_size=48KiB --l1d_assoc=12 --l1i_size=32KiB --l1i_assoc=8
  --l2_size=2MiB --l2_assoc=16 --l3_size=5MiB --l3_assoc=20
  --mem-type=SimpleMemory --mem-size=8GiB --cxl-mem-size=4GiB
  --dram-latency=150ns --cxl-latency=300ns
)

mkdir -p "$OUT"
printf 'run_id=%s\nwss_pct=%s\nwss_kib=%s\ntimeout_s=%s\n' \
  "$RUN_ID" "$PCT" "$WSS_KIB" "$TIMEOUT_S" > "$OUT/manifest.txt"
printf 'gem5_build_info:\n' >> "$OUT/manifest.txt"
"$GEM5" --build-info >> "$OUT/manifest.txt"

run_arm() {
  local arm=$1 binaries=$2 options=$3
  local arm_out="$OUT/$arm"
  mkdir -p "$arm_out"
  printf 'arm=%s\nstarted_utc=%s\n' "$arm" "$(date -u --iso-8601=seconds)" > "$arm_out/provenance.txt"
  printf '%q ' env RUBY_RANDOMIZATION=1 "$GEM5" "--outdir=$arm_out" "${COMMON[@]}" \
    -c "$binaries" --options "$options" > "$arm_out/command.txt"
  printf '\n' >> "$arm_out/command.txt"

  env RUBY_RANDOMIZATION=1 "$GEM5" "--outdir=$arm_out" "${COMMON[@]}" \
    -c "$binaries" --options "$options" > "$arm_out/run.log" 2>&1 &
  local pid=$! watchdog status sim_ticks
  printf 'pid=%s\n' "$pid" >> "$arm_out/provenance.txt"
  (
    sleep "$TIMEOUT_S"
    if kill -0 "$pid" 2>/dev/null && [[ ! -s "$arm_out/stats.txt" ]]; then
      printf 'tripwire_utc=%s\ntripwire_reason=zero-byte_stats_after_%ss\n' \
        "$(date -u --iso-8601=seconds)" "$TIMEOUT_S" >> "$arm_out/provenance.txt"
      kill -INT "$pid"
    fi
  ) & watchdog=$!
  if wait "$pid"; then status=0; else status=$?; fi
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  sim_ticks=$(awk '$1 == "simTicks" { print $2; exit }' "$arm_out/stats.txt" 2>/dev/null || true)
  printf 'finished_utc=%s\nexit_status=%s\nsimTicks=%s\n' \
    "$(date -u --iso-8601=seconds)" "$status" "${sim_ticks:-unavailable}" >> "$arm_out/provenance.txt"
  [[ $status -eq 0 && -s "$arm_out/stats.txt" ]]
}

V="$ROOT/testcase/dirtax/victim"
D="$ROOT/testcase/dirtax/dummy"
A="$ROOT/testcase/dirtax/aggressor"
SA="$ROOT/testcase/dutyfree/aggressor"

run_arm alone "$V;$D;$D;$D" "$WSS_KIB $ITERS;;;"
run_arm with_agg "$V;$A;$A;$A" "$WSS_KIB $ITERS;$AGG_MB;$AGG_MB;$AGG_MB"
run_arm with_streaming "$V;$SA;$SA;$SA" "$WSS_KIB $ITERS;$AGG_MB;$AGG_MB;$AGG_MB"
