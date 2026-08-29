#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* FUSED tenant — streams a large immutable array AND keeps a hot table with
 * real reuse. DutyFree (STREAMING). This is the workload the head-to-head
 * needs and aggressor.c cannot provide.
 *
 *   argv[1] = stream size MB (float, default 16.0)
 *   argv[2] = hot-table size MB (float, default 3.0)
 *   argv[3] = "stream" to declare ONLY the stream region
 *
 * Why this exists. aggressor.c is a PURE stream: it has no reuse, so confining
 * it to a few LLC ways costs it nothing, and way partitioning comes out nearly
 * free (measured 0.55%, H2H_PARTITION_VS_H2_OUTCOME_2026-08-29.md). That makes
 * a pure stream unable to discriminate between a way mask and a page-scoped
 * label -- both protect the neighbour, neither charges the tenant.
 *
 * A real streaming tenant is not pure: a scan probes a hash table, a decoder
 * keeps reference frames, a loader keeps weights. The reuse structure is
 * exactly what a way mask cannot spare, because a mask is indexed by AGENT and
 * the stream and the table belong to the same agent. A page-scoped label is
 * indexed by ADDRESS and can separate them. That difference is the paper's
 * thesis and it is invisible to a pure stream.
 *
 * Sizing for the 5 MiB / 20-way HNF with a 2 MiB private L2:
 *   - table 3 MB > 2 MiB L2, so ~1 MB of it must live in the LLC to stay hot;
 *   - victim's chase is 2650 KiB, so table spill + victim ~= 3.6 MB < 5 MiB,
 *     i.e. both fit when the stream stops allocating;
 *   - under a 4/20 mask the tenant's whole LLC share is 1 MiB and the stream
 *     shares it, so the table's spill is evicted continuously.
 *
 * Ordering, as in aggressor.c: init writes first, THEN the declaration, THEN a
 * read-only epoch -- no write inside the streaming epoch (contract I1). The
 * table is written during init and only READ afterwards, but is deliberately
 * NEVER declared: it is the tenant's own resident state.
 *
 * !!! BUILD WITH -O3 -march=x86-64 -ftree-vectorize !!! */

static inline void gem5_set_streaming(void *addr, long size) {
    __asm__ volatile(".byte 0x0f, 0x04, 0x55, 0x00"
                     : : "D"((long)addr), "S"(size) : "rax");
}

#define MAX_MB   512
#define MAX_TBL   64
#define UNROLL    16
static long arr[(long)MAX_MB  * 1024 * 1024 / sizeof(long)];
static long tbl[(long)MAX_TBL * 1024 * 1024 / sizeof(long)];

int main(int argc, char *argv[])
{
    double size_mb  = argc > 1 ? atof(argv[1]) : 16.0;
    double table_mb = argc > 2 ? atof(argv[2]) : 3.0;
    if (size_mb  > MAX_MB)  size_mb  = MAX_MB;
    if (table_mb > MAX_TBL) table_mb = MAX_TBL;

    long N = (long)(size_mb  * 1024.0 * 1024.0) / (long)sizeof(long);
    long T = (long)(table_mb * 1024.0 * 1024.0) / (long)sizeof(long);
    /* power-of-two element count so the probe index is a mask, not a modulo */
    long Tp = 1; while (Tp * 2 <= T) Tp *= 2;
    long limit = N - (N % UNROLL);

    for (long i = 0; i < N;  i++) arr[i] = i;        /* first-touch + non-zero */
    for (long i = 0; i < Tp; i++) tbl[i] = i * 3;    /* the tenant's own state */

    /* Declare ONLY the stream. The table is never declared -- that asymmetry is
     * the entire experiment. argv[3] gates it so one binary serves every arm
     * and no comparison is confounded by a code difference. */
    if (argc > 3 && strcmp(argv[3], "stream") == 0)
        gem5_set_streaming((void*)arr, N * (long)sizeof(long));

    static volatile unsigned long sink;
    unsigned long a[UNROLL];
    unsigned long h = 0;
    for (int k = 0; k < UNROLL; k++) a[k] = 0;
    while (1) {
        for (long i = 0; i < limit; i += UNROLL) {
            for (int k = 0; k < UNROLL; k++) a[k] += (unsigned long)arr[i + k];
            /* One table probe per 128 B of stream: enough traffic to make the
             * table's residency matter, not so much that the tenant stops
             * being a streamer. Multiply-scramble so the index is spread over
             * the whole table rather than walking it linearly. */
            unsigned long idx = ((unsigned long)arr[i] * 2654435761UL)
                                & (unsigned long)(Tp - 1);
            h += (unsigned long)tbl[idx];
        }
        for (long i = limit; i < N; i++) a[0] += (unsigned long)arr[i];
        unsigned long s = h;
        for (int k = 0; k < UNROLL; k++) s += a[k];
        sink = s;
    }
}
