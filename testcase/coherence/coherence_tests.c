/*
 * Multi-CPU Coherence Validation Tests
 * Covers: Invalidation, Sharing, Ping-Pong, O-state, False Sharing
 *
 * Usage: coherence_tests <test_id>
 *   0 = invalidation   (CPU0 write -> CPU1 read: stale data check)
 *   1 = sharing        (multi-CPU read same data: I->S->S)
 *   2 = pingpong       (M->I->M: alternating writers on same cacheline)
 *   3 = ostate         (M->O->S: MOESI O-state path)
 *   4 = false_sharing  (same cacheline, different words: perf vs no-sharing)
 *
 * Compile: gcc -O1 -static -march=x86-64 -pthread -o coherence_tests coherence_tests.c
 * Note: -O1 not -O2 to prevent volatile loads being optimized away.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

/* ── helpers ─────────────────────────────────────────────── */

/* Cache-line-aligned padding to avoid false sharing in control vars */
#define CL 64

/* Spin barrier: all N threads must arrive before any proceeds */
typedef struct {
    volatile int count  __attribute__((aligned(CL)));
    volatile int round  __attribute__((aligned(CL)));
    int n;
} SpinBarrier;

static void sb_init(SpinBarrier *b, int n) { b->count=0; b->round=0; b->n=n; }

static void sb_wait(SpinBarrier *b) {
    int r = b->round;
    if (__sync_add_and_fetch(&b->count, 1) == b->n) {
        b->count = 0;
        __sync_fetch_and_add(&b->round, 1);   /* release others */
    } else {
        while (b->round == r) { /* spin */ }  /* wait for release */
    }
}

#define PASS(name) printf("PASS  [%s]\n", name)
#define FAIL(name, ...) do { printf("FAIL  [%s] ", name); printf(__VA_ARGS__); printf("\n"); } while(0)
#define RESULT(name, ok, ...) do { if(ok) PASS(name); else FAIL(name, __VA_ARGS__); } while(0)

/* ── Test 0: Invalidation ─────────────────────────────────
 * CPU0 writes array, sets flag.
 * CPU1 spins on flag, then reads array.
 * CPU1 must see CPU0's values → no stale data.
 * Exercises: I->M (CPU0), M->I (probe from CPU1 fetch), I->S (CPU1)
 * In MOESI: M->O->S (CPU0 stays O, CPU1 gets S)
 */
#define INV_N 1024
static int  inv_arr[INV_N];
static volatile int inv_flag __attribute__((aligned(CL)));

static void *inv_writer(void *arg) {
    for (int i = 0; i < INV_N; i++) inv_arr[i] = 0xA5 + i;
    __sync_synchronize();   /* store-store fence */
    inv_flag = 1;
    return NULL;
}
static void *inv_reader(void *arg) {
    while (!inv_flag) { }   /* spin until writer done */
    __sync_synchronize();   /* load-load fence */
    int ok = 1;
    for (int i = 0; i < INV_N; i++)
        if (inv_arr[i] != 0xA5 + i) { ok = 0; break; }
    RESULT("invalidation", ok, "arr[%d]=%d expected %d",
           0, inv_arr[0], 0xA5);
    return NULL;
}
static void test_invalidation(void) {
    inv_flag = 0;
    pthread_t t0, t1;
    pthread_create(&t0, NULL, inv_writer, NULL);
    pthread_create(&t1, NULL, inv_reader, NULL);
    pthread_join(t0, NULL);
    pthread_join(t1, NULL);
}

/* ── Test 1: Shared Read ──────────────────────────────────
 * Main writes array (->M), two threads read it (->S/O).
 * Both threads must see the written values.
 * Exercises: M->S/O (probe), S->S (second reader)
 */
#define SHR_N 512
static int shr_arr[SHR_N];
static SpinBarrier shr_bar;
static int shr_results[2];

static void *shr_reader(void *arg) {
    int id = (int)(long)arg;
    sb_wait(&shr_bar);   /* wait for main to finish writing */
    int ok = 1;
    for (int i = 0; i < SHR_N; i++)
        if (shr_arr[i] != i * 3) { ok = 0; break; }
    shr_results[id] = ok;
    return NULL;
}
static void test_sharing(void) {
    sb_init(&shr_bar, 3);   /* main + 2 threads */
    pthread_t t0, t1;
    pthread_create(&t0, NULL, shr_reader, (void*)0L);
    pthread_create(&t1, NULL, shr_reader, (void*)1L);
    for (int i = 0; i < SHR_N; i++) shr_arr[i] = i * 3;   /* write while threads wait */
    __sync_synchronize();
    sb_wait(&shr_bar);   /* release threads */
    pthread_join(t0, NULL);
    pthread_join(t1, NULL);
    RESULT("sharing_t0", shr_results[0], "stale read");
    RESULT("sharing_t1", shr_results[1], "stale read");
}

/* ── Test 2: Ping-Pong ────────────────────────────────────
 * Two threads alternately write to THE SAME int.
 * Each write causes M->I on the other side (probe invalidation).
 * Correctness: each writer increments the value; final == 2*ITERS.
 * Note: no atomic here → exercises raw coherence ordering, not RMW.
 *       Race-free because turns are gated by a flag.
 */
#define PP_ITERS 256
static volatile int pp_data  __attribute__((aligned(CL)));
static volatile int pp_turn  __attribute__((aligned(CL)));  /* 0 = t0's turn */

