#include <stdio.h>
#include <stdlib.h>

/* Sequential streaming aggressor.
 * argv[1] = size_mb  (float, default 4.0; e.g. 1.5 for 1.5 MiB)
 * Infinite loop — runs until gem5 simulation ends (victim calls m5_exit).
 * Sequential stride-1 read-only — bandwidth-bound, no dependency chain.
 * Static array avoids malloc/mmap so gem5 SE VMA tracking is stable. */

#define MAX_MB 512
static volatile int arr[MAX_MB * 1024 * 1024 / sizeof(int)];

int main(int argc, char *argv[])
{
    double size_mb = argc > 1 ? atof(argv[1]) : 4.0;
    if (size_mb > MAX_MB) size_mb = MAX_MB;
    long N = (long)(size_mb * 1024.0 * 1024.0) / (long)sizeof(int);

    volatile long sum = 0;
    while (1)
        for (long i = 0; i < N; i++)
            sum += arr[i];
}
