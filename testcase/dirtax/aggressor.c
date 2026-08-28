#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

/* argv[2] = "h2" publishes the stream as a Streaming read epoch via
 * mprotect(PROT_READ|PROT_STREAMING) before the read loop starts. FS mode only:
 * SE mode has no page tables, so there the tag is applied with the
 * setstreaming pseudo-inst from the harness instead.
 *
 * Only whole pages fully inside arr[0..N) are tagged, and only after the init
 * loop's last write - the epoch is read-only, so a later store would fault. */
#ifndef PROT_STREAMING
#define PROT_STREAMING 0x10 /* Linux 6.8 claude-draft2: PAT slot 6 */
#endif

/* Sequential streaming aggressor — bandwidth-maximizing (the default aggressor).
 * argv[1] = size_mb  (float, default 4.0)
 * Infinite loop — runs until gem5 simulation ends (victim calls m5_exit).
 *
 * Why this exists: aggressor_lowBW.c (volatile int + single accumulator) is
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

    if (argc > 2 && strcmp(argv[2], "h2") == 0) {
        long pg = sysconf(_SC_PAGESIZE);
        uintptr_t lo = ((uintptr_t)arr + pg - 1) & ~(uintptr_t)(pg - 1);
        uintptr_t hi = ((uintptr_t)arr + (uintptr_t)N * sizeof(long))
                       & ~(uintptr_t)(pg - 1);
        if (hi <= lo) {
            fprintf(stderr, "FATAL: stream range too small to tag\n");
            return 3;
        }
        if (mprotect((void *)lo, (size_t)(hi - lo),
                     PROT_READ | PROT_STREAMING) != 0) {
            /* Never fall through to an untagged run: it would be recorded as
             * an H2 result while the hardware saw plain WB. */
            fprintf(stderr, "FATAL: mprotect(PROT_STREAMING) [%p,%p): %s\n",
                    (void *)lo, (void *)hi, strerror(errno));
            return 11;
        }
        printf("aggressor: streaming_tagged [%p,%p) %.1f MiB\n",
               (void *)lo, (void *)hi, (double)(hi - lo) / (1024.0 * 1024.0));
        fflush(stdout);
    }

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
