#!/usr/bin/env bash
# FS-mode boot + restorable checkpoint for the hash_join / STREAMING work.
#
# Fixed platform: Intel 8592 (EMR) gem5 build, custom STREAMING kernel,
# DRAM + CXL layout (DRAM 8GiB + CXL 8GiB x num_cpus; the CXL region is
# carved off the top of the last memory range and exposed to the guest as
# a CPU-less NUMA node1 via ACPI SRAT/SLIT, so mbind/numactl work).
#
# Boot runs on AtomicSimpleCPU. Core/cache config is NOT stored in the
# checkpoint - the O3 + Ruby/CHI 8592 machine is applied at restore time by
# fs_restore_chi_8592.sh - so one boot checkpoint serves every core/cache
# configuration with the same num_cpus and memory layout.
#
# The boot script (hack_back_ckpt.rcS) runs `m5 checkpoint` right after boot
# and re-runs `m5 readfile` on restore, so a new --script (the benchmark rcS)
# can be injected per restore.
#
# Usage: fs_boot_checkpoint.sh <2|4|8|16> [ckpt-name]
#          default ckpt-name: atomic_<N>cpu_cxl_hj
# Env:
#   GEM5             gem5 binary (default: build_Intel_8592/gem5.opt)
#   DISK             disk image (default: hashjoin-v2 copy with the workload
#                    preinstalled at /root/cxl_join_bench.gem5fs)
#   SCRIPT_OVERRIDE  alternate boot rcS. hack_back_ckpt_delay5.rcS shifts the
#                    capture instant past a livelock-prone guest state - it
#                    was required to get a usable 4cpu checkpoint.
#
# Notes:
#   - Do NOT launch restores until this boot process has EXITED: m5.cpt is
#     still being written after the cpt directory appears (parse race).
#   - Kernel console log: <outdir>/system.pc.com_1.device

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEM5=${GEM5:-$ROOT/build_Intel_8592/gem5.opt}
FS=$ROOT/configs/deprecated/example/fs.py
KERNEL=$ROOT/../linux/vmlinux
DISK=${DISK:-$HOME/.cache/gem5/x86-ubuntu-18.04-img-hashjoin-v2}
CMDLINE="earlyprintk=ttyS0 console=ttyS0 lpj=7999923 root=/dev/sda1"
SCRIPT=${SCRIPT_OVERRIDE:-$ROOT/configs/boot/hack_back_ckpt.rcS}
OUT=$ROOT/logs/fs_boot_ckpt

N=${1:?usage: fs_boot_checkpoint.sh <2|4|8|16> [ckpt-name]}
case "$N" in
    2|4|8|16) ;;
    *) echo "num_cpus must be 2, 4, 8 or 16"; exit 1 ;;
esac
MEM=$(( 8 + 8 * N ))GiB          # DRAM 8GiB + CXL 8GiB per core
CXL=$(( 8 * N ))GiB
name=${2:-atomic_${N}cpu_cxl_hj}

mkdir -p $OUT/$name
exec $GEM5 --outdir=$OUT/$name $FS \
    --kernel=$KERNEL \
    --disk-image=$DISK \
    --command-line="$CMDLINE" \
    --script=$SCRIPT \
    --cpu-type=AtomicSimpleCPU --num-cpus=$N \
    --caches \
    --mem-size=$MEM --cxl-mem-size=$CXL \
    --checkpoint-dir=$OUT/$name
