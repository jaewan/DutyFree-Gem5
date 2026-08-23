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
# TIMEOUT_S was 5400 (the session prompt's 90-minute zero-stat tripwire), and
# 5400 is SMALLER THAN THE KNOWN COMPLETION TIME OF THIS SWEEP'S FASTEST 53%
# ARM. Measured, not estimated: logs/intel_8592_4cpu_dirtax_streaming/alone_53p
# completed naturally at hostSeconds 6072 (1.69 h). The two contended 53% arms
# are strictly slower -- at 17,400 s they had reached only 172.5e9 and 191.8e9
# ticks against alone's 431.8e9, i.e. 40% and 44% -- so at their measured tick
# rates they need >=12.1 h and >=10.9 h respectively, and those are LOWER bounds
# because contention raises the victim's tick cost above alone's total.
#
# With the old default every arm of the 2026-08-23 supervised 53% trio was
# killed at exactly 5400 s and reported SUCCESS. See
# experiments/asplos/W8.5_T2_SUPERVISED_TRIO_WAS_TRUNCATED_2026-08-24.md.
# Default raised to 14 h, which clears the >=12.1 h lower bound with margin.
TIMEOUT_S=${TIMEOUT_S:-50400}
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
      # Marker file, because the watchdog is a subshell and cannot set a
      # variable in run_arm. Without it the tripwire is invisible to the
      # success test below -- which is exactly how the 2026-08-23 trio came
      # back green with three truncated arms.
      : > "$arm_out/.tripwire_fired"
      kill -INT "$pid"
    fi
  ) & watchdog=$!
  if wait "$pid"; then status=0; else status=$?; fi
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  sim_ticks=$(awk '$1 == "simTicks" { print $2; exit }' "$arm_out/stats.txt" 2>/dev/null || true)

  # A TRIPPED ARM IS A FAILED ARM. gem5 handles SIGINT by dumping a complete,
  # normal-looking stats.txt and exiting 0, so the old test
  #     [[ $status -eq 0 && -s "$arm_out/stats.txt" ]]
  # returned TRUE for every killed arm. On 2026-08-23 all three arms of the 53%
  # trio were killed at 5400 s, produced 1.8-2.0 MB of stats, recorded
  # exit_status=0, and the runner reported the trio complete. The arms had
  # stopped at 193e9 / 48.7e9 / 51.9e9 ticks -- a "matched trio" whose members
  # did 4x different amounts of work.
  #
  # Two independent detectors, because one of them can be defeated:
  #   * the watchdog's marker file (misses a manual Ctrl-C);
  #   * gem5's own exit line in run.log (misses a SIGKILL, which leaves no line
  #     and also no stats, so the -s test catches that case).
  local tripped=no interrupted=no
  [[ -e "$arm_out/.tripwire_fired" ]] && tripped=yes
  grep -q "because user interrupt received" "$arm_out/run.log" 2>/dev/null && interrupted=yes
  local completed=yes
  [[ $status -ne 0 || ! -s "$arm_out/stats.txt" || $tripped == yes || $interrupted == yes ]] && completed=no

  printf 'finished_utc=%s\nexit_status=%s\nsimTicks=%s\ntripwire_fired=%s\nuser_interrupt=%s\ncompleted=%s\n' \
    "$(date -u --iso-8601=seconds)" "$status" "${sim_ticks:-unavailable}" \
    "$tripped" "$interrupted" "$completed" >> "$arm_out/provenance.txt"

  if [[ $completed == no ]]; then
    echo "ARM FAILED: $arm -- exit=$status tripwire=$tripped interrupt=$interrupted" \
         "simTicks=${sim_ticks:-unavailable}" >&2
    echo "  Its stats.txt is NOT a result. Do not analyse it." >&2
    return 1
  fi
  echo "ARM OK: $arm simTicks=${sim_ticks:-unavailable} ($(( $(date +%s) )) )"
}

V="$ROOT/testcase/dirtax/victim"
D="$ROOT/testcase/dirtax/dummy"
A="$ROOT/testcase/dirtax/aggressor"
SA="$ROOT/testcase/dutyfree/aggressor"

# The trio aborts at the first failed arm. A trio is only a result if all three
# members ran the same victim workload to completion; continuing after one arm
# was truncated spends hours producing a comparison that cannot be made.
run_arm alone          "$V;$D;$D;$D"    "$WSS_KIB $ITERS;;;"          || { echo "TRIO ABORTED at 'alone'" >&2; exit 3; }
run_arm with_agg       "$V;$A;$A;$A"    "$WSS_KIB $ITERS;$AGG_MB;$AGG_MB;$AGG_MB"  || { echo "TRIO ABORTED at 'with_agg'" >&2; exit 3; }
run_arm with_streaming "$V;$SA;$SA;$SA" "$WSS_KIB $ITERS;$AGG_MB;$AGG_MB;$AGG_MB"  || { echo "TRIO ABORTED at 'with_streaming'" >&2; exit 3; }
echo "TRIO COMPLETE: $OUT"
