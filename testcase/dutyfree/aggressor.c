#include <stdio.h>
#include <stdlib.h>

/* Sequential streaming aggressor — DutyFree variant (PF bypass enabled).
 * argv[1] = size_mb  (float, default 4.0; e.g. 1.5 for 1.5 MiB)
 * Infinite loop — runs until gem5 simulation ends (victim calls m5_exit).
 * Sequential stride-1 read-only — bandwidth-bound, no dependency chain.
 * Static array avoids malloc/mmap so gem5 SE VMA tracking is stable.
 *
 * gem5_set_streaming(addr, size): marks address range as STREAMING in gem5
 * page table → TLB hit propagates STREAMING flag → ProbeFilter skips
 * enrollment for these lines (M5OP_SET_STREAMING = 0x55).
 * pseudo_inst::setstreaming() pre-allocates any missing BSS pages via
 * process->allocateMem(), so this call works before first access. */

/* x86 gem5 pseudo-instructions */
static inline void gem5_set_streaming(void *addr, long size) {
    __asm__ volatile(".byte 0x0f, 0x04, 0x55, 0x00"
                     : : "D"((long)addr), "S"(size) : "rax");
}

#define MAX_MB 512
static volatile int arr[MAX_MB * 1024 * 1024 / sizeof(int)];

int main(int argc, char *argv[])
{
    double size_mb = argc > 1 ? atof(argv[1]) : 4.0;
    if (size_mb > MAX_MB) size_mb = MAX_MB;
    long N = (long)(size_mb * 1024.0 * 1024.0) / (long)sizeof(int);

    /* Mark streaming region in gem5 page table before accessing */
    gem5_set_streaming((void*)arr, N * (long)sizeof(int));

    volatile long sum = 0;
    while(1) {
    for (long i = 0; i < N; i++)
        sum += arr[i];
    }
}
