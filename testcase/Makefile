# Top-level testcase build: recurse into every subdir that has a Makefile.
# `make -C testcase` builds all (coherence, dirtax, dutyfree, latency, ...).
SUBDIRS := $(patsubst %/,%,$(dir $(wildcard */Makefile)))

.PHONY: all clean $(SUBDIRS)

all: $(SUBDIRS)

$(SUBDIRS):
	$(MAKE) -C $@

clean:
	for d in $(SUBDIRS); do $(MAKE) -C $$d clean; done
