#include <stdio.h>
#include <stdlib.h>

/* Sequential aggressor — finite, bandwidth-maximizing (the default finite
 * aggressor; standalone BW / prefetch test).
 * argv[1] = size_mb  (float, default 16.0; footprint must exceed LLC)
 * argv[2] = passes   (int,   default 4, measured after 1 warmup pass)
 * argv[3] = pfdist   (int,   SW-prefetch distance in elements; 0 = off)
 *
 * BW-max design (see aggressor.c for rationale): non-volatile `long`,
 * 16 independent accumulators + 16x unroll, no per-iteration store (immune to
 * the store-set serialization of commit d821212e9d). The init loop writes arr
 * so -O3 cannot fold the reads as zero BSS. A warmup pass trains the
 * prefetcher, then gem5_reset_stats() discards it so the measured window is
 * steady-state ROI only. Single-core: ~13.7 GB/s @ -O3 (vs ~1.9 for the
 * original). !!! BUILD WITH -O3 -march=x86-64 -ftree-vectorize !!! (SSE2). */

static inline void gem5_exit(void) {
    __asm__ volatile(".byte 0x0f, 0x04, 0x21, 0x00" : : "D"(0ULL));
}
static inline void gem5_reset_stats(void) {
    __asm__ volatile(".byte 0x0f, 0x04, 0x40, 0x00" : : "D"(0ULL), "S"(0ULL));
}

#define MAX_MB 512
#define UNROLL 16
static long arr[(long)MAX_MB * 1024 * 1024 / sizeof(long)];

int main(int argc, char *argv[])
{
    double size_mb = argc > 1 ? atof(argv[1]) : 16.0;
    int    passes  = argc > 2 ? atoi(argv[2]) : 4;
    long   pfdist  = argc > 3 ? atol(argv[3]) : 0;
    if (size_mb > MAX_MB) size_mb = MAX_MB;
    long N = (long)(size_mb * 1024.0 * 1024.0) / (long)sizeof(long);
    long limit = N - (N % UNROLL);

    for (long i = 0; i < N; i++) arr[i] = i;   /* non-zero init + first-touch */

    static volatile unsigned long sink;
    unsigned long w = 0;
    for (long i = 0; i < N; i++) w += (unsigned long)arr[i];   /* warmup: PF */
    sink = w;

    gem5_reset_stats();                                        /* ROI only */

    unsigned long a[UNROLL];
    for (int k = 0; k < UNROLL; k++) a[k] = 0;
    for (int p = 0; p < passes; p++) {
        if (pfdist) {
            for (long i = 0; i < limit; i += UNROLL) {
                __builtin_prefetch(&arr[i + pfdist], 0, 0);
                for (int k = 0; k < UNROLL; k++) a[k] += (unsigned long)arr[i + k];
            }
        } else {
            for (long i = 0; i < limit; i += UNROLL)
                for (int k = 0; k < UNROLL; k++) a[k] += (unsigned long)arr[i + k];
        }
        for (long i = limit; i < N; i++) a[0] += (unsigned long)arr[i];
    }
    unsigned long s = 0;
    for (int k = 0; k < UNROLL; k++) s += a[k];
    sink = s;

    printf("aggressor_finite(%.1fMB x%d pf%ld): sum=%lu\n",
           size_mb, passes, pfdist, (unsigned long)sink);
    gem5_exit();
    return 0;
}
