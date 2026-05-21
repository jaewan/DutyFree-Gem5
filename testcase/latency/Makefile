CC      = gcc
CFLAGS  = -O1 -static -march=x86-64
TARGETS = latency_bench shared_bench

all: $(TARGETS)

latency_bench: latency_bench.c
	$(CC) $(CFLAGS) -o $@ $<

shared_bench: shared_bench.c
	$(CC) $(CFLAGS) -pthread -o $@ $<

clean:
	rm -f $(TARGETS)

.PHONY: all clean
