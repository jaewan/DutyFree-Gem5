#!/usr/bin/env bash
# Run one hash_join workload in gem5 FS mode: restore a boot checkpoint onto
# the frozen Intel 8592 (EMR) machine and run the workload via an rcS.
# Requires a boot checkpoint from fs_boot_checkpoint.sh: atomic_<N>cpu_hashjoin.
# Usage:
#   run_fs.sh <w1o|w1ls|w2|w3> <ncores> <reps>
#     w1o = W1(original)   w1ls = W1(line-stride)
#     w2  = quiescent probe   w3 = morsel WB
#     (w4 = morsel H2 is SE-only: FS needs a kernel change, not supported yet)
# e.g.  run_fs.sh w3 2 3
set -u
[ $# -eq 3 ] || { echo "usage: $0 <w1o|w1ls|w2|w3> <ncores> <reps>"; exit 1; }
WL=$1; N=$2; REPS=$3
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN=/root/cxl_join_bench.gem5fs                  # installed in the disk image
HOT=$(( N * 5 * 1024 * 1024 * 53 / 100 ))        # 53% of N x 5MiB LLC

case "$WL" in
  w1o)  ARGS="--mode stream-smoke --policy wb --threads 1 --cpu-list 0" ;;
  w1ls) ARGS="--mode stream-smoke --policy wb --threads 1 --cpu-list 0 --line-stride" ;;
  w2)   ARGS="--mode probe-workload --policy wb --hot-bytes $HOT --threads $N --cpu-list 0-$((N-1))" ;;
  w3)   ARGS="--mode morsel --policy wb --hot-bytes $HOT --threads $N --cpu-list 0-$((N-1)) --morsel 1m --check" ;;
  w4)   echo "w4 (morsel H2) is not supported in FS: the STREAMING kernel gates MAP_STREAMING to device-DAX. Run w4 in SE (run_se.sh)."; exit 1 ;;
  *) echo "unknown workload: $WL"; exit 1 ;;
esac

CKPT=atomic_${N}cpu_hashjoin
RCS=$ROOT/logs/fs_restore_chi/run_${WL}_${N}c.rcS
cat > "$RCS" <<EOF
$BIN $ARGS --fact-bytes 1g --fact-node 1 --hot-node 0 --warmups 1 --reps $REPS
m5 exit
EOF
exec bash "$ROOT/scripts/fs_restore_chi_8592.sh" "$CKPT" "fs_${WL}_${N}c_r${REPS}" "$RCS"
