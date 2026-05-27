/*
 * Multi-CPU Coherence Validation Tests
 * Covers: Invalidation, Sharing, Ping-Pong, O-state, False Sharing,
 *         Inter-CorePair coherence (tests 5-8, require --num-cpus >= 4)
 *
 * Usage: coherence_tests <test_id>
 *   0 = invalidation      (CPU0 write -> CPU1 read: stale data check)
 *   1 = sharing           (multi-CPU read same data: I->S->S)
 *   2 = pingpong          (M->I->M: alternating writers on same cacheline)
 *   3 = ostate            (M->O->S: MOESI O-state path)
 *   4 = false_sharing     (same cacheline, different words: perf vs no-sharing)
 *   5 = inter_cp_share    (CPU0 M -> CPU2(CP1) read: inter-CorePair transfer)
 *   6 = inter_cp_inv      (CPU0 write V1, CPU2 reads, CPU0 write V2: CP1 inv)
 *   7 = o_state_inter_cp  (CPU0 M->O, CPU2 S, CPU2 write: CPU0 O->I check)
 *   8 = multi_sharer_inv  (O + S across 2 CorePairs, writer invalidates all)
 *  10 = invalidation_2c   (2c: main writes, pthread reads)
 *  11 = sharing_2c        (2c: main writes, main+pthread both read)
 *  12 = pingpong_2c       (2c: main and pthread alternate writes)
 *  13 = ostate_2c         (2c: main M->O, pthread reads/writes, main reads back)
 *  14 = false_sharing_2c  (2c: main+pthread write same/diff cachelines)
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


#define PASS(name) printf("PASS  [%s]\n", name)
#define FAIL(name, ...) do { printf("FAIL  [%s] ", name); printf(__VA_ARGS__); printf("\n"); } while(0)
#define RESULT(name, ok, ...) do { if(ok) PASS(name); else FAIL(name, __VA_ARGS__); } while(0)

/* ── spin-wait helpers (no pthread_join / no atomic RMW) ─────────────────
 * pthread_join uses futex internally and can hang in gem5 SE+Ruby when
 * threads exit. Use per-thread volatile done flag + spin-wait instead.
 */
#define T4_DONE(id)   do { t4_done[(id)] = 1; return NULL; } while(0)
#define T4_WAIT(id)   do { while(!t4_done[(id)]) {} } while(0)
static volatile int t4_done[4] __attribute__((aligned(CL)));

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
static volatile int shr_flag __attribute__((aligned(CL)));
static int shr_results[2];

