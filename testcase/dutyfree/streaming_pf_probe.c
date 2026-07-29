#include <stdio.h>
#include <stdlib.h>

/* STREAMING prefetch-leak probe.
 *
 * Goal: create many lines that are PREFETCHED but never DEMAND-touched, so
 * they reach L2 with isStreaming=false (the prefetch path drops the flag) and,
 * when evicted via WriteEvictFull, fill the LLC instead of bypassing it.
 *
 * Mechanism: stride by 2 cache lines (128B) so demand touches only EVEN lines.
 *   - StridePrefetcher learns the 128B stride -> prefetches future EVEN lines
 *     (those get demand-touched later -> flag written -> not our subject).
 *   - TaggedPrefetcher (adjacent line) fetches X+1 -> ODD lines, which are
 *     NEVER demand-touched -> pure prefetch lines -> the leak subject.
 *
 * argv[1] = passes (int, default 2)
 */

static inline void gem5_set_streaming(void *addr, long size) {
    __asm__ volatile(".byte 0x0f, 0x04, 0x55, 0x00"
                     : : "D"((long)addr), "S"(size) : "rax");
}

#define MB   32
#define LINE 64
static volatile unsigned char arr[MB * 1024 * 1024];

int main(int argc, char *argv[])
{
    int passes = argc > 1 ? atoi(argv[1]) : 2;
    long N = (long)sizeof(arr);

    gem5_set_streaming((void *)arr, N);
    printf("streaming_pf_probe: %dMB, stride=2 lines, passes=%d\n", MB, passes);

    volatile unsigned long s = 0;
    for (int p = 0; p < passes; p++)
        for (long i = 0; i < N; i += 2 * LINE)   /* even lines only */
            s += arr[i];

    printf("streaming_pf_probe: sum=%lu\n", s);
    return 0;
}
