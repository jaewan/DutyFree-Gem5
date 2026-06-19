#include <stdio.h>
#include <stdlib.h>

/* Sequential aggressor — finite loop version (for standalone prefetch test).
 * argv[1] = size_mb  (float, default 4.0)
 * argv[2] = passes   (int,   default 10)
 * Sequential stride-1 read-only. Static array for VMA stability. */

#define MAX_MB 16
static volatile int arr[MAX_MB * 1024 * 1024 / sizeof(int)];

int main(int argc, char *argv[])
{
    double size_mb = argc > 1 ? atof(argv[1]) : 4.0;
    int    passes  = argc > 2 ? atoi(argv[2]) : 10;
    if (size_mb > MAX_MB) size_mb = MAX_MB;
    long N = (long)(size_mb * 1024.0 * 1024.0) / (long)sizeof(int);

    volatile long sum = 0;
    for (int p = 0; p < passes; p++)
        for (long i = 0; i < N; i++)
            sum += arr[i];

    printf("aggressor_finite(%.1fMB x %d): sum=%ld\n", size_mb, passes, sum);
    return 0;
}
