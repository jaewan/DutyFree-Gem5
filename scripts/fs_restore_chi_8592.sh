#!/usr/bin/env bash
# Restore a fs_boot_checkpoint.sh checkpoint into the Intel 8592 (EMR) CHI/Ruby
# hierarchy with O3 CPUs and run the --script benchmark. Config is kept IDENTICAL
# to the SE 8592 reference (CHI_config_8592.py, L1d 48K/12, L1i 32K/8, L2 2M/16,
# L3 5M/20, O3 @1.9GHz) so SE and FS are the same machine.
#
# Memory layout MUST match the checkpoint's backing stores. Boot uses a fixed
# DRAM 128GiB + CXL 128GiB (mem-size 256GiB) for every core count, so restore
# uses the same; num-l3caches = num-cpus (LLC = ncpu*5MiB).
# DRAM/CXL device latency defaults: dram 97ns / cxl 198ns -> e2e 111.0/199.0ns,
# validated against real EMR (111.49/199.16, within 0.5%) on the EMR O3 core.
# Override via DRAM_LAT/CXL_LAT env.
#
# Usage: fs_restore_chi_8592.sh <ckpt_name> <run_name> <script.rcS>
#   e.g.: fs_restore_chi_8592.sh atomic_2cpu_hashjoin fs_w3_2c w3_2c.rcS

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# gem5 SysPaths needs M5_PATH to point at an existing dir (kernel/disk are
# absolute, so any existing dir works). Default so this runs unconfigured.
export M5_PATH=${M5_PATH:-$HOME/.cache/gem5}
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
    *8cpu*)  N=8 ;;
    *4cpu*)  N=4 ;;
    *2cpu*)  N=2 ;;
    *) echo "cannot infer num-cpus from $1"; exit 1 ;;
esac

# Fixed layout, must equal boot (fs_boot_checkpoint.sh): DRAM 128 + CXL 128GiB.
MEMARGS=("--mem-size=${MEM:-256GiB}" "--cxl-mem-size=${CXL:-128GiB}")

# A checkpoint is meaningful only together with the exact kernel, base image,
# and simulator that created it.  Refuse a silent provenance mismatch before
# spending hours in detailed simulation.
PROVENANCE=$CKPT/checkpoint.provenance
if [ -s "$PROVENANCE" ]; then
	grep -qx 'boot_checkpoint_complete=true' "$PROVENANCE" || {
		echo "FAIL checkpoint provenance is incomplete: $PROVENANCE" >&2
		exit 2
	}
	mapfile -t cpts < <(find "$CKPT" -mindepth 2 -maxdepth 2 -type f -name m5.cpt -size +0c -printf '%h\n')
	[ ${#cpts[@]} -eq 1 ] || {
		echo "FAIL expected exactly one complete checkpoint" >&2
		exit 2
	}
	while IFS= read -r -d '' artifact; do
		key=$(basename "$artifact" | tr '.-' '__')
		expected=$(sed -n "s/^checkpoint_${key}_sha256=//p" "$PROVENANCE")
		[ -n "$expected" ] || {
			echo "FAIL missing payload hash for $artifact" >&2
			exit 2
		}
		actual=$(sha256sum "$artifact" | awk '{print $1}')
		[ "$actual" = "$expected" ] || {
			echo "FAIL checkpoint payload hash mismatch: $artifact" >&2
			exit 2
		}
	done < <(find "${cpts[0]}" -maxdepth 1 -type f -print0 | sort -z)
    verify_hash()
    {
        key=$1
        path=$2
        expected=$(sed -n "s/^${key}=//p" "$PROVENANCE")
        [ -n "$expected" ] || return 0
        actual=$(sha256sum "$path" | awk '{print $1}')
        [ "$actual" = "$expected" ] || {
            echo "FAIL provenance mismatch: $key ($path)" >&2
            exit 2
        }
    }
    verify_hash kernel_sha256 "$KERNEL"
    verify_hash image_sha256 "$DISK"
    verify_hash gem5_sha256 "$GEM5"
else
    echo "WARN checkpoint has no provenance manifest: $PROVENANCE" >&2
fi

mkdir -p "$OUT"
exec env RUBY_RANDOMIZATION=1 "$GEM5" --outdir="$OUT" "$FS" \
    --kernel="$KERNEL" \
    --disk-image="$DISK" \
    --command-line="$CMDLINE" \
    --script="$RCS" \
    --checkpoint-dir="$CKPT" -r 1 \
    --ruby --topology=Pt2Pt \
    --chi-config="$ROOT/configs/ruby/CHI_config_8592.py" \
    --num-l3caches=$N --num-dirs=1 \
    --cpu-type=O3CPU --restore-with-cpu=O3CPU --num-cpus=$N --cpu-clock=1.9GHz \
    --l1d_size=48KiB --l1d_assoc=12 \
    --l1i_size=32KiB --l1i_assoc=8 \
    --l2_size=2MiB   --l2_assoc=16 \
    --l3_size=5MiB   --l3_assoc=20 \
    --mem-type=SimpleMemory "${MEMARGS[@]}" \
    --dram-latency="$DRAM_LAT" --cxl-latency="$CXL_LAT"
