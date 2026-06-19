#include <stdio.h>
#include <stdlib.h>

/* Sequential streaming aggressor — bandwidth-maximizing variant of aggressor.c.
 * argv[1] = size_mb  (float, default 4.0)
 * Infinite loop — runs until gem5 simulation ends (victim calls m5_exit).
 *
 * Why this exists: aggressor.c (volatile int + single accumulator) is
 * compute-bound — the HW prefetcher hides all memory latency (L1 hit ~98%)
 * and the serial `sum +=` chain caps the core at ~1.9 GB/s single-core,
 * independent of memory latency or TBE budget. This variant lifts the
 * consumption ceiling to ~14 GB/s:
 *   - non-volatile `long` (8B) reads     → vectorizable, half the loads/line
 *   - 16 independent accumulators + 16x   → breaks the reduction dep chain
 *   - one sink store per scan only        → immune to the O3 store-set
 *     serialization fixed in commit d821212e9d (no per-iteration store)
 * The init loop writes arr (so -O3 cannot fold the reads away as zero BSS).
 *
 * !!! BUILD WITH -O3 -march=x86-64 -ftree-vectorize !!! (SSE2 `paddq`,
 * 16B/instr). At -O1 the loop stays scalar (~5 GB/s). gem5 x86 O3 runs SSE2
 * fine; do NOT use -mavx. Static array keeps gem5 SE VMA tracking stable. */

#define MAX_MB 512
#define UNROLL 16
static long arr[(long)MAX_MB * 1024 * 1024 / sizeof(long)];

int main(int argc, char *argv[])
{
    double size_mb = argc > 1 ? atof(argv[1]) : 4.0;
    if (size_mb > MAX_MB) size_mb = MAX_MB;
    long N = (long)(size_mb * 1024.0 * 1024.0) / (long)sizeof(long);
    long limit = N - (N % UNROLL);

    for (long i = 0; i < N; i++) arr[i] = i;   /* non-zero init + first-touch */

    static volatile unsigned long sink;
    unsigned long a[UNROLL];
    for (int k = 0; k < UNROLL; k++) a[k] = 0;
    while (1) {
        for (long i = 0; i < limit; i += UNROLL)
            for (int k = 0; k < UNROLL; k++) a[k] += (unsigned long)arr[i + k];
        for (long i = limit; i < N; i++) a[0] += (unsigned long)arr[i];
        unsigned long s = 0;
        for (int k = 0; k < UNROLL; k++) s += a[k];
        sink = s;  /* one store per scan keeps the read loop live */
    }
}