static void *pp_thread(void *arg) {
    int id = (int)(long)arg;
    for (int i = 0; i < PP_ITERS; i++) {
        while (pp_turn != id) { }         /* wait for my turn */
        pp_data++;
        __sync_synchronize();
        pp_turn = 1 - id;                 /* pass turn */
    }
    return NULL;
}
static void test_pingpong(void) {
    pp_data = 0; pp_turn = 0;
    pthread_t t0, t1;
    pthread_create(&t0, NULL, pp_thread, (void*)0L);
    pthread_create(&t1, NULL, pp_thread, (void*)1L);
    pthread_join(t0, NULL);
    pthread_join(t1, NULL);
    RESULT("pingpong", pp_data == 2*PP_ITERS,
           "expected %d got %d", 2*PP_ITERS, pp_data);
}

/* ── Test 3: O-state (MOESI-specific) ────────────────────
 * Thread 0 writes large array (-> M, then O after Thread 1 reads).
 * Thread 1 reads while Thread 0 still "owns" dirty data.
 * Thread 2 then writes (invalidating O->M).
 * All threads verify final value.
 * In MESI: M->S path (write-back to memory). In MOESI: M->O->S (no WB).
 */
#define OS_N 256
static int os_arr[OS_N];
static SpinBarrier os_bar;
static volatile int os_flag __attribute__((aligned(CL)));
static int os_ok[3];

static void *os_t0(void *arg) {
    for (int i = 0; i < OS_N; i++) os_arr[i] = 0xBB;   /* M state */
    __sync_synchronize();
    os_flag = 1;                         /* signal T1 to read */
    while (os_flag != 2) { }            /* wait for T1 done */
    os_ok[0] = 1;
    for (int i = 0; i < OS_N; i++)      /* T0 can still read (O state in MOESI) */
        if (os_arr[i] != 0xBB) { os_ok[0] = 0; break; }
    os_flag = 3;                         /* signal T2 to write */
    return NULL;
}
static void *os_t1(void *arg) {
    while (os_flag != 1) { }            /* wait for T0 write */
    __sync_synchronize();
    os_ok[1] = 1;
    for (int i = 0; i < OS_N; i++)
        if (os_arr[i] != 0xBB) { os_ok[1] = 0; break; }
    os_flag = 2;                         /* signal T0 */
    while (os_flag != 4) { }            /* wait for T2 done */
    os_ok[1] &= (os_arr[0] == 0xCC);   /* T1 must see T2's new value */
    return NULL;
}
static void *os_t2(void *arg) {
    while (os_flag != 3) { }            /* wait for T0 signal */
    for (int i = 0; i < OS_N; i++) os_arr[i] = 0xCC;  /* invalidate O/S -> M */
    __sync_synchronize();
    os_flag = 4;
    return NULL;
}
static void test_ostate(void) {
    os_flag = 0; memset(os_ok, 0, sizeof(os_ok));
    pthread_t t0, t1, t2;
    pthread_create(&t0, NULL, os_t0, NULL);
    pthread_create(&t1, NULL, os_t1, NULL);
    pthread_create(&t2, NULL, os_t2, NULL);
    pthread_join(t0, NULL);
    pthread_join(t1, NULL);
    pthread_join(t2, NULL);
    RESULT("ostate_t0_read", os_ok[0], "T0 stale after T1 shared read");
    RESULT("ostate_t1_read", os_ok[1], "T1 stale after T2 write");
}

/* ── Test 4: False Sharing ────────────────────────────────
 * Two threads write to DIFFERENT words in the SAME cacheline.
 * This creates unnecessary M->I->M ping-pong even though no actual
 * sharing of data occurs.
 * Compare performance vs. writing to separate cachelines (no false sharing).
 */
#define FS_ITERS 512
static volatile int fs_shared[2];   /* [0] and [1] in same cacheline */
static volatile int fs_private[2][16]; /* [0][0] and [1][0] in diff cachelines */

static void *fs_shared_writer(void *arg) {
    int id = (int)(long)arg;
    for (int i = 0; i < FS_ITERS; i++) fs_shared[id] = i;
    return NULL;
}
static void *fs_private_writer(void *arg) {
    int id = (int)(long)arg;
    for (int i = 0; i < FS_ITERS; i++) fs_private[id][0] = i;
    return NULL;
}
static void test_false_sharing(void) {
    pthread_t t0, t1;
    /* shared cacheline (false sharing) */
    pthread_create(&t0, NULL, fs_shared_writer, (void*)0L);
    pthread_create(&t1, NULL, fs_shared_writer, (void*)1L);
    pthread_join(t0, NULL);
    pthread_join(t1, NULL);
    int s0 = fs_shared[0], s1 = fs_shared[1];
    /* private cachelines (no false sharing) */
    pthread_create(&t0, NULL, fs_private_writer, (void*)0L);
    pthread_create(&t1, NULL, fs_private_writer, (void*)1L);
    pthread_join(t0, NULL);
    pthread_join(t1, NULL);
    /* Both should complete; report final values */
    printf("INFO  [false_sharing] shared=[%d,%d] private=[%d,%d] "
           "(compare ticks: shared > private expected)\n",
           s0, s1, fs_private[0][0], fs_private[1][0]);
}

/* ── main ─────────────────────────────────────────────────── */
int main(int argc, char *argv[])
{
    int test = (argc > 1) ? atoi(argv[1]) : -1;
    printf("=== coherence_tests (test=%d) ===\n", test);
    switch (test) {
        case 0: test_invalidation();  break;
        case 1: test_sharing();       break;
        case 2: test_pingpong();      break;
        case 3: test_ostate();        break;
        case 4: test_false_sharing(); break;
        default:
            /* run all */
            test_invalidation();
            test_sharing();
            test_pingpong();
            test_ostate();
            test_false_sharing();
    }
    printf("done\n");
    return 0;
}
