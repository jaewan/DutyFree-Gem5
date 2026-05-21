/*
 * shared_bench.c - multi-thread shared memory read benchmark
 * All threads chase the SAME pointer array → multiple CorePairs hold the same lines.
 * Generates cross-CorePair sharing probes (E->S / O->S path).
 *
 * Usage: shared_bench <N> <step> <iters> <nthreads>
 *   N        : array size (int elements)
 *   step     : pointer-chase stride (must be coprime to N)
 *   iters    : pointer-chase iterations per thread
 *   nthreads : number of threads (should equal --num-cpus)
 *
 * Compile: gcc -O1 -static -march=x86-64 -pthread -o shared_bench shared_bench.c
 *
 * NOTE: read-only access avoids concurrent write races that cause
 *       Ruby functional read failures in gem5 SE mode.
 */

#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>

#define MAX_THREADS  8

static int *arr;

static int N_global;
static int iters_global;

static pthread_t threads[MAX_THREADS];

/* pthread_join uses futex which causes Ruby functional read failures in gem5 SE mode.
 * Use per-thread volatile flags + spin-wait instead. */
static volatile int thread_done[MAX_THREADS];

static void *worker(void *arg)
{
    int id    = (int)(long)arg;
    int N     = N_global;
    int iters = iters_global;
    int idx   = id % N;
    long sum  = 0;

    for (int i = 0; i < iters; i++) {
        idx  = arr[idx];    /* read-only: generates E->S probes when CorePairs share */
        sum += idx;
    }

    printf("thread %d done sum=%ld\n", id, sum);
    thread_done[id] = 1;
    return NULL;
}

int main(int argc, char *argv[])
{
    if (argc < 5) {
        fprintf(stderr, "Usage: shared_bench <N> <step> <iters> <nthreads>\n");
        return 1;
    }

    int N        = atoi(argv[1]);
    int step     = atoi(argv[2]);
    int iters    = atoi(argv[3]);
    int nthreads = atoi(argv[4]);

    arr = (int *)malloc(N * sizeof(int));
    if (!arr) { fprintf(stderr, "malloc failed\n"); return 1; }

    N_global     = N;
    iters_global = iters;

    for (int i = 0; i < N; i++) arr[i] = (i + step) % N;
    for (int i = 0; i < nthreads; i++) thread_done[i] = 0;

    /* thread 0 = main itself; create nthreads-1 additional pthreads.
     * total live threads == nthreads == --num-cpus, so no CPU is wasted on a pure spin-wait. */
    for (int i = 1; i < nthreads; i++)
        pthread_create(&threads[i], NULL, worker, (void *)(long)i);

    worker((void *)(long)0);

    for (int i = 1; i < nthreads; i++)
        while (!thread_done[i]) { /* spin */ }

    free(arr);
    return 0;
}
