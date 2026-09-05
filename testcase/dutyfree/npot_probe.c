#include <stdio.h>
#include <stdlib.h>

/* Reachable-LLC-capacity probe.
 *
 * A cyclic sequential sweep of a working set W through an LRU cache of
 * reachable capacity C is the sharpest available discriminator of C:
 *   W <= C  -> every line is still resident when the next pass reaches it,
 *              so after the first pass the LLC supplies everything and
 *              memory-side read traffic falls to zero;
 *   W >  C  -> the line evicted to make room is always the one the sweep
 *              will want next, so the hit rate is ~0 and memory-side read
 *              traffic is ~W per pass.
 * The transition is a step, not a slope, which is what makes a single cell
 * able to separate 5.00 MiB from 7.50 MiB of reachable LLC.
 *
 * argv[1] = ws_kb   working set, KiB (default 6144 = 6 MiB)
 * argv[2] = passes  measured sweeps (default 3)
 *
 * Phases: init touch -> gem5_reset_stats -> measured sweeps -> gem5_exit.
 * Static array, no malloc/mmap, so gem5 SE VMA tracking is stable (as victim.c).
 */

/* x86 gem5 pseudo-instructions: opcode 0F 04, function byte, 0x00 */
static inline void gem5_exit(void) {
    unsigned long m5_rax;
    __asm__ volatile(".byte 0x0f, 0x04, 0x21, 0x00"
                     : "=a"(m5_rax) : "D"(0ULL));
    (void)m5_rax;
}
static inline void gem5_reset_stats(void) {
    unsigned long m5_rax;
    __asm__ volatile(".byte 0x0f, 0x04, 0x40, 0x00"
                     : "=a"(m5_rax) : "D"(0ULL), "S"(0ULL));
    (void)m5_rax;
}

#define MAX_KB (32 * 1024)
#define LINE 64

/* No alignment attribute: gem5's ELF loader panics on the segment a large
 * .bss alignment produces ("Segment outside the bounds of the image data"),
 * and alignment is not needed here.  The HNF selects set bits [6 : 6+b-1], so
 * the set index has period 2^(6+b) bytes: 256 KiB at b=12, 512 KiB at b=13.
 * A 6 MiB region is a whole multiple of both (24x and 12x), so every reachable
 * set receives exactly the same number of lines from whatever 64 B-aligned
 * address the array happens to start at. */
static unsigned char buf[MAX_KB * 1024L];

int main(int argc, char *argv[])
{
    long ws_kb = argc > 1 ? atol(argv[1]) : 6144;
    long passes = argc > 2 ? atol(argv[2]) : 3;
    if (ws_kb > MAX_KB) ws_kb = MAX_KB;
    long n = ws_kb * 1024L;
    volatile unsigned long sink = 0;
    unsigned long sum = 0;

    /* Init: one write per line, so every page is mapped and every line has a
     * home before the measured region begins. */
    for (long i = 0; i < n; i += LINE) buf[i] = (unsigned char)(i >> 6);

    gem5_reset_stats();

    for (long p = 0; p < passes; p++)
        for (long i = 0; i < n; i += LINE) sum += buf[i];

    sink = sum;
    printf("npot_probe(ws=%ldKiB passes=%ld): lines=%ld sum=%lu\n",
           ws_kb, passes, n / LINE, (unsigned long)sink);
    gem5_exit();
    return 0;
}
