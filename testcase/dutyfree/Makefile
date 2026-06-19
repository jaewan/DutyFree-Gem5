CC      = gcc
CFLAGS  = -O1 -static -march=x86-64
# BW-max aggressors (the default aggressor/aggressor_finite) need -O3
# -ftree-vectorize (SSE2 paddq); the *_lowBW variants stay scalar at -O1.
BWCFLAGS = -O3 -static -march=x86-64 -ftree-vectorize
TARGETS = victim dummy aggressor aggressor_finite aggressor_lowBW aggressor_finite_lowBW

all: $(TARGETS)

victim: victim.c
	$(CC) $(CFLAGS) -o $@ $<

dummy: dummy.c
	$(CC) $(CFLAGS) -o $@ $<

aggressor: aggressor.c
	$(CC) $(BWCFLAGS) -o $@ $<

aggressor_finite: aggressor_finite.c
	$(CC) $(BWCFLAGS) -o $@ $<

aggressor_lowBW: aggressor_lowBW.c
	$(CC) $(CFLAGS) -o $@ $<

aggressor_finite_lowBW: aggressor_finite_lowBW.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f $(TARGETS)

.PHONY: all clean
