#!/usr/bin/env bash
# CHI protocol version of latency_test.sh
#
# Cache hierarchy (per CPU):
#   L1D 32KiB 8-way  |  L1I 64KiB 8-way  |  private L2 512KiB 8-way
#   shared L3 (HNF) 16MiB 16-way
#
# Working sets (1t):
#   L1:  N=2048    (8KB   << 32KB L1D),   iters=4096
#   L2:  N=65536   (256KB << 512KB L2),   iters=512,  flush=32768
#   L3:  N=524288  (2MB   << 16MB L3),    iters=512,  flush=262144
#   MEM: N=4194304 (16MB  >= 16MB L3),    iters=2,    flush=N
#
# Working sets (8t) — 8 CPUs share the 16MB L3, independent address spaces:
#   L1:  same as 1t (private L1 per CPU)
#   L2:  same as 1t (private L2 per CPU)
#   L3:  N=262144  (1MB/CPU × 8 = 8MB  << 16MB L3), flush=131072
#   MEM: N=1048576 (4MB/CPU × 8 = 32MB >> 16MB L3), flush=N

mkdir -p /home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency

echo "=== Launching CHI latency tests ==="

# ── L1 read ───────────────────────────────────────────────────────────────────
/home/naivete/DutyFree-Gem5-pakeunji/build_X86_CHI/gem5.opt --outdir=/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/l1_read_1t_m5out \
    /home/naivete/DutyFree-Gem5-pakeunji/configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=1 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c /home/naivete/DutyFree-Gem5-pakeunji/testcase/latency/latency_bench \
    -o "2048 1277 4096 r 0" \
    > /home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/l1_read_1t.log 2>&1 &
echo "  started: l1_read_1t"

/home/naivete/DutyFree-Gem5-pakeunji/build_X86_CHI/gem5.opt --outdir=/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/l1_read_8t_m5out \
    /home/naivete/DutyFree-Gem5-pakeunji/configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0;2048 1277 4096 r 0" \
    > /home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/l1_read_8t.log 2>&1 &
echo "  started: l1_read_8t"

# ── L1 write ──────────────────────────────────────────────────────────────────
/home/naivete/DutyFree-Gem5-pakeunji/build_X86_CHI/gem5.opt --outdir=/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/l1_write_1t_m5out \
    /home/naivete/DutyFree-Gem5-pakeunji/configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=1 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c /home/naivete/DutyFree-Gem5-pakeunji/testcase/latency/latency_bench \
    -o "2048 1277 4096 w 0" \
    > /home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/l1_write_1t.log 2>&1 &
echo "  started: l1_write_1t"

/home/naivete/DutyFree-Gem5-pakeunji/build_X86_CHI/gem5.opt --outdir=/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/l1_write_8t_m5out \
    /home/naivete/DutyFree-Gem5-pakeunji/configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "2048 1277 4096 w 0;2048 1277 4096 w 0;2048 1277 4096 w 0;2048 1277 4096 w 0;2048 1277 4096 w 0;2048 1277 4096 w 0;2048 1277 4096 w 0;2048 1277 4096 w 0" \
    > /home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/l1_write_8t.log 2>&1 &
echo "  started: l1_write_8t"

# ── L2 read (private per-CPU L2: 512KiB) ─────────────────────────────────────
/home/naivete/DutyFree-Gem5-pakeunji/build_X86_CHI/gem5.opt --outdir=/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/l2_read_1t_m5out \
    /home/naivete/DutyFree-Gem5-pakeunji/configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=1 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c /home/naivete/DutyFree-Gem5-pakeunji/testcase/latency/latency_bench \
    -o "65536 40504 512 r 32768" \
    > /home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/l2_read_1t.log 2>&1 &
echo "  started: l2_read_1t"

/home/naivete/DutyFree-Gem5-pakeunji/build_X86_CHI/gem5.opt --outdir=/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/l2_read_8t_m5out \
    /home/naivete/DutyFree-Gem5-pakeunji/configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "65536 40504 512 r 32768;65536 40504 512 r 32768;65536 40504 512 r 32768;65536 40504 512 r 32768;65536 40504 512 r 32768;65536 40504 512 r 32768;65536 40504 512 r 32768;65536 40504 512 r 32768" \
    > /home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/l2_read_8t.log 2>&1 &
echo "  started: l2_read_8t"

# ── L2 write ──────────────────────────────────────────────────────────────────
/home/naivete/DutyFree-Gem5-pakeunji/build_X86_CHI/gem5.opt --outdir=/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/l2_write_1t_m5out \
    /home/naivete/DutyFree-Gem5-pakeunji/configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=1 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c /home/naivete/DutyFree-Gem5-pakeunji/testcase/latency/latency_bench \
    -o "65536 40504 512 w 32768" \
    > /home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/l2_write_1t.log 2>&1 &
echo "  started: l2_write_1t"

/home/naivete/DutyFree-Gem5-pakeunji/build_X86_CHI/gem5.opt --outdir=/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/l2_write_8t_m5out \
    /home/naivete/DutyFree-Gem5-pakeunji/configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "65536 40504 512 w 32768;65536 40504 512 w 32768;65536 40504 512 w 32768;65536 40504 512 w 32768;65536 40504 512 w 32768;65536 40504 512 w 32768;65536 40504 512 w 32768;65536 40504 512 w 32768" \
    > /home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/l2_write_8t.log 2>&1 &
