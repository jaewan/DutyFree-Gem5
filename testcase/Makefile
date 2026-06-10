# Top-level testcase Makefile: build/clean all workloads at once.
#   make -C testcase          # build everything
#   make -C testcase clean    # clean everything

SUBDIRS = coherence latency dirtax dutyfree

.PHONY: all clean $(SUBDIRS)

all: $(SUBDIRS)

$(SUBDIRS):
	$(MAKE) -C $@

clean:
	@for d in $(SUBDIRS); do $(MAKE) -C $$d clean; done
