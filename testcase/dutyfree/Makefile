CC      = gcc
CFLAGS  = -O1 -static -march=x86-64
# BW-max aggressors need -O3 -ftree-vectorize (SSE2 paddq); -O1 stays scalar.
BWCFLAGS = -O3 -static -march=x86-64 -ftree-vectorize
TARGETS = victim aggressor dummy aggressor_bw aggressor_finite_bw

all: $(TARGETS)

victim: victim.c
	$(CC) $(CFLAGS) -o $@ $<

aggressor: aggressor.c
	$(CC) $(CFLAGS) -o $@ $<

dummy: dummy.c
	$(CC) $(CFLAGS) -o $@ $<

aggressor_bw: aggressor_bw.c
	$(CC) $(BWCFLAGS) -o $@ $<

aggressor_finite_bw: aggressor_finite_bw.c
	$(CC) $(BWCFLAGS) -o $@ $<

clean:
	rm -f $(TARGETS)

.PHONY: all clean