static void *shr_reader(void *arg) {
    int id = (int)(long)arg;
    while (!shr_flag) {}      /* spin until main sets flag */
    __sync_synchronize();
    int ok = 1;
    for (int i = 0; i < SHR_N; i++)
        if (shr_arr[i] != i * 3) { ok = 0; break; }
    shr_results[id] = ok;
    T4_DONE(id);
}
static void test_sharing(void) {
    memset((void*)t4_done, 0, sizeof(t4_done));
    shr_flag = 0;
    pthread_t t0, t1;
    pthread_create(&t0, NULL, shr_reader, (void*)0L);
    pthread_create(&t1, NULL, shr_reader, (void*)1L);
    for (int i = 0; i < SHR_N; i++) shr_arr[i] = i * 3;
    __sync_synchronize();
    shr_flag = 1;             /* release threads */
    T4_WAIT(0); T4_WAIT(1);
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
#define PP_ITERS 4
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

/* ── Test 5: inter_cp_share ───────────────────────────────
 * CPU0 (CP0) writes, CPU2 (CP1) reads → must see written value.
 * Exercises: M (CP0) → probe → S/O inter-CorePair transfer.
 * Catches: ProbeFilter isOnCPU=false → CP1 skipped → stale read.
 */
static volatile int ics_data __attribute__((aligned(CL)));
static volatile int ics_flag __attribute__((aligned(CL)));
static volatile int ics_result;

static void *ics_writer(void *arg) {         /* CPU0, CP0 */
    ics_data = 0xDEAD;
    __sync_synchronize();
    ics_flag = 1;
    T4_DONE(0);
}
static void *ics_reader(void *arg) {         /* CPU2, CP1 */
    while (ics_flag != 1) {}
    __sync_synchronize();
    ics_result = (ics_data == 0xDEAD);
    T4_DONE(2);
}
static void test_inter_cp_share(void) {
    memset((void*)t4_done, 0, sizeof(t4_done));
    ics_flag = 0; ics_data = 0; ics_result = 0;
    pthread_t t0, t2;
    pthread_create(&t0, NULL, ics_writer, NULL);
    pthread_create(&t2, NULL, ics_reader, NULL);
    T4_WAIT(0); T4_WAIT(2);
    RESULT("inter_cp_share", ics_result, "CP1 read stale: got 0x%x expected 0xDEAD", ics_data);
}

/* ── Test 6: inter_cp_inv ─────────────────────────────────
 * CPU0 (CP0) writes V1, CPU2 (CP1) reads (inter-CP sharing).
 * CPU0 writes V2 → must invalidate CP1's copy.
 * CPU2 reads again → must see V2, not stale V1.
 * Catches: ProbeFilter fails to invalidate CP1 on second write.
 */
static volatile int ici_data __attribute__((aligned(CL)));
static volatile int ici_flag __attribute__((aligned(CL)));
static volatile int ici_result;

static void *ici_cpu0(void *arg) {
    ici_data = 0x1111;
    __sync_synchronize();
    ici_flag = 1;                   /* signal CPU2 to read V1 */
    while (ici_flag != 2) {}        /* wait for CPU2 ack */
    ici_data = 0x2222;              /* second write: must invalidate CP1 */
    __sync_synchronize();
    ici_flag = 3;                   /* signal CPU2 to read V2 */
    T4_DONE(0);
}
static void *ici_cpu2(void *arg) {
    while (ici_flag != 1) {}
    __sync_synchronize();
    int v1 = ici_data;              /* read V1 (warms CP1's cache) */
    ici_flag = 2;
    while (ici_flag != 3) {}
    __sync_synchronize();
    int v2 = ici_data;              /* must be 0x2222, not stale 0x1111 */
    ici_result = (v1 == 0x1111) && (v2 == 0x2222);
    T4_DONE(2);
}
static void test_inter_cp_inv(void) {
    memset((void*)t4_done, 0, sizeof(t4_done));
    ici_flag = 0; ici_data = 0; ici_result = 0;
    pthread_t t0, t2;
    pthread_create(&t0, NULL, ici_cpu0, NULL);
    pthread_create(&t2, NULL, ici_cpu2, NULL);
    T4_WAIT(0); T4_WAIT(2);
    RESULT("inter_cp_inv", ici_result, "CP1 stale after re-write");
}

/* ── Test 7: o_state_inter_cp ─────────────────────────────
 * CPU0 (CP0): write 0x11 → M
 * CPU2 (CP1): read → CPU0 M→O, CPU2 →S
 * CPU2 (CP1): write 0x22 → CPU0 O→I (must be probed!), CPU2 →M
 * CPU0 (CP0): read → must see 0x22, not stale 0x11
 * Catches: ProbeFilter skips O-holder probe → CPU0 stays O with stale data.
 */
static volatile int ost_data __attribute__((aligned(CL)));
static volatile int ost_flag __attribute__((aligned(CL)));
static volatile int ost_result[2];

static void *ost_cpu0(void *arg) {
    ost_data = 0x11;
    __sync_synchronize();
    ost_flag = 1;                   /* signal CPU2: M ready */
    while (ost_flag != 2) {}       /* wait: CPU2 read, we are now O */
    ost_flag = 3;                   /* signal CPU2 to write */
    while (ost_flag != 4) {}       /* wait: CPU2 wrote, we should be I */
    __sync_synchronize();
    ost_result[0] = (ost_data == 0x22);  /* must see CPU2's write */
    T4_DONE(0);
}
static void *ost_cpu2(void *arg) {
    while (ost_flag != 1) {}
    __sync_synchronize();
    int v = ost_data;               /* read: CPU0 M→O, us →S */
    ost_result[1] = (v == 0x11);
    ost_flag = 2;
    while (ost_flag != 3) {}
    ost_data = 0x22;                /* write: CPU0 O→I, us →M */
    __sync_synchronize();
    ost_flag = 4;
    T4_DONE(2);
}
static void test_o_state_inter_cp(void) {
    memset((void*)t4_done, 0, sizeof(t4_done));
    ost_flag = 0; ost_data = 0;
    memset((void*)ost_result, 0, sizeof(ost_result));
    pthread_t t0, t2;
    pthread_create(&t0, NULL, ost_cpu0, NULL);
    pthread_create(&t2, NULL, ost_cpu2, NULL);
    T4_WAIT(0); T4_WAIT(2);
    RESULT("o_state_inter_cp_read",  ost_result[1], "CPU2 read stale from M holder");
    RESULT("o_state_inter_cp_inv",   ost_result[0], "CPU0 O-holder not invalidated");
}

/* ── Test 8: multi_sharer_inv ─────────────────────────────
 * pthread0 (CP0) writes 0x33 → M
 * pthread1 (CP1) reads → CP0 M→O, CP1 →S  (inter-CP)
 * pthread2 (CP1) writes 0x44 → CP0 O→I, CP1 S→I
 * pthread0 and pthread1 read back → must see 0x44
 * Key ProbeFilter test: O-holder (CP0) must be probed by CP1 writer.
 * main + 3 pthreads = 4 threads → fits in --num-cpus=4.
 */
static volatile int msi_data  __attribute__((aligned(CL)));
static volatile int msi_start __attribute__((aligned(CL)));  /* writer → reader */
static volatile int msi_r1    __attribute__((aligned(CL)));  /* reader read done */
static volatile int msi_go    __attribute__((aligned(CL)));  /* writer2 write done */
static volatile int msi_result[3];

static void *msi_cpu0(void *arg) {   /* CP0: initial writer, becomes O-holder */
    msi_data = 0x33;
    __sync_synchronize();
    msi_start = 1;
    while (!msi_go) {}
    __sync_synchronize();
    msi_result[0] = (msi_data == 0x44);   /* O-holder must see new value */
    T4_DONE(0);
}
static void *msi_cpu1(void *arg) {   /* CP1: inter-CP reader → S */
    while (!msi_start) {}
    __sync_synchronize();
    int v = msi_data;                     /* CP0 M→O, us →S */
    msi_result[1] = (v == 0x33);
    msi_r1 = 1;
    while (!msi_go) {}
    __sync_synchronize();
    msi_result[1] &= (msi_data == 0x44);  /* S-sharer must see new value */
    T4_DONE(1);
}
static void *msi_cpu2(void *arg) {   /* CP1: writer → invalidates O + S */
    while (!msi_r1) {}
    msi_data = 0x44;                      /* O→I (CP0) + S→I (CP1) */
    __sync_synchronize();
    msi_go = 1;
    T4_DONE(2);
}
static void test_multi_sharer_inv(void) {
    memset((void*)t4_done, 0, sizeof(t4_done));
    msi_data = 0; msi_start = 0; msi_r1 = 0; msi_go = 0;
    memset((void*)msi_result, 0, sizeof(msi_result));
    pthread_t t0, t1, t2;
    pthread_create(&t0, NULL, msi_cpu0, NULL);
    pthread_create(&t1, NULL, msi_cpu1, NULL);
    pthread_create(&t2, NULL, msi_cpu2, NULL);
    T4_WAIT(0); T4_WAIT(1); T4_WAIT(2);
    RESULT("multi_sharer_cp0_oholder", msi_result[0], "CP0 O-holder not invalidated");
    RESULT("multi_sharer_cp1_sharer",  msi_result[1], "CP1 S-sharer stale after write");
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

/* ── 2c variants (tests 10-14): main participates directly, main+1 pthread only ──
 * Designed for --num-cpus=2. No pthread_join; use T4_DONE/T4_WAIT.
 */

/* Test 10: invalidation_2c — main writes, pthread reads */
static volatile int i2_data __attribute__((aligned(CL)));
static volatile int i2_flag __attribute__((aligned(CL)));
static volatile int i2_result;
static void *i2_reader(void *arg) {
    while (!i2_flag) {}
    __sync_synchronize();
    i2_result = (i2_data == 0xA5);
    T4_DONE(0);
}
static void test_invalidation_2c(void) {
    memset((void*)t4_done, 0, sizeof(t4_done));
    i2_flag = 0; i2_data = 0; i2_result = 0;
    pthread_t t0;
    pthread_create(&t0, NULL, i2_reader, NULL);
    i2_data = 0xA5;
    __sync_synchronize();
    i2_flag = 1;
    T4_WAIT(0);
    RESULT("invalidation_2c", i2_result, "stale read");
}

/* Test 11: sharing_2c — main writes, pthread reads, main also reads */
static volatile int s2_data __attribute__((aligned(CL)));
static volatile int s2_flag __attribute__((aligned(CL)));
static volatile int s2_result;
static void *s2_reader(void *arg) {
    while (!s2_flag) {}
    __sync_synchronize();
    s2_result = (s2_data == 0x42);
    T4_DONE(0);
}
static void test_sharing_2c(void) {
    memset((void*)t4_done, 0, sizeof(t4_done));
    s2_flag = 0; s2_data = 0; s2_result = 0;
    pthread_t t0;
    pthread_create(&t0, NULL, s2_reader, NULL);
    s2_data = 0x42;
    __sync_synchronize();
    s2_flag = 1;
    int main_ok = (s2_data == 0x42);
    T4_WAIT(0);
    RESULT("sharing_2c_main",   main_ok,   "main stale read");
    RESULT("sharing_2c_thread", s2_result, "thread stale read");
}

/* Test 12: pingpong_2c — main and pthread alternate writes */
static volatile int pp2_data __attribute__((aligned(CL)));
static volatile int pp2_turn __attribute__((aligned(CL)));
static void *pp2_thread(void *arg) {
    for (int i = 0; i < PP_ITERS; i++) {
        while (pp2_turn != 1) {}
        pp2_data++;
        __sync_synchronize();
        pp2_turn = 0;
    }
    T4_DONE(0);
}
static void test_pingpong_2c(void) {
    memset((void*)t4_done, 0, sizeof(t4_done));
    pp2_data = 0; pp2_turn = 0;
    pthread_t t0;
    pthread_create(&t0, NULL, pp2_thread, NULL);
    for (int i = 0; i < PP_ITERS; i++) {
        while (pp2_turn != 0) {}
        pp2_data++;
        __sync_synchronize();
        pp2_turn = 1;
    }
    T4_WAIT(0);
    RESULT("pingpong_2c", pp2_data == 2*PP_ITERS,
           "expected %d got %d", 2*PP_ITERS, pp2_data);
}

/* Test 13: ostate_2c — main writes→M, pthread reads→O/S, pthread writes, main reads back */
static volatile int os2_data __attribute__((aligned(CL)));
static volatile int os2_flag __attribute__((aligned(CL)));
static volatile int os2_ok[2];
static void *os2_thread(void *arg) {
    while (os2_flag != 1) {}
    __sync_synchronize();
    int v = os2_data;            /* main M→O, us →S */
    os2_ok[1] = (v == 0xBB);
    os2_flag = 2;
    while (os2_flag != 3) {}
    os2_data = 0xCC;             /* write: main O→I */
    __sync_synchronize();
    os2_flag = 4;
    T4_DONE(0);
}
static void test_ostate_2c(void) {
    memset((void*)t4_done, 0, sizeof(t4_done));
    os2_flag = 0; os2_data = 0;
    memset((void*)os2_ok, 0, sizeof(os2_ok));
    pthread_t t0;
    pthread_create(&t0, NULL, os2_thread, NULL);
    os2_data = 0xBB;             /* main writes → M */
    __sync_synchronize();
    os2_flag = 1;
    while (os2_flag != 2) {}    /* wait: thread read, we are O */
    os2_ok[0] = (os2_data == 0xBB);  /* main reads as O-holder */
    os2_flag = 3;
    while (os2_flag != 4) {}    /* wait: thread wrote */
    __sync_synchronize();
    int inv_ok = (os2_data == 0xCC); /* main O→I: must see thread's write */
    T4_WAIT(0);
    RESULT("ostate_2c_thread_read", os2_ok[1], "thread stale from M-holder");
    RESULT("ostate_2c_main_oholder", os2_ok[0], "main O-read wrong");
    RESULT("ostate_2c_main_inv",     inv_ok,    "main O-holder not invalidated");
}

/* Test 14: false_sharing_2c — main and pthread write to same/diff cachelines */
static void *fs2_shared_w(void *arg) {
    for (int i = 0; i < FS_ITERS; i++) fs_shared[1] = i;
    T4_DONE(0);
}
static void *fs2_private_w(void *arg) {
    for (int i = 0; i < FS_ITERS; i++) fs_private[1][0] = i;
    T4_DONE(0);
}
static void test_false_sharing_2c(void) {
    pthread_t t0;
    memset((void*)t4_done, 0, sizeof(t4_done));
    pthread_create(&t0, NULL, fs2_shared_w, NULL);
    for (int i = 0; i < FS_ITERS; i++) fs_shared[0] = i;
    T4_WAIT(0);
    int s0 = fs_shared[0], s1 = fs_shared[1];
    memset((void*)t4_done, 0, sizeof(t4_done));
    pthread_create(&t0, NULL, fs2_private_w, NULL);
    for (int i = 0; i < FS_ITERS; i++) fs_private[0][0] = i;
    T4_WAIT(0);
    printf("INFO  [false_sharing_2c] shared=[%d,%d] private=[%d,%d]\n",
           s0, s1, fs_private[0][0], fs_private[1][0]);
}

/* ── main ─────────────────────────────────────────────────── */
int main(int argc, char *argv[])
{
    int test = (argc > 1) ? atoi(argv[1]) : -1;
    printf("=== coherence_tests (test=%d) ===\n", test);
    switch (test) {
        case 0:  test_invalidation();       break;
        case 1:  test_sharing();            break;
        case 2:  test_pingpong();           break;
        case 3:  test_ostate();             break;
        case 4:  test_false_sharing();      break;
        case 5:  test_inter_cp_share();     break;
        case 6:  test_inter_cp_inv();       break;
        case 7:  test_o_state_inter_cp();   break;
        case 8:  test_multi_sharer_inv();   break;
        case 10: test_invalidation_2c();    break;
        case 11: test_sharing_2c();         break;
        case 12: test_pingpong_2c();        break;
        case 13: test_ostate_2c();          break;
        case 14: test_false_sharing_2c();   break;
        default:
            /* run all */
            test_invalidation();
            test_sharing();
            test_pingpong();
            test_ostate();
            test_false_sharing();
            test_inter_cp_share();
            test_inter_cp_inv();
            test_o_state_inter_cp();
            test_multi_sharer_inv();
    }
    printf("done\n");
    return 0;
}
