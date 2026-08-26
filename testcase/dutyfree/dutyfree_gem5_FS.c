#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/syscall.h>

/* FS-mode sequential streaming aggressor — BW-max variant.
 *   argv[1] = size_mb (float, default 4.0)
 *   argv[2] = policy: "wb" (plain cacheable) | "h2" (mprotect(PROT_STREAMING))
 *
 * Same BW-max scan as aggressor.c / ../dirtax/aggressor.c (non-volatile
 * long, 16 accumulators + 16x unroll, one sink store per scan).
 * !!! BUILD WITH -O3 -march=x86-64 -ftree-vectorize !!! (SSE2; no AVX)
 *
 * FS differences vs the SE variants:
 *   - array is mmap'd and mbind(MPOL_BIND, node1) BEFORE first touch, so the
 *     guest kernel places it on the CXL NUMA node (SE used gem5-side pools).
 *   - H2 marking is mprotect(PROT_READ|PROT_STREAMING) — the Linux 6.8
 *     claude-draft2 kernel rewrites PTEs to PAT slot 6 and gem5's page walker
 *     decodes that into Request::STREAMING_BIT. The SE gem5_set_streaming
 *     m5op does not exist on this path.
 *   - a failed mprotect must never degrade silently into a WB run: exit(11),
 *     same convention as cxl_join_bench.gem5fs.
 *
 * Ordering (read-only epoch contract): init WRITES arr first, THEN the
 * region is published streaming, THEN the scan loop is read-only. */

#ifndef PROT_STREAMING
#define PROT_STREAMING 0x10   /* Linux 6.8 claude-draft2: PAT slot 6 */
#endif

#define MPOL_BIND 2
#define CXL_NODE 1
#define UNROLL 16

int main(int argc, char *argv[])
{
    double size_mb = argc > 1 ? atof(argv[1]) : 4.0;
    const char *policy = argc > 2 ? argv[2] : "wb";
    int h2 = strcmp(policy, "h2") == 0;
    if (!h2 && strcmp(policy, "wb") != 0) {
        fprintf(stderr, "dutyfree_gem5_FS: unknown policy '%s' (wb|h2)\n",
                policy);
        return 2;
    }

    long bytes = (long)(size_mb * 1024.0 * 1024.0);
    long N = bytes / (long)sizeof(long);
    long limit = N - (N % UNROLL);

    long *arr = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
                     MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (arr == MAP_FAILED) { perror("mmap"); return 2; }

    /* Bind to the CXL node BEFORE first touch (first-touch would go node0). */
    unsigned long mask = 1UL << CXL_NODE;
    if (syscall(SYS_mbind, arr, bytes, MPOL_BIND, &mask,
                sizeof(mask) * 8, 0) != 0) {
        fprintf(stderr, "dutyfree_gem5_FS: mbind(node%d) failed: %s\n",
                CXL_NODE, strerror(errno));
        return 2;
    }

    for (long i = 0; i < N; i++) arr[i] = i;   /* init + first-touch on CXL */

    /* Publish the read epoch AFTER the last write. Kernel side: PTE -> PAT
     * slot 6 + TLB shootdown + WBNOINVD IPI drain (gem5 currently no-ops the
     * WBNOINVD — see note 15). Loud fail so a stale kernel can't fake H2. */
    if (h2 && mprotect(arr, bytes, PROT_READ | PROT_STREAMING) != 0) {
        fprintf(stderr, "FATAL: mprotect(PROT_STREAMING) failed: %s\n",
                strerror(errno));
        exit(11);
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
        sink = s;
    }
}
