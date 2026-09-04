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
# The reconstructed W8 rootfs owns its own boot/checkpoint/readfile protocol.
# Its init takes exactly one checkpoint and loads the restore-time rcS through
# `m5 readfile`.  The injected boot script must therefore be empty by default:
# supplying gem5's legacy hack_back_ckpt.rcS would create a second checkpoint
# protocol inside the guest and invalidate the checkpoint finalization.
#
# Usage: fs_boot_checkpoint.sh <2|4|8|16> [ckpt-name]
#          default ckpt-name: atomic_<N>cpu_cxl_hj
# Env:
#   GEM5             gem5 binary (default: build_Intel_8592/gem5.opt)
#   DISK             disk image (default: hashjoin-v2 copy with the workload
#                    preinstalled at /root/cxl_join_bench.gem5fs)
#   SCRIPT_OVERRIDE  alternate file injected into the guest at boot. The W8
#                    default is intentionally an empty file; benchmark rcS
#                    files are injected only by fs_restore_chi_8592.sh.
#
# Notes:
#   - Do NOT launch restores until this boot process has EXITED: m5.cpt is
#     still being written after the cpt directory appears (parse race).
#   - Kernel console log: <outdir>/system.pc.com_1.device

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_identity()
{
    local repo=$1

    SOURCE_HEAD=$(git -C "$repo" rev-parse HEAD)
    SOURCE_DIRTY=$([ -n "$(git -C "$repo" status --porcelain=v1 --untracked-files=all)" ] &&
                   printf true || printf false)
    SOURCE_FINGERPRINT=$(
      {
        printf 'HEAD %s\n' "$SOURCE_HEAD"
        git -C "$repo" diff --binary HEAD --
        git -C "$repo" ls-files --others --exclude-standard -z | while IFS= read -r -d '' file; do
          printf 'UNTRACKED %s ' "$file"
          sha256sum "$repo/$file" | awk '{print $1}'
        done
      } | sha256sum | awk '{print $1}'
    )
}
# gem5's SysPaths needs M5_PATH to point at an existing dir; kernel/disk are
# passed as absolute paths so any existing dir works. Default to the image
# cache so this runs without a preset environment.
export M5_PATH=${M5_PATH:-$HOME/.cache/gem5}
GEM5=${GEM5:-$ROOT/build_Intel_8592/gem5.opt}
FS=$ROOT/configs/deprecated/example/fs.py
KERNEL=$ROOT/../linux/vmlinux
DISK=${DISK:-$HOME/.cache/gem5/x86-ubuntu-18.04-img-hashjoin-v2}
CMDLINE="earlyprintk=ttyS0 console=ttyS0 lpj=7999923 root=/dev/sda1"
SCRIPT=${SCRIPT_OVERRIDE:-$ROOT/../benchmarks/e2e/hash_join/w8/empty.rcS}
OUT=$ROOT/logs/fs_boot_ckpt

N=${1:?usage: fs_boot_checkpoint.sh <2|4|8|16> [ckpt-name]}
case "$N" in
    2|4|8|16) ;;
    *) echo "num_cpus must be 2, 4, 8 or 16"; exit 1 ;;
esac
# Fixed layout for every core count: DRAM 128GiB + CXL 128GiB. SimpleMemory
# backing store is lazily faulted, so only touched pages cost RAM (fact 1g +
# hot table + kernel ~ a few GB); checkpoints stay sparse. Keeping it uniform
# means the only per-run knob is the core count, and boot/restore always match.
MEM=${MEM:-256GiB}
CXL=${CXL:-128GiB}
name=${2:-atomic_${N}cpu_hashjoin}
PROV="$DISK.provenance"

