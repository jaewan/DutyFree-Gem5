CC      = gcc
CFLAGS  = -O1 -static -march=x86-64
# BW-max aggressors (the default aggressor/aggressor_finite) need -O3
# -ftree-vectorize (SSE2 paddq); the *_lowBW variants stay scalar at -O1.
BWCFLAGS = -O3 -static -march=x86-64 -ftree-vectorize
TARGETS = victim dummy fused aggressor aggressor_finite aggressor_lowBW aggressor_finite_lowBW dutyfree_gem5_FS

all: $(TARGETS)

victim: victim.c
	$(CC) $(CFLAGS) -o $@ $<

dummy: dummy.c
	$(CC) $(CFLAGS) -o $@ $<

# fused = stream + hot table; the workload a pure stream cannot stand in for
fused: fused.c
	$(CC) $(BWCFLAGS) -o $@ $<

aggressor: aggressor.c
	$(CC) $(BWCFLAGS) -o $@ $<

aggressor_finite: aggressor_finite.c
	$(CC) $(BWCFLAGS) -o $@ $<

aggressor_lowBW: aggressor_lowBW.c
	$(CC) $(CFLAGS) -o $@ $<

aggressor_finite_lowBW: aggressor_finite_lowBW.c
	$(CC) $(CFLAGS) -o $@ $<

# FS-mode aggressor (mprotect(PROT_STREAMING)); static so it runs in the guest.
dutyfree_gem5_FS: dutyfree_gem5_FS.c
	$(CC) $(BWCFLAGS) -o $@ $<

clean:
	rm -f $(TARGETS)

.PHONY: all clean
