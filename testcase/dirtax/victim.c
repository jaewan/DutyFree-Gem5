#include <stdio.h>
#include <stdlib.h>

/* Pointer-chase victim using LCG traversal over 1MB array.
   LCG with a=65537, c=1, m=N gives full period (all N elements visited).
   Array (1MB) > L2 (512KB) → guaranteed L2 miss; fits in L3 → L3 hit. */
#define N      262144   /* 1MB / 4B = 262144 entries */
#define LCG_A  65537    /* a ≡ 1 (mod 4), full period for power-of-2 N */
#define LCG_C  1
#define ITERS  131072   /* 32× increase: chase dominates over chain-build overhead */

int main(void)
{
    int *arr = (int *)malloc(N * sizeof(int));
    if (!arr) { fprintf(stderr, "malloc failed\n"); return 1; }

    /* Build LCG permutation as pointer chain */
    unsigned idx = 0;
    for (int i = 0; i < N; i++) {
        unsigned next = (idx * LCG_A + LCG_C) & (N - 1);
        arr[idx] = (int)next;
        idx = next;
    }

    /* Chase the chain */
    idx = 0;
    long sum = 0;
    for (int i = 0; i < ITERS; i++) {
        idx = (unsigned)arr[idx];
        sum += idx;
    }

    printf("victim: sum=%ld idx=%u\n", sum, idx);
    free(arr);
    return 0;
}