echo "  started: l2_write_8t"

# ── L3 read (shared HNF: 16MiB) ───────────────────────────────────────────────
/home/naivete/DutyFree-Gem5-pakeunji/build_X86_CHI/gem5.opt --outdir=/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/l3_read_1t_m5out \
    /home/naivete/DutyFree-Gem5-pakeunji/configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=1 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c /home/naivete/DutyFree-Gem5-pakeunji/testcase/latency/latency_bench \
    -o "524288 324011 512 r 262144" \
    > /home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/l3_read_1t.log 2>&1 &
echo "  started: l3_read_1t"

/home/naivete/DutyFree-Gem5-pakeunji/build_X86_CHI/gem5.opt --outdir=/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/l3_read_8t_m5out \
    /home/naivete/DutyFree-Gem5-pakeunji/configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "262144 162007 512 r 131072;262144 162007 512 r 131072;262144 162007 512 r 131072;262144 162007 512 r 131072;262144 162007 512 r 131072;262144 162007 512 r 131072;262144 162007 512 r 131072;262144 162007 512 r 131072" \
    > /home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/l3_read_8t.log 2>&1 &
echo "  started: l3_read_8t"

# ── L3 write ──────────────────────────────────────────────────────────────────
/home/naivete/DutyFree-Gem5-pakeunji/build_X86_CHI/gem5.opt --outdir=/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/l3_write_1t_m5out \
    /home/naivete/DutyFree-Gem5-pakeunji/configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=1 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c /home/naivete/DutyFree-Gem5-pakeunji/testcase/latency/latency_bench \
    -o "524288 324011 512 w 262144" \
    > /home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/l3_write_1t.log 2>&1 &
echo "  started: l3_write_1t"

/home/naivete/DutyFree-Gem5-pakeunji/build_X86_CHI/gem5.opt --outdir=/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/l3_write_8t_m5out \
    /home/naivete/DutyFree-Gem5-pakeunji/configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "262144 162007 512 w 131072;262144 162007 512 w 131072;262144 162007 512 w 131072;262144 162007 512 w 131072;262144 162007 512 w 131072;262144 162007 512 w 131072;262144 162007 512 w 131072;262144 162007 512 w 131072" \
    > /home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/l3_write_8t.log 2>&1 &
echo "  started: l3_write_8t"

# ── MEM read ──────────────────────────────────────────────────────────────────
/home/naivete/DutyFree-Gem5-pakeunji/build_X86_CHI/gem5.opt --outdir=/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/mem_read_1t_m5out \
    /home/naivete/DutyFree-Gem5-pakeunji/configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=1 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c /home/naivete/DutyFree-Gem5-pakeunji/testcase/latency/latency_bench \
    -o "4194304 2592089 2 r 4194304" \
    > /home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/mem_read_1t.log 2>&1 &
echo "  started: mem_read_1t"

/home/naivete/DutyFree-Gem5-pakeunji/build_X86_CHI/gem5.opt --outdir=/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/mem_read_8t_m5out \
    /home/naivete/DutyFree-Gem5-pakeunji/configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "1048576 648019 2 r 1048576;1048576 648019 2 r 1048576;1048576 648019 2 r 1048576;1048576 648019 2 r 1048576;1048576 648019 2 r 1048576;1048576 648019 2 r 1048576;1048576 648019 2 r 1048576;1048576 648019 2 r 1048576" \
    > /home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/mem_read_8t.log 2>&1 &
echo "  started: mem_read_8t"

# ── MEM write ─────────────────────────────────────────────────────────────────
/home/naivete/DutyFree-Gem5-pakeunji/build_X86_CHI/gem5.opt --outdir=/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/mem_write_1t_m5out \
    /home/naivete/DutyFree-Gem5-pakeunji/configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=1 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c /home/naivete/DutyFree-Gem5-pakeunji/testcase/latency/latency_bench \
    -o "4194304 2592089 2 w 4194304" \
    > /home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/mem_write_1t.log 2>&1 &
echo "  started: mem_write_1t"

/home/naivete/DutyFree-Gem5-pakeunji/build_X86_CHI/gem5.opt --outdir=/home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/mem_write_8t_m5out \
    /home/naivete/DutyFree-Gem5-pakeunji/configs/deprecated/example/se.py \
    --ruby --topology=Pt2Pt --num-l3caches=1 --num-dirs=1 \
    --cpu-type=TimingSimpleCPU --num-cpus=8 \
    --l1d_size=32KiB --l1d_assoc=8 --l1i_size=64KiB --l1i_assoc=8 \
    --l2_size=512KiB --l2_assoc=8 --l3_size=16MiB --l3_assoc=16 \
    -c "testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench;testcase/latency/latency_bench" \
    -o "1048576 648019 2 w 1048576;1048576 648019 2 w 1048576;1048576 648019 2 w 1048576;1048576 648019 2 w 1048576;1048576 648019 2 w 1048576;1048576 648019 2 w 1048576;1048576 648019 2 w 1048576;1048576 648019 2 w 1048576" \
    > /home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/mem_write_8t.log 2>&1 &
echo "  started: mem_write_8t"

echo ""
echo "All launched (14 tests). Check logs in /home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/"
echo "Results: grep 'Exiting @ tick' /home/naivete/DutyFree-Gem5-pakeunji/logs/intel_latency/*.log"
