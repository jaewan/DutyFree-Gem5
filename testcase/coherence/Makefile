CC      = gcc
CFLAGS  = -O1 -static -march=x86-64
TARGETS = coherence_tests

all: $(TARGETS)

coherence_tests: coherence_tests.c
	$(CC) $(CFLAGS) -pthread -o $@ $<

clean:
	rm -f $(TARGETS)

.PHONY: all clean