[ ! -e "$OUT/$name" ] || { echo "FAIL checkpoint output already exists: $OUT/$name" >&2; exit 2; }
[ -s "$KERNEL" ] && [ -s "$DISK" ] && [ -s "$PROV" ] && [ -x "$GEM5" ] && [ -f "$SCRIPT" ] || {
    echo "FAIL missing kernel, image/provenance, gem5 binary, or injected script" >&2; exit 2;
}
IMAGE_SHA=$(sha256sum "$DISK" | awk '{print $1}')
grep -qx "image_sha256=$IMAGE_SHA" "$PROV" || { echo "FAIL image/provenance mismatch" >&2; exit 2; }
GUEST_SHA=$(sed -n 's/^guest_bench_sha256=//p' "$PROV")
[ -n "$GUEST_SHA" ] || { echo "FAIL image provenance has no guest binary hash" >&2; exit 2; }
source_identity "$ROOT"
GEM5_SOURCE_HEAD=$SOURCE_HEAD
GEM5_SOURCE_DIRTY=$SOURCE_DIRTY
GEM5_SOURCE_FINGERPRINT=$SOURCE_FINGERPRINT
source_identity "$ROOT/../linux"
LINUX_SOURCE_HEAD=$SOURCE_HEAD
LINUX_SOURCE_DIRTY=$SOURCE_DIRTY
LINUX_SOURCE_FINGERPRINT=$SOURCE_FINGERPRINT
mkdir -p "$OUT/$name"
WRITER_MARKER="$OUT/$name/.checkpoint-writer-active"
touch "$WRITER_MARKER"
cleanup_writer_marker()
{
    rm -f "$WRITER_MARKER"
}
trap cleanup_writer_marker EXIT
"$GEM5" --outdir="$OUT/$name" "$FS" \
    --kernel="$KERNEL" \
    --disk-image="$DISK" \
    --command-line="$CMDLINE" \
    --script="$SCRIPT" \
    --cpu-type=AtomicSimpleCPU --num-cpus="$N" \
    --caches \
    --mem-size="$MEM" --cxl-mem-size="$CXL" \
    --checkpoint-dir="$OUT/$name"
mapfile -t cpts < <(find "$OUT/$name" -mindepth 2 -maxdepth 2 -type f -name m5.cpt -size +0c -printf '%h\n')
[ ${#cpts[@]} -eq 1 ] || { echo "FAIL checkpoint incomplete" >&2; exit 2; }
manifest_tmp="$OUT/$name/.checkpoint.provenance.$$"
{
    printf 'format=streaming-fs-checkpoint-v3\nnum_cpus=%s\nmemory=%s\ncxl_memory=%s\n' \
        "$N" "$MEM" "$CXL"
    printf 'kernel_sha256=%s\nimage_sha256=%s\nguest_bench_sha256=%s\ngem5_sha256=%s\nboot_script_sha256=%s\nfs_config_sha256=%s\ngem5_source_head=%s\ngem5_source_dirty=%s\ngem5_source_fingerprint=%s\nlinux_source_head=%s\nlinux_source_dirty=%s\nlinux_source_fingerprint=%s\n' \
        "$(sha256sum "$KERNEL" | awk '{print $1}')" \
        "$IMAGE_SHA" "$GUEST_SHA" \
        "$(sha256sum "$GEM5" | awk '{print $1}')" \
        "$(sha256sum "$0" | awk '{print $1}')" \
        "$(sha256sum "$FS" | awk '{print $1}')" \
        "$GEM5_SOURCE_HEAD" "$GEM5_SOURCE_DIRTY" "$GEM5_SOURCE_FINGERPRINT" \
        "$LINUX_SOURCE_HEAD" "$LINUX_SOURCE_DIRTY" "$LINUX_SOURCE_FINGERPRINT"
    printf 'boot_guest_script_sha256=%s\n' "$(sha256sum "$SCRIPT" | awk '{print $1}')"
} > "$manifest_tmp"
while IFS= read -r -d '' artifact; do
    key=$(basename "$artifact" | tr '.-' '__')
    printf 'checkpoint_%s_sha256=%s\n' "$key" \
        "$(sha256sum "$artifact" | awk '{print $1}')"
done < <(find "${cpts[0]}" -maxdepth 1 -type f -print0 | sort -z) \
    >> "$manifest_tmp"
printf 'boot_checkpoint_complete=true\n' >> "$manifest_tmp"
mv "$manifest_tmp" "$OUT/$name/checkpoint.provenance"
rm -f "$WRITER_MARKER"
trap - EXIT
echo "checkpoint provenance $OUT/$name/checkpoint.provenance"
