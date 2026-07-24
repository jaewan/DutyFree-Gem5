#!/usr/bin/env bash
# Restore a fs_boot_checkpoint.sh checkpoint into the Intel 8592 (EMR) CHI/Ruby
# hierarchy with O3 CPUs and run the --script benchmark. Config is kept IDENTICAL
# to the SE 8592 reference (CHI_config_8592.py, L1d 48K/12, L1i 32K/8, L2 2M/16,
# L3 5M/20, O3 @1.9GHz) so SE and FS are the same machine.
#
# Memory layout MUST match the checkpoint's backing stores (boot mem-size/cxl,
# i.e. DRAM 8GiB + CXL 8GiB per cpu):
#   *2cpu_cxl*  : --mem-size=24GiB  --cxl-mem-size=16GiB
#   *4cpu_cxl*  : --mem-size=40GiB  --cxl-mem-size=32GiB
#   *8cpu_cxl*  : --mem-size=72GiB  --cxl-mem-size=64GiB
#   *16cpu_cxl* : --mem-size=136GiB --cxl-mem-size=128GiB
# num-l3caches = num-cpus (per 8592 dirtax convention -> LLC = ncpu*5MiB).
# DRAM/CXL device latency defaults: dram 97ns / cxl 198ns -> e2e 111.0/199.0ns,
# validated against real EMR (111.49/199.16, within 0.5%) on the EMR O3 core.
# Override via DRAM_LAT/CXL_LAT env.
#
# Usage: fs_restore_chi_8592.sh <ckpt_name> <run_name> <script.rcS>
#   e.g.: fs_restore_chi_8592.sh atomic_2cpu_cxl_hj hj_smoke_2c logs/fs_restore_chi/hashjoin_smoke.rcS

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEM5=${GEM5:-$ROOT/build_Intel_8592/gem5.opt}
FS=$ROOT/configs/deprecated/example/fs.py
KERNEL=$ROOT/../linux/vmlinux
# Default to the v2 image (workload with --line-stride installed), matching
# fs_boot_checkpoint.sh. Safe with v1-booted checkpoints too: boot never reads
# /root/cxl_join_bench.gem5fs, so its blocks are not in the guest page cache.
DISK=${DISK:-$HOME/.cache/gem5/x86-ubuntu-18.04-img-hashjoin-v2}
CMDLINE="earlyprintk=ttyS0 console=ttyS0 lpj=7999923 root=/dev/sda1"
CKPT=$ROOT/logs/fs_boot_ckpt/$1
RUN=$2
RCS=$3
OUT=$ROOT/logs/fs_restore_chi/$RUN
DRAM_LAT=${DRAM_LAT:-97ns}
CXL_LAT=${CXL_LAT:-198ns}

case "$1" in
    *16cpu*) N=16 ;;
    *2cpu*) N=2 ;;
    *4cpu*) N=4 ;;
    *8cpu*) N=8 ;;
    *) echo "cannot infer num-cpus from $1"; exit 1 ;;
esac

case "$1" in
    *16cpu_cxl*) MEMARGS="--mem-size=136GiB --cxl-mem-size=128GiB" ;;
    *2cpu_cxl*) MEMARGS="--mem-size=24GiB --cxl-mem-size=16GiB" ;;
    *4cpu_cxl*) MEMARGS="--mem-size=40GiB --cxl-mem-size=32GiB" ;;
    *8cpu_cxl*) MEMARGS="--mem-size=72GiB --cxl-mem-size=64GiB" ;;
    *)          MEMARGS="--mem-size=3GiB" ;;
esac

mkdir -p $OUT
exec env RUBY_RANDOMIZATION=1 $GEM5 --outdir=$OUT $FS \
    --kernel=$KERNEL \
    --disk-image=$DISK \
    --command-line="$CMDLINE" \
    --script=$RCS \
    --checkpoint-dir=$CKPT -r 1 \
    --ruby --topology=Pt2Pt \
    --chi-config=$ROOT/configs/ruby/CHI_config_8592.py \
    --num-l3caches=$N --num-dirs=1 \
    --cpu-type=O3CPU --restore-with-cpu=O3CPU --num-cpus=$N --cpu-clock=1.9GHz \
    --l1d_size=48KiB --l1d_assoc=12 \
    --l1i_size=32KiB --l1i_assoc=8 \
    --l2_size=2MiB   --l2_assoc=16 \
    --l3_size=5MiB   --l3_assoc=20 \
    --mem-type=SimpleMemory $MEMARGS --dram-latency=$DRAM_LAT --cxl-latency=$CXL_LAT
