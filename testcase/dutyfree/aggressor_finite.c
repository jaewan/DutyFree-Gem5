#include <stdio.h>
#include <stdlib.h>

/* Sequential aggressor — finite, bandwidth-maximizing variant, DutyFree
 * (STREAMING / LLC+PF bypass).
 * argv[1] = size_mb (float, default 16.0)  argv[2] = passes (int, default 4)
 * argv[3] = pfdist (int, SW-prefetch distance in elements; 0 = off)
 *
 * Same BW-max design as dirtax/aggressor_finite.c (non-volatile long, 16
 * accumulators + 16x unroll, warmup + gem5_reset_stats for steady-state ROI,
 * no per-iteration store → immune to commit d821212e9d's store-set bug). The
 * only difference is gem5_set_streaming(). !!! BUILD WITH -O3 -march=x86-64
 * -ftree-vectorize !!! (SSE2).
 *
 * Ordering for the streaming read-only contract: init WRITES arr → mark
 * streaming → warmup + measured reads are read-only (no write in the epoch). */

static inline void gem5_set_streaming(void *addr, long size) {
    unsigned long m5_rax;
    __asm__ volatile(".byte 0x0f, 0x04, 0x55, 0x00"
                     : "=a"(m5_rax) : "D"((long)addr), "S"(size));
    (void)m5_rax;
}
static inline void gem5_exit(void) {
    unsigned long m5_rax;
    __asm__ volatile(".byte 0x0f, 0x04, 0x21, 0x00"
                     : "=a"(m5_rax) : "D"(0ULL));
    (void)m5_rax;
}
static inline void gem5_reset_stats(void) {
    unsigned long m5_rax;
    __asm__ volatile(".byte 0x0f, 0x04, 0x40, 0x00"
                     : "=a"(m5_rax) : "D"(0ULL), "S"(0ULL));
    (void)m5_rax;
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

    /* Mark streaming region AFTER init writes, BEFORE the read-only passes. */
    gem5_set_streaming((void*)arr, N * (long)sizeof(long));

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
