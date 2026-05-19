CC      = gcc
CFLAGS  = -O1 -static -march=x86-64
TARGETS = victim aggressor dummy

all: $(TARGETS)

victim: victim.c
	$(CC) $(CFLAGS) -o $@ $<

aggressor: aggressor.c
	$(CC) $(CFLAGS) -o $@ $<

dummy: dummy.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f $(TARGETS)

.PHONY: all clean
