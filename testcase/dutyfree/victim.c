#include <stdio.h>
#include <stdlib.h>

/* Pointer-chase victim.
 * argv[1] = size_kb  (default 1024 = 1MiB, max 8192 = 8MiB)
 * argv[2] = iters    (default 4*N, measurement pass only)
 * Uses Sattolo's algorithm — single-cycle permutation in-place, any N.
 * Static array avoids malloc/mmap so gem5 SE VMA tracking is stable.
 *
 * Execution phases:
 *   1. Sattolo shuffle  — build pointer chain
 *   2. Warmup pass      — N iters, traverse full chain once (warms L2 + PF)
 *   3. gem5_reset_stats — discard shuffle/warmup from stats
 *   4. Measurement pass — iters iterations (chase only, low demand)
 *   5. gem5_exit        — stop simulation immediately */

/* x86 gem5 pseudo-instructions: opcode 0F 04, function byte, 0x00 */
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

#define MAX_KB (256 * 1024)
static int arr[MAX_KB * 1024 / sizeof(int)];

int main(int argc, char *argv[])
{
    long size_kb = argc > 1 ? atol(argv[1]) : 1024;
    if (size_kb > MAX_KB) size_kb = MAX_KB;
    long N = size_kb * 1024L / (long)sizeof(int);
    long iters = argc > 2 ? atol(argv[2]) : 4 * N;

    /* Sattolo's algorithm: j = rand() % i (not i+1) guarantees single cycle. */
    for (long i = 0; i < N; i++) arr[i] = (int)i;
    srand(42);
    for (long i = N - 1; i > 0; i--) {
        long j = (long)rand() % i;
        int tmp = arr[i]; arr[i] = arr[j]; arr[j] = tmp;
    }

    /* Warmup: traverse full chain once to warm L2 + PF */
    long idx = 0, sum = 0;
    for (long i = 0; i < N; i++)
        idx = arr[idx];

    /* Discard shuffle + warmup from stats */
    gem5_reset_stats();

    /* Measurement: chase only */
    idx = 0; sum = 0;
    for (long i = 0; i < iters; i++) {
        idx = arr[idx];
        sum += idx;
    }

    printf("victim(%ldKiB iters=%ld): sum=%ld\n", size_kb, iters, sum);
    gem5_exit();
    return 0;
}
