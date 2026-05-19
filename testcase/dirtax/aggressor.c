#include <stdio.h>
#include <stdlib.h>

/*
 * Sequential streaming aggressor — matches paper conditions (minus CXL).
 *
 * Paper conditions reflected:
 *   - Sequential stride-1 access (prefetcher-friendly, matches "sequential 64-byte reads")
 *   - Read-only (no writes): WORM/immutable stream scenario from §2
 *   - No dependency chain: bandwidth-bound, not latency-bound
 *
 * Not reflected (gem5 SE mode limitation):
 *   - CXL device memory: using local malloc instead
 *
 * Array (1MB) > L2 (512KB) → every pass causes L2 evictions → directory enrollment.
 * Sequential pattern lets the hardware prefetcher (if present) pipeline requests.
 */
#define N      262144   /* 1MB / 4B */
#define PASSES 50       /* ~2× victim baseline duration */

int main(void)
{
    int *arr = (int *)malloc(N * sizeof(int));
    if (!arr) { fprintf(stderr, "malloc fail\n"); return 1; }

    for (int i = 0; i < N; i++) arr[i] = i;

    long sum = 0;
    for (int p = 0; p < PASSES; p++)
        for (int i = 0; i < N; i++)
            sum += arr[i];   /* sequential read-only, no dependency chain */

    printf("aggressor: sum=%ld\n", sum);
    free(arr);
    return 0;
}
