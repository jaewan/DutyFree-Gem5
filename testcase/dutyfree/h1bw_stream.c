#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Single-core H1/MLP bandwidth-survival probe (tab:h1bw, ASPLOS27 Appendix).
 * argv[1] = size_mb (default 16.0)
 * argv[2] = "stream" to mark the region STREAMING via gem5_set_streaming
 *           before the read loop -- the +H2 arm. Omit for WB. The WC arm
 *           reuses this same (unmarked) binary with PF_OFF_CORES set on this
 *           core via the harness env, not an argv flag.
 *
 * Unlike aggressor.c (a co-runner with no stats boundary of its own), this
 * probe calls gem5_reset_stats() right after the init write pass, so the
 * bandwidth/LLC counters in stats.txt reflect ONLY the steady-state
 * read-only stream -- not the one-time read-for-ownership traffic of
 * initializing a size_mb-MiB static array. (Reconstructed 2026-08-13: the
 * original c3-session harness that produced tab:h1bw is gone; running
 * aggressor.c standalone without this reset conflates the init RFO burst
 * with the intended steady-state read bandwidth -- confirmed by a probe run
 * where LLC data-array writes came back 0 because the 5M-instruction budget
 * was consumed almost entirely by the init loop.)
 */

static inline void gem5_set_streaming(void *addr, long size) {
    __asm__ volatile(".byte 0x0f, 0x04, 0x55, 0x00"
                     : : "D"((long)addr), "S"(size) : "rax");
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
    if (size_mb > MAX_MB) size_mb = MAX_MB;
    long N = (long)(size_mb * 1024.0 * 1024.0) / (long)sizeof(long);
    long limit = N - (N % UNROLL);

    for (long i = 0; i < N; i++) arr[i] = i;   /* non-zero init + first-touch */

    if (argc > 2 && strcmp(argv[2], "stream") == 0)
        gem5_set_streaming((void *)arr, N * (long)sizeof(long));

    gem5_reset_stats();   /* discard init-write RFO traffic from stats */

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
