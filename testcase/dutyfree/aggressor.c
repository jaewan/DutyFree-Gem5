#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Sequential streaming aggressor — bandwidth-maximizing variant, DutyFree
 * (STREAMING / LLC+PF bypass). argv[1] = size_mb (float, default 4.0).
 * Infinite loop — runs until gem5 simulation ends (victim calls m5_exit).
 *
 * Same BW-max design as dirtax/aggressor.c (non-volatile long, 16
 * accumulators + 16x unroll, one sink store per scan → ~14 GB/s single-core,
 * immune to the O3 store-set serialization of commit d821212e9d). The only
 * difference is the gem5_set_streaming() call. !!! BUILD WITH -O3
 * -march=x86-64 -ftree-vectorize !!! (SSE2); -O1 stays scalar (~5 GB/s).
 *
 * Ordering matters for the streaming read-only contract: the init loop WRITES
 * arr first, THEN gem5_set_streaming marks the range, THEN the loop is
 * read-only — so no write occurs inside the streaming epoch.
 *
 * gem5_set_streaming(addr, size): marks the range STREAMING in the gem5 page
 * table → TLB propagates the flag → HNF/ProbeFilter bypass allocation for
 * these lines (M5OP_SET_STREAMING = 0x55). setstreaming() pre-allocates any
 * missing BSS pages, so it is safe before first access. */

static inline void gem5_set_streaming(void *addr, long size) {
    __asm__ volatile(".byte 0x0f, 0x04, 0x55, 0x00"
                     : : "D"((long)addr), "S"(size) : "rax");
}

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

    /* Mark streaming region AFTER init writes, BEFORE the read-only loop.
     * Gated on argv[2]=="stream" so one binary serves both the WB and the H2
     * arm: using two different binaries would confound the comparison with a
     * code difference. Same convention as h1bw_stream.c. */
    if (argc > 2 && strcmp(argv[2], "stream") == 0)
        gem5_set_streaming((void*)arr, N * (long)sizeof(long));

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
