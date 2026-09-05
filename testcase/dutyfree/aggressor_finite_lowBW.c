#include <stdio.h>
#include <stdlib.h>

/* Sequential streaming aggressor — finite loop version.
 * argv[1] = size_mb  (float, default 4.0)
 * argv[2] = passes   (int,   default 10)
 * Calls gem5_set_streaming() before accessing array → LLC bypass. */

static inline void gem5_set_streaming(void *addr, long size) {
    unsigned long m5_rax;
    __asm__ volatile(".byte 0x0f, 0x04, 0x55, 0x00"
                     : "=a"(m5_rax) : "D"((long)addr), "S"(size));
    (void)m5_rax;
}

#define MAX_MB 512
static volatile int arr[MAX_MB * 1024 * 1024 / sizeof(int)];

int main(int argc, char *argv[])
{
    double size_mb = argc > 1 ? atof(argv[1]) : 4.0;
    int    passes  = argc > 2 ? atoi(argv[2]) : 10;
    if (size_mb > MAX_MB) size_mb = MAX_MB;
    long N = (long)(size_mb * 1024.0 * 1024.0) / (long)sizeof(int);

    printf("aggressor_finite(%.1fMB x %d): calling gem5_set_streaming...\n",
           size_mb, passes);
    gem5_set_streaming((void*)arr, N * (long)sizeof(int));
    printf("aggressor_finite: gem5_set_streaming done, starting reads\n");

    volatile long sum = 0;
    for (int p = 0; p < passes; p++)
        for (long i = 0; i < N; i++)
            sum += arr[i];

    printf("aggressor_finite(%.1fMB x %d): sum=%ld\n", size_mb, passes, sum);
    return 0;
}
