#!/usr/bin/env bash
# Run a hash_join workload in gem5 SE mode on the frozen Intel 8592 (EMR)
# machine. Usage:
#   run_se.sh <w1o|w1ls|w2|w3|w4|all> <ncores> <reps>
#     w1o  = W1(original)   w1ls = W1(line-stride)  -- each launches WB/H2/WC arms
#     w2   = quiescent probe   w3 = morsel WB   w4 = morsel H2(stream)
#     all  = launch w1o w1ls w2 w3 w4 concurrently in the background
# e.g.  run_se.sh w4 8 3     run_se.sh all 8 3
set -u
[ $# -eq 3 ] || { echo "usage: $0 <w1o|w1ls|w2|w3|w4|all> <ncores> <reps>"; exit 1; }
WL=$1; N=$2; REPS=$3
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN=$ROOT/../benchmarks/e2e/hash_join_gem5se/build/cxl_join_bench.gem5se
HOT=$(( N * 5 * 1024 * 1024 * 53 / 100 ))        # 53% of N x 5MiB LLC

# Frozen config only (L1_MSHR=16, PF 4/8, 4KiB). The one-off MSHR/prefetcher
# knee sweep lives in a separate script (knee_sweep.sh), not here.

# gem5 <outdir> <mode> <policy> <extra-opts> <ls> <place-env> <ncpus> <threads> <cpulist> <pf-off>
run_gem5() {
  local out=$1 mode=$2 pol=$3 extra=$4 ls=$5 place=$6 nc=$7 threads=$8 cpul=$9 pfoff=${10:-}
  local pfenv=""; [ -n "$pfoff" ] && pfenv="PF_OFF_CORES=$pfoff"
  env RUBY_RANDOMIZATION=1 $place $pfenv \
      L1_MSHR=16 PF_DEGREE_L1=4 PF_DEGREE_L2=8 PF_PAGE=4KiB \
  $ROOT/build_Intel_8592/gem5.opt --outdir=$out \
    $ROOT/configs/deprecated/example/se.py --cmd=$BIN \
    --options="--mode $mode --policy $pol --fact-bytes 1g --fact-node 1 --hot-node 0 \
               --threads $threads --cpu-list $cpul --warmups 1 --reps $REPS $extra $ls" \
    --ruby --topology=Pt2Pt --chi-config=$ROOT/configs/ruby/CHI_config_8592.py \
    --num-l3caches=$N --num-dirs=1 --cpu-type=O3CPU --num-cpus=$nc --cpu-clock=1.9GHz \
    --l1d_size=48KiB --l1d_assoc=12 --l1i_size=32KiB --l1i_assoc=8 \
    --l2_size=2MiB --l2_assoc=16 --l3_size=5MiB --l3_assoc=20 \
    --mem-type=SimpleMemory --mem-size=256GiB --cxl-mem-size=128GiB \
    --dram-latency=98ns --cxl-latency=203ns
}

# W1 (single core, ALL_CXL): launch WB/H2/WC arms. ls="" for orig, "--line-stride" for w1ls.
run_w1() {
  local tag=$1 ls=$2
  local base=$ROOT/logs/se_chi/se_${tag}
  run_gem5 ${base}_wb_${N}c stream-smoke wb     "" "$ls" ALL_CXL=1 1 1 0 "" > ${base}_wb_${N}c.launch.log 2>&1 &
  echo "  launched ${tag}_wb_${N}c (pid $!)"
  run_gem5 ${base}_h2_${N}c stream-smoke stream "" "$ls" ALL_CXL=1 1 1 0 "" > ${base}_h2_${N}c.launch.log 2>&1 &
  echo "  launched ${tag}_h2_${N}c (pid $!)"
  run_gem5 ${base}_wc_${N}c stream-smoke stream "" "$ls" ALL_CXL=1 1 1 0 "0" > ${base}_wc_${N}c.launch.log 2>&1 &
  echo "  launched ${tag}_wc_${N}c (pid $!)"
}

launch_one() {
  local wl=$1
  case "$wl" in
    w1o)  run_w1 w1o "" ;;
    w1ls) run_w1 w1ls "--line-stride" ;;
    w2)   run_gem5 $ROOT/logs/se_chi/se_w2_${N}c probe-workload wb "--hot-bytes $HOT" "" "" $N $N "0-$((N-1))" ;;
    w3)   run_gem5 $ROOT/logs/se_chi/se_w3_${N}c morsel wb     "--hot-bytes $HOT --morsel 1m --check" "" "" $((N+1)) $N "0-$N" ;;
    w4)   run_gem5 $ROOT/logs/se_chi/se_w4_${N}c morsel stream "--hot-bytes $HOT --morsel 1m --check" "" "" $((N+1)) $N "0-$N" ;;
    *) echo "unknown workload: $wl"; exit 1 ;;
  esac
}

if [ "$WL" = all ]; then
  for w in w1o w1ls w2 w3 w4; do launch_one "$w"; sleep 2; done
  wait
else
  launch_one "$WL"   # w1o/w1ls background their 3 arms; others run single
fi
