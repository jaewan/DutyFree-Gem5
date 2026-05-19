#include <stdio.h>
#include <stdlib.h>

/*
 * Cache-level latency benchmark.
 * Usage: latency_bench <N> <step> <iters> <mode:r|w> <flush_n>
 *
 * Phase 1: Build pointer chain sequentially → warms cache with N elements.
 * Phase 2: Flush with flush_n random-stride reads → evicts chain from L1/L2.
 * Phase 3: Chase chain for <iters> steps → measures hit latency at remaining level.
 *
 * TimingSimpleCPU is single-issue: ticks/iters == per-access latency in cycles.
 */
int main(int argc, char *argv[])
{
    int N       = atoi(argv[1]);
    int step    = atoi(argv[2]);
    int iters   = atoi(argv[3]);
    int do_write = (argv[4][0] == 'w');
    int flush_n = (argc > 5) ? atoi(argv[5]) : 0;

    int *arr = (int *)malloc(N * sizeof(int));
    if (!arr) { fprintf(stderr, "malloc fail N=%d\n", N); return 1; }

    /* Phase 1: build chain arr[i] -> arr[(i+step)%N] (step odd, gcd(step,N)=1) */
    for (int i = 0; i < N; i++) arr[i] = (i + step) % N;

    /* Phase 2: flush – touch a separate array to evict chain data from L1/L2 */
    if (flush_n > 0) {
        int *flush = (int *)malloc(flush_n * sizeof(int));
        if (flush) {
            int fstep = flush_n / 2 + 1;
            for (int i = 0; i < flush_n; i++) flush[i] = (i + fstep) % flush_n;
            volatile int fi = 0;
            for (int i = 0; i < flush_n; i++) fi = flush[fi];
            (void)fi;
            free(flush);
        }
    }

    /* Phase 3: pointer chase (this is what we measure via total ticks) */
    int idx = 0;
    long sum = 0;
    for (int i = 0; i < iters; i++) {
        idx = arr[idx];
        sum += idx;
        if (do_write) arr[idx] = (arr[idx] + 1) % N;
    }

    printf("N=%d step=%d iters=%d mode=%s flush=%d sum=%ld\n",
           N, step, iters, do_write ? "write" : "read", flush_n, sum);
    free(arr);
    return 0;
}
