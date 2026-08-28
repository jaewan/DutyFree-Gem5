import os
# Copyright (c) 2021-2024 Arm Limited
# All rights reserved.
#
# The license below extends only to copyright in the software and shall
# not be construed as granting a license to any other intellectual
# property including but not limited to intellectual property relating
# to a hardware implementation of the functionality of the software
# licensed hereunder.  You may use the software subject to the license
# terms below provided that you ensure that this notice is replicated
# unmodified and in its entirety in all distributions of the software,
# modified or unmodified, in source code or in binary form.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met: redistributions of source code must retain the above copyright
# notice, this list of conditions and the following disclaimer;
# redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution;
# neither the name of the copyright holders nor the names of its
# contributors may be used to endorse or promote products derived from
# this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

"""
Definitions for CHI nodes and controller types. These are used by
create_system in configs/ruby/CHI.py or may be used in custom configuration
scripts. When used with create_system, the user may provide an additional
configuration file as the --chi-config parameter to specialize the classes
defined here.

When using the CustomMesh topology, --chi-config must be provided with
specialization of the NoC_Param classes defining the NoC dimensions and
node to router binding. See configs/example/noc_config/2x4.py for an example.
"""

import math
import os

import m5
from m5.objects import *


# Declare caches and controller types used by the protocol
# Notice tag and data accesses are not concurrent, so the a cache hit
# latency = tag + data + response latencies.
# Default response latencies are 1 cy for all controllers.
# For L1 controllers the mandatoryQueue enqueue latency is always 1 cy and
# this is deducted from the initial tag read latency for sequencer requests
# dataAccessLatency may be set to 0 if one wants to consider parallel
# data and tag lookups
class L1ICache(RubyCache):
    dataAccessLatency = 1
    tagAccessLatency = 1


class L1DCache(RubyCache):
    # Verification hook for way partitioning: L1D_MASK=<hex> confines every
    # requestor in this cache to those ways. 0/unset leaves it unpartitioned.
    way_mask = int(os.environ.get("L1D_MASK", "0"), 0)
    # TreePLRU cannot take a candidate subset, so a partitioned cache needs a
    # linearly-scanned policy. Only switched when a mask is actually set, so the
    # unpartitioned baseline keeps the default and stays comparable to prior runs.
    if way_mask != 0:
        replacement_policy = LRURP()

    # end-to-end calibrated 2026-07-06: measured 2.6ns load-to-use (EMR);
    # path overhead eats most of it, so the array itself is nearly free
    dataAccessLatency = 1
    tagAccessLatency = 1


class L2Cache(RubyCache):
    # end-to-end calibrated 2026-07-06: measured 8.4ns incl. L1-miss path
    dataAccessLatency = 1
    tagAccessLatency = 2


class Versions:
    """
    Helper class to obtain unique ids for a given controller class.
    These are passed as the 'version' parameter when creating the controller.
    """

    _seqs = 0

    @classmethod
    def getSeqId(cls):
        val = cls._seqs
        cls._seqs += 1
        return val

    _version = {}

    @classmethod
    def getVersion(cls, tp):
        if tp not in cls._version:
            cls._version[tp] = 0
        val = cls._version[tp]
        cls._version[tp] = val + 1
        return val


class NoC_Params:
    """
    Default parameters for the interconnect. The value of data_width is
    also used to set the data_channel_size for all CHI controllers.
    (see configs/ruby/CHI.py)
    """

    router_link_latency = 1
    node_link_latency = 1
    router_latency = 1
    router_buffer_size = 4
    cntrl_msg_size = 8
    data_width = 32
    cross_links = []
    cross_link_latency = 0


class CHI_Node(SubSystem):
    """
    Base class with common functions for setting up Cache or Memory
    controllers that are part of a CHI RNF, RNFI, HNF, or SNF nodes.
    Notice getNetworkSideControllers and getAllControllers must be implemented
    in the derived classes.
    """

    class NoC_Params:
        """
        NoC config. parameters and bindings required for CustomMesh topology.

        Maps 'num_nodes_per_router' CHI nodes to each router provided in
        'router_list'. This assumes len(router_list)*num_nodes_per_router
        equals the number of nodes
        If 'num_nodes_per_router' is left undefined, we circulate around
        'router_list' until all nodes are mapped.
        See 'distributeNodes' in configs/topologies/CustomMesh.py
        """

        num_nodes_per_router = None
        router_list = None

    def __init__(self, ruby_system):
        super().__init__()
        self._ruby_system = ruby_system
        self._network = ruby_system.network

    def getNetworkSideControllers(self):
        """
        Returns all ruby controllers that need to be connected to the
        network
        """
        raise NotImplementedError()

    def getAllControllers(self):
        """
        Returns all ruby controllers associated with this node
        """
        raise NotImplementedError()

    def setDownstream(self, cntrls):
        """
        Sets cntrls as the downstream list of all controllers in this node
        """
        for c in self.getNetworkSideControllers():
            c.downstream_destinations = cntrls

    def connectController(self, cntrl):
        """
        Creates and configures the messages buffers for the CHI input/output
        ports that connect to the network
        """
        cntrl.reqOut = MessageBuffer()
        cntrl.rspOut = MessageBuffer()
        cntrl.snpOut = MessageBuffer()
        cntrl.datOut = MessageBuffer()
        cntrl.reqIn = MessageBuffer()
        cntrl.rspIn = MessageBuffer()
        cntrl.snpIn = MessageBuffer()
        cntrl.datIn = MessageBuffer()

        # All CHI ports are always connected to the network.
        # Controllers that are not part of the getNetworkSideControllers list
        # still communicate using internal routers, thus we need to wire-up the
        # ports
        cntrl.reqOut.out_port = self._network.in_port
        cntrl.rspOut.out_port = self._network.in_port
        cntrl.snpOut.out_port = self._network.in_port
        cntrl.datOut.out_port = self._network.in_port
        cntrl.reqIn.in_port = self._network.out_port
        cntrl.rspIn.in_port = self._network.out_port
        cntrl.snpIn.in_port = self._network.out_port
        cntrl.datIn.in_port = self._network.out_port


class TriggerMessageBuffer(MessageBuffer):
    """
    MessageBuffer for triggering internal controller events.
    These buffers should not be affected by the Ruby tester randomization
    and allow poping messages enqueued in the same cycle.
    """

    randomization = "disabled"
    allow_zero_latency = True


class OrderedTriggerMessageBuffer(TriggerMessageBuffer):
    ordered = True


class MemCtrlMessageBuffer(MessageBuffer):
    """
    MessageBuffer exchanging messages with the memory
    These buffers should also not be affected by the Ruby tester randomization.
    """

    randomization = "disabled"
    ordered = True


class Base_CHI_Cache_Controller(CHI_Cache_Controller):
    """
    Default parameters for a Cache controller
    The Cache_Controller can also be used as a DMA requester or as
    a pure directory if all cache allocation policies are disabled.
    """

    def __init__(self, ruby_system):
        super().__init__(
            version=Versions.getVersion(CHI_Cache_Controller),
            ruby_system=ruby_system,
            mandatoryQueue=MessageBuffer(),
            prefetchQueue=MessageBuffer(),
            triggerQueue=TriggerMessageBuffer(),
            retryTriggerQueue=OrderedTriggerMessageBuffer(),
            replTriggerQueue=OrderedTriggerMessageBuffer(),
            reqRdy=TriggerMessageBuffer(),
            snpRdy=TriggerMessageBuffer(),
        )
        # Set somewhat large number since we really a lot on internal
        # triggers. To limit the controller performance, tweak other
        # params such as: input port buffer size, cache banks, and output
        # port latency
        self.transitions_per_cycle = 1024
        # This should be set to true in the data cache controller to enable
        # timeouts on unique lines when a store conditional fails
        self.sc_lock_enabled = False
        # H3/B2 finite snoop-filter backing store. SLICC auto-generates an
        # UNCONDITIONAL m_sf_ptr->setRubySystem() for this CacheMemory param, so
        # it cannot be NULL. Give every controller a tiny dummy that is NEVER
        # accessed unless sf_finite (getDirEntry/dirTagPresent/CheckSFFill all
        # gate on sf_finite) -> byte-identical to legacy. The HNF overrides this
        # with the real finite SF only when HNF_SF_FINITE is set.
        self.sf = SFDirectory(size="1kB", assoc=1)


class CHI_L1Controller(Base_CHI_Cache_Controller):
    """
    Default parameters for a L1 Cache controller
    """

    def __init__(self, ruby_system, sequencer, cache, prefetcher):
        super().__init__(ruby_system)
        self.sequencer = sequencer
        self.cache = cache
        self.prefetcher = prefetcher
        self.use_prefetcher = prefetcher != NULL
        self.send_evictions = True
        self.is_HN = False
        self.enable_DMT = False
        self.enable_DCT = False
        # Strict inclusive MOESI
        self.allow_SD = True
        self.alloc_on_seq_acc = True
        self.alloc_on_seq_line_write = False
        self.alloc_on_readshared = True
        self.alloc_on_readunique = True
        self.alloc_on_readonce = True
        # H3: participate in the STREAMING no-footprint bypass so streaming
        # reads are issued as ReadOnce (no L1/L2 retention). Off unless HNF_H3=1.
        self.enable_H3_streaming_bypass = bool(
            int(os.environ.get("HNF_H3", 0))
        )
        self.alloc_on_writeback = True
        self.alloc_on_atomic = False
        self.dealloc_on_unique = False
        self.dealloc_on_shared = False
        self.dealloc_backinv_unique = True
        self.dealloc_backinv_shared = True
        # Some reasonable default TBE params (env L1_MSHR, unset=16)
        self.number_of_TBEs = int(os.environ.get("L1_MSHR", 16))
        # Replacement-path depth (env L1_REPL). Default 16 so an unset
        # environment reproduces today's behavior exactly. Sweeping L1_MSHR
        # alone starves this path relative to the request path (64 vs 16),
        # and the STREAMING attribute has to survive the eviction path
        # (cache_entry.isStreaming -> TBE -> WriteEvictFull) to be honoured
        # at the HNF -- so this is a candidate cause of H2 fill-suppression
        # degrading at high L1_MSHR.
        self.number_of_repl_TBEs = int(os.environ.get("L1_REPL", 16))
        self.number_of_snoop_TBEs = 4
        self.number_of_DVM_TBEs = 16
        self.number_of_DVM_snoop_TBEs = 4

        self.unify_repl_TBEs = False


class CHI_L2Controller(Base_CHI_Cache_Controller):
    """
    Default parameters for a L2 Cache controller
    """

    def __init__(self, ruby_system, cache, prefetcher):
        super().__init__(ruby_system)
        self.sequencer = NULL
        self.cache = cache
        self.prefetcher = prefetcher
        self.use_prefetcher = prefetcher != NULL
        self.allow_SD = True
        self.is_HN = False
        self.enable_DMT = False
        self.enable_DCT = False
        self.send_evictions = False
        # Strict inclusive MOESI
        self.alloc_on_seq_acc = False
        self.alloc_on_seq_line_write = False
        self.alloc_on_readshared = True
        self.alloc_on_readunique = True
        self.alloc_on_readonce = True
        # H3: participate in the STREAMING no-footprint bypass so streaming
        # reads are issued as ReadOnce (no L1/L2 retention). Off unless HNF_H3=1.
        self.enable_H3_streaming_bypass = bool(
            int(os.environ.get("HNF_H3", 0))
        )
        self.alloc_on_writeback = True
        self.alloc_on_atomic = False
        self.dealloc_on_unique = False
        self.dealloc_on_shared = False
        self.dealloc_backinv_unique = True
        self.dealloc_backinv_shared = True
        # L2 superqueue ~48 on SPR/EMR (env L2_MSHR)
        self.number_of_TBEs = int(os.environ.get("L2_MSHR", 48))
        # Replacement-path depth (env L2_REPL); default 32 preserves today's
        # behavior when unset. See the L1_REPL note above.
        self.number_of_repl_TBEs = int(os.environ.get("L2_REPL", 32))
        self.number_of_snoop_TBEs = 16
        self.number_of_DVM_TBEs = 1  # should not receive any dvm
        self.number_of_DVM_snoop_TBEs = 1  # should not receive any dvm
        self.unify_repl_TBEs = False


class CHI_HNFController(Base_CHI_Cache_Controller):
    """
    Default parameters for a coherent home node (HNF) cache controller
    """

    def __init__(self, ruby_system, cache, prefetcher, addr_ranges):
        super().__init__(ruby_system)
        self.sequencer = NULL
        self.cache = cache
        self.prefetcher = prefetcher
        self.use_prefetcher = prefetcher != NULL
        self.addr_ranges = addr_ranges
        self.allow_SD = True
        self.is_HN = True
        # DMT default ON (calibrated baseline, unchanged for all existing runs).
        # The H3/finite-SF experiment sets HNF_DMT=0: the finite-SF dir-allocation
        # deferral (CheckSFFill) is incompatible with the DMT read pipeline's
        # SendReadNoSnpDMT sequencing, and DMT is orthogonal to the SF story.
        self.enable_DMT = bool(int(os.environ.get("HNF_DMT", 1)))
        self.enable_DCT = True
        self.send_evictions = False
        # Non-inclusive (victim cache): L2 evictions fill LLC, reads do not.
        self.alloc_on_seq_acc = False
        self.alloc_on_seq_line_write = False
        self.alloc_on_readshared = False
        self.alloc_on_readunique = False
        self.alloc_on_readonce = False
        self.alloc_on_writeback = True
        self.alloc_on_atomic = True
        self.dealloc_on_unique = True
        self.dealloc_on_shared = False
        self.dealloc_backinv_unique = False
        self.dealloc_backinv_shared = False
        # H3 / finite snoop filter (see H3_FINITE_SF_DESIGN.md).  Both default
        # OFF so an unset environment reproduces today's behavior exactly.
        #   HNF_SF_FINITE=1 -> model the HNF directory as a finite snoop filter
        #   HNF_H3=1        -> STREAMING lines skip directory/SF enrollment
        self.sf_finite = bool(int(os.environ.get("HNF_SF_FINITE", 0)))
        self.enable_H3_streaming_bypass = bool(
            int(os.environ.get("HNF_H3", 0))
        )
        # HNF_FWD_UNIQUE: a ReadShared hitting a UC/UD line at the HNF is
        # answered with unique state (real x86 MESIF grants E to a sole
        # reader). Default 1 since 2026-08-14: the gem5 CHI default (grant
        # SC) permanently exiles a victim's clean lines from the NINE LLC
        # after their first eviction (SC evicts are silent, no refill path),
        # inflating the onset-region tax (mini 25p: 1.63 vs 1.29; 53p+ and
        # H2/BW unaffected — see 9_shared_vs_distinct.md A/B).
        # HNF_FWD_UNIQUE=0 restores the old SC behavior.
        self.fwd_unique_on_readshared = bool(
            int(os.environ.get("HNF_FWD_UNIQUE", 1))
        )
        # Cross-guard: the finite-SF dir-allocation deferral (CheckSFFill) is
        # incompatible with the DMT read pipeline (SendReadNoSnpDMT sequencing),
        # and finite-SF misses often, firing the DMT branch constantly. Forgetting
        # HNF_DMT=0 would silently exercise that untested combination and could
        # corrupt results with no crash. Fail loudly instead.
        assert not (
            self.sf_finite and self.enable_DMT
        ), "finite SF (HNF_SF_FINITE=1) requires DMT off (HNF_DMT=0)"
        # Some reasonable default TBE params (env HNF_MSHR, unset=32)
        self.number_of_TBEs = int(os.environ.get("HNF_MSHR", 32))
        self.number_of_repl_TBEs = 32
        self.number_of_snoop_TBEs = 1  # should not receive any snoop
        self.number_of_DVM_TBEs = 1  # should not receive any dvm
        self.number_of_DVM_snoop_TBEs = 1  # should not receive any dvm
        self.unify_repl_TBEs = False


class CHI_MNController(CHI_MiscNode_Controller):
    """
    Default parameters for a Misc Node
    """

    def __init__(
        self, ruby_system, addr_range, l1d_caches, early_nonsync_comp
    ):
        super().__init__(
            version=Versions.getVersion(CHI_MiscNode_Controller),
            ruby_system=ruby_system,
            mandatoryQueue=MessageBuffer(),
            triggerQueue=TriggerMessageBuffer(),
            retryTriggerQueue=TriggerMessageBuffer(),
            schedRspTriggerQueue=TriggerMessageBuffer(),
            reqRdy=TriggerMessageBuffer(),
            snpRdy=TriggerMessageBuffer(),
        )
        # Set somewhat large number since we really a lot on internal
        # triggers. To limit the controller performance, tweak other
        # params such as: input port buffer size, cache banks, and output
        # port latency
        self.transitions_per_cycle = 1024
        self.addr_ranges = [addr_range]
        # 16 total transaction buffer entries, but 1 is reserved for DVMNonSync
        self.number_of_DVM_TBEs = 16
        self.number_of_non_sync_TBEs = 1
        self.early_nonsync_comp = early_nonsync_comp

        # "upstream_destinations" = targets for DVM snoops
        self.upstream_destinations = l1d_caches


class CHI_DMAController(Base_CHI_Cache_Controller):
    """
    Default parameters for a DMA controller
    """

    def __init__(self, ruby_system, sequencer):
        super().__init__(ruby_system)
        self.sequencer = sequencer

        class DummyCache(RubyCache):
            dataAccessLatency = 0
            tagAccessLatency = 1
            size = "128"
            assoc = 1

        self.prefetcher = NULL
        self.use_prefetcher = False
        self.cache = DummyCache()
        self.sequencer.dcache = NULL
        # All allocations are false
        # Deallocations are true (don't really matter)
        self.allow_SD = False
        self.is_HN = False
        self.enable_DMT = False
        self.enable_DCT = False
        self.alloc_on_seq_acc = False
        self.alloc_on_seq_line_write = False
        self.alloc_on_readshared = False
        self.alloc_on_readunique = False
        self.alloc_on_readonce = False
        self.alloc_on_writeback = False
        self.alloc_on_atomic = False
        self.dealloc_on_unique = False
        self.dealloc_on_shared = False
        self.dealloc_backinv_unique = False
        self.dealloc_backinv_shared = False
        self.send_evictions = False
        self.number_of_TBEs = 16
        self.number_of_repl_TBEs = 1
        self.number_of_snoop_TBEs = 1  # should not receive any snoop
        self.number_of_DVM_TBEs = 1  # should not receive any dvm
        self.number_of_DVM_snoop_TBEs = 1  # should not receive any dvm
        self.unify_repl_TBEs = False


class CPUSequencerWrapper:
    """
    Other generic configuration scripts assume a matching number of sequencers
    and cpus. This wraps the instruction and data sequencer so they are
    compatible with the other scripts. This assumes all scripts are using
    connectCpuPorts/connectIOPorts to bind ports
    """

    def __init__(self, iseq, dseq):
        # use this style due to __setattr__ override below
        self.__dict__["inst_seq"] = iseq
        self.__dict__["data_seq"] = dseq
        self.__dict__["support_data_reqs"] = True
        self.__dict__["support_inst_reqs"] = True
        # Compatibility with certain scripts that wire up ports
        # without connectCpuPorts
        self.__dict__["in_ports"] = dseq.in_ports

    def connectCpuPorts(self, cpu):
        assert isinstance(cpu, BaseCPU)
        cpu.icache_port = self.inst_seq.in_ports
        for p in cpu._cached_ports:
            if str(p) != "icache_port":
                exec(f"cpu.{p} = self.data_seq.in_ports")
        cpu.connectUncachedPorts(
            self.data_seq.in_ports, self.data_seq.interrupt_out_port
        )

    def connectIOPorts(self, piobus):
        self.data_seq.connectIOPorts(piobus)

    def __setattr__(self, name, value):
        setattr(self.inst_seq, name, value)
        setattr(self.data_seq, name, value)


class CHI_RNF(CHI_Node):
    """
    Defines a CHI request node.
    Notice all contollers and sequencers are set as children of the cpus, so
    this object acts more like a proxy for seting things up and has no topology
    significance unless the cpus are set as its children at the top level
    """

    def __init__(
        self,
        cpus,
        ruby_system,
        l1Icache_type,
        l1Dcache_type,
        cache_line_size,
        l1Iprefetcher_type=None,
        l1Dprefetcher_type=None,
    ):
        super().__init__(ruby_system)

        self._block_size_bits = int(math.log(cache_line_size, 2))

        # All sequencers and controllers
        self._seqs = []
        self._cntrls = []

        # Last level controllers in this node, i.e., the ones that will send
        # requests to the home nodes
        self._ll_cntrls = []

        self._cpus = cpus

        # First creates L1 caches and sequencers
        # SEQ_OUT: sequencer max_outstanding_requests (counted per load).
        # Default 32 (2026-08-19): LFB-like limit. The 16..1024 sweep showed
        # victim tax/H2 insensitive; only the demand-only WC arm needs a
        # bounded sequencer for its low-BW contrast (>=128 is non-binding
        # and WC collapses to WB-level BW). Override via env for sweeps.
        _seq_out = int(os.environ.get("SEQ_OUT", 32))
        for cpu in self._cpus:
            cpu.inst_sequencer = RubySequencer(
                version=Versions.getSeqId(), ruby_system=ruby_system
            )
            cpu.data_sequencer = RubySequencer(
                version=Versions.getSeqId(),
                ruby_system=ruby_system,
                max_outstanding_requests=_seq_out,
            )

            self._seqs.append(
                CPUSequencerWrapper(cpu.inst_sequencer, cpu.data_sequencer)
            )

            # caches
            l1i_cache = l1Icache_type(
                start_index_bit=self._block_size_bits, is_icache=True
            )

            l1d_cache = l1Dcache_type(
                start_index_bit=self._block_size_bits, is_icache=False
            )

            # prefetcher wrappers
            if l1Iprefetcher_type != None:
                l1i_pf = l1Iprefetcher_type()
            else:
                l1i_pf = NULL

            if l1Dprefetcher_type != None:
                l1d_pf = l1Dprefetcher_type()
            else:
                l1d_pf = NULL

            # cache controllers
            cpu.l1i = CHI_L1Controller(
                ruby_system, cpu.inst_sequencer, l1i_cache, l1i_pf
            )

            cpu.l1d = CHI_L1Controller(
                ruby_system, cpu.data_sequencer, l1d_cache, l1d_pf
            )

            cpu.inst_sequencer.dcache = NULL
            cpu.data_sequencer.dcache = cpu.l1d.cache

            cpu.l1d.sc_lock_enabled = True

            cpu._ll_cntrls = [cpu.l1i, cpu.l1d]
            for c in cpu._ll_cntrls:
                self._cntrls.append(c)
                self.connectController(c)
                self._ll_cntrls.append(c)

    def getSequencers(self):
        return self._seqs

    def getAllControllers(self):
        return self._cntrls

    def getNetworkSideControllers(self):
        return self._cntrls

    def setDownstream(self, cntrls):
        for c in self._ll_cntrls:
            c.downstream_destinations = cntrls

    def getCpus(self):
        return self._cpus

    # Adds a private L2 for each cpu
    def addPrivL2Cache(self, cache_type, pf_type=None):
        self._ll_cntrls = []
        for cpu in self._cpus:
            l2_cache = cache_type(
                start_index_bit=self._block_size_bits, is_icache=False
            )

            if pf_type != None:
                l2_pf = pf_type()
            else:
                l2_pf = NULL

            cpu.l2 = CHI_L2Controller(self._ruby_system, l2_cache, l2_pf)

            self._cntrls.append(cpu.l2)
            self.connectController(cpu.l2)

            self._ll_cntrls.append(cpu.l2)

            for c in cpu._ll_cntrls:
                c.downstream_destinations = [cpu.l2]
            cpu._ll_cntrls = [cpu.l2]

    @classmethod
    def generate(cls, options, ruby_system, cpus):
        # Intel SPR-like prefetcher (all 4 default-ON):
        # L1D: DCU Streamer (Stride) + DCU IP Prefetcher (DCPT)
        # L2:  MLC Streamer (Stride) + MLC Spatial/Adjacent (Tagged)
        # PF_DEGREE(_L1/_L2): stride prefetch depth, 4KB-page bound (tuning)
        _deg = int(os.environ.get("PF_DEGREE", 4))
        _deg1 = int(os.environ.get("PF_DEGREE_L1", _deg))
        _deg2 = int(os.environ.get("PF_DEGREE_L2", _deg))

        # PF_PAGE: stride prefetcher page_bytes (diagnostic; 4KB is faithful)
        _pfpage = os.environ.get("PF_PAGE", "4KiB")

        class L1DIntelPF(MultiPrefetcher):
            prefetchers = [
                StridePrefetcher(
                    degree=_deg1,
                    queue_size=max(32, _deg1 * 4),
                    page_bytes=_pfpage,
                ),
                DCPTPrefetcher(),
            ]

        class L2IntelPF(MultiPrefetcher):
            prefetchers = [
                StridePrefetcher(
                    degree=_deg2,
                    queue_size=max(32, _deg2 * 4),
                    page_bytes=_pfpage,
                ),
                TaggedPrefetcher(),
            ]

        # PF_OFF_CORES="1,2,3": disable L1D/L2 prefetchers on those cpu_ids
        _pfoff = {
            int(x)
            for x in os.environ.get("PF_OFF_CORES", "").split(",")
            if x.strip()
        }

        rnfs = [
            cls(
                [cpu],
                ruby_system,
                L1ICache(size=options.l1i_size, assoc=options.l1i_assoc),
                L1DCache(size=options.l1d_size, assoc=options.l1d_assoc),
                options.cacheline_size,
                l1Dprefetcher_type=(
                    None if int(cpu.cpu_id) in _pfoff else L1DIntelPF
                ),
            )
            for cpu in cpus
        ]
        for rnf in rnfs:
            rnf.addPrivL2Cache(
                L2Cache(size=options.l2_size, assoc=options.l2_assoc),
                pf_type=(
                    None
                    if int(rnf.getCpus()[0].cpu_id) in _pfoff
                    else L2IntelPF
                ),
            )
        return rnfs


class CHI_HNF(CHI_Node):
    """
    Encapsulates an HNF cache/directory controller.
    Before the first controller is created, the class method
    CHI_HNF.createAddrRanges must be called before creating any CHI_HNF object
    to set-up the interleaved address ranges used by the HNFs
    """

    class NoC_Params(CHI_Node.NoC_Params):
        """HNFs may also define the 'pairing' parameter to allow pairing"""

        pairing = None

    _addr_ranges = {}

    @classmethod
    def createAddrRanges(cls, sys_mem_ranges, cache_line_size, hnfs):
        # Create the HNFs interleaved addr ranges
        block_size_bits = int(math.log(cache_line_size, 2))
        llc_bits = int(math.log(len(hnfs), 2))
        numa_bit = block_size_bits + llc_bits - 1
        for i, hnf in enumerate(hnfs):
            ranges = []
            for r in sys_mem_ranges:
                addr_range = AddrRange(
                    r.start,
                    size=r.size(),
                    intlvHighBit=numa_bit,
                    intlvBits=llc_bits,
                    intlvMatch=i,
                )
                ranges.append(addr_range)
            cls._addr_ranges[hnf] = (ranges, numa_bit)

    @classmethod
    def getAddrRanges(cls, hnf_idx):
        assert len(cls._addr_ranges) != 0
        return cls._addr_ranges[hnf_idx]

    # The CHI controller can be a child of this object or another if
    # 'parent' if specified
    def __init__(self, hnf_idx, ruby_system, llcache_type, parent):
        super().__init__(ruby_system)

        addr_ranges, intlvHighBit = self.getAddrRanges(hnf_idx)
        # All ranges should have the same interleaving
        assert len(addr_ranges) >= 1

        ll_cache = llcache_type(start_index_bit=intlvHighBit + 1)

        # LLC replacement policy (env HNF_RP). Unset keeps whatever
        # llcache_type specifies; RubyCache's default is TreePLRURP, which is
        # what every published number in this project was produced with -- so
        # an unset environment reproduces prior behaviour exactly, and any
        # comparison must name TreePLRU rather than assume LRU.
        #
        # #28 needs a reuse predictor at the LLC to compare declaration
        # against prediction. SHiP is the only one in this tree (Hawkeye and
        # Mockingjay are absent). SHiPMemRP, not SHiPPCRP: Ruby requests do
        # not reliably carry a PC for a PC-indexed signature.
        _rp = os.environ.get("HNF_RP", "").strip().lower()
        if _rp in ("ship", "ship_mem", "shipmem"):
            ll_cache.replacement_policy = SHiPMemRP()
        elif _rp == "brrip":
            ll_cache.replacement_policy = BRRIPRP()
        elif _rp == "lru":
            ll_cache.replacement_policy = LRURP()
        elif _rp not in ("", "default", "treeplru", "tree_plru"):
            m5.fatal("unknown HNF_RP=%s (ship|brrip|lru|treeplru)", _rp)

        self._cntrl = CHI_HNFController(
            ruby_system, ll_cache, NULL, addr_ranges
        )

        # H3/B2 finite snoop filter. Only the HNF gets a real `sf`; only when
        # HNF_SF_FINITE=1. Default (unset) leaves sf=NULL and sf_finite=False
        # (byte-identical to legacy). Indexed like the LLC slice so per-HNF
        # interleaving lines up. Sized huge by default so it never evicts
        # (behaves as the infinite PerfectCacheMemory); shrink via env for B4.
        if bool(int(os.environ.get("HNF_SF_FINITE", 0))):
            sf_ways = int(os.environ.get("HNF_SF_WAYS", 16))
            sf_sets = int(os.environ.get("HNF_SF_SETS", 1 << 16))
            self._cntrl.sf = SFDirectory(
                size=str(sf_sets * sf_ways * 64)
                + "B",  # MemorySize wants a str; 64B/line
                assoc=sf_ways,
                start_index_bit=intlvHighBit + 1,
            )
            # sf_finite is already read from env in CHI_HNFController.__init__;
            # this asserts the invariant sf != NULL <=> sf_finite at the HNF.
            assert self._cntrl.sf_finite

        if parent == None:
            self.cntrl = self._cntrl
        else:
            parent.cntrl = self._cntrl

        self.connectController(self._cntrl)

    def getAllControllers(self):
        return [self._cntrl]

    def getNetworkSideControllers(self):
        return [self._cntrl]


class CHI_MN(CHI_Node):
    """
    Encapsulates a Misc Node controller.
    """

    class NoC_Params(CHI_Node.NoC_Params):
        """HNFs may also define the 'pairing' parameter to allow pairing"""

        pairing = None

    # The CHI controller can be a child of this object or another if
    # 'parent' if specified
    def __init__(self, ruby_system, l1d_caches, early_nonsync_comp=False):
        super().__init__(ruby_system)

        # MiscNode has internal address range starting at 0
        addr_range = AddrRange(0, size="1KiB")

        self._cntrl = CHI_MNController(
            ruby_system, addr_range, l1d_caches, early_nonsync_comp
        )

        self.cntrl = self._cntrl

        self.connectController(self._cntrl)

    def connectController(self, cntrl):
        CHI_Node.connectController(self, cntrl)

    def getAllControllers(self):
        return [self._cntrl]

    def getNetworkSideControllers(self):
        return [self._cntrl]

    @classmethod
    def generate(cls, options, ruby_system, cpus):
        """
        Creates one Misc Node
        """
        return [cls(ruby_system, [cpu.l1d for cpu in cpus])]


class CHI_SNF_Base(CHI_Node):
    """
    Creates CHI node controllers for the memory controllers
    """

    # The CHI controller can be a child of this object or another if
    # 'parent' if specified
    def __init__(self, ruby_system, parent):
        super().__init__(ruby_system)

        self._cntrl = CHI_Memory_Controller(
            version=Versions.getVersion(CHI_Memory_Controller),
            ruby_system=ruby_system,
            triggerQueue=TriggerMessageBuffer(),
            responseFromMemory=MemCtrlMessageBuffer(),
            requestToMemory=MemCtrlMessageBuffer(),
            reqRdy=TriggerMessageBuffer(),
            transitions_per_cycle=1024,
        )

        # SNF_MSHR: number_of_TBEs, SNF_REQBUF: requestToMemory depth
        self._cntrl.number_of_TBEs = int(os.environ.get("SNF_MSHR", 256))

        # The Memory_Controller implementation deallocates the TBE for
        # write requests when they are queue up to memory. The size of this
        # buffer must be limited to prevent unlimited outstanding writes.
        self._cntrl.requestToMemory.buffer_size = int(
            os.environ.get(
                "SNF_REQBUF", int(self._cntrl.to_memory_controller_latency) + 1
            )
        )

        self.connectController(self._cntrl)

        if parent:
            parent.cntrl = self._cntrl
        else:
            self.cntrl = self._cntrl

    def getAllControllers(self):
        return [self._cntrl]

    def getNetworkSideControllers(self):
        return [self._cntrl]

    def getMemRange(self, mem_ctrl):
        # TODO need some kind of transparent API for
        # MemCtrl+DRAM vs SimpleMemory
        if hasattr(mem_ctrl, "range"):
            return mem_ctrl.range
        else:
            return mem_ctrl.dram.range


class CHI_SNF_BootMem(CHI_SNF_Base):
    """
    Create the SNF for the boot memory
    """

    def __init__(self, ruby_system, parent, bootmem):
        super().__init__(ruby_system, parent)
        self._cntrl.memory_out_port = bootmem.port
        self._cntrl.addr_ranges = self.getMemRange(bootmem)


class CHI_SNF_MainMem(CHI_SNF_Base):
    """
    Create the SNF for a list main memory controllers
    """

    def __init__(self, ruby_system, parent, mem_ctrl=None):
        super().__init__(ruby_system, parent)
        if mem_ctrl:
            self._cntrl.memory_out_port = mem_ctrl.port
            self._cntrl.addr_ranges = self.getMemRange(mem_ctrl)
        # else bind ports and range later


class CHI_RNI_Base(CHI_Node):
    """
    Request node without cache / DMA
    """

    # The CHI controller can be a child of this object or another if
    # 'parent' if specified
    def __init__(self, ruby_system, parent):
        super().__init__(ruby_system)

        self._sequencer = RubySequencer(
            version=Versions.getSeqId(),
            ruby_system=ruby_system,
            clk_domain=ruby_system.clk_domain,
        )
        self._cntrl = CHI_DMAController(ruby_system, self._sequencer)

        if parent:
            parent.cntrl = self._cntrl
        else:
            self.cntrl = self._cntrl

        self.connectController(self._cntrl)

    def getAllControllers(self):
        return [self._cntrl]

    def getNetworkSideControllers(self):
        return [self._cntrl]


class CHI_RNI_DMA(CHI_RNI_Base):
    """
    DMA controller wiredup to a given dma port
    """

    def __init__(self, ruby_system, dma_port, parent):
        super().__init__(ruby_system, parent)
        assert dma_port != None
        self._sequencer.in_ports = dma_port


class CHI_RNI_IO(CHI_RNI_Base):
    """
    DMA controller wiredup to ruby_system IO port
    """

    def __init__(self, ruby_system, parent):
        super().__init__(ruby_system, parent)
        ruby_system._io_port = self._sequencer


class SFDirectory(RubyCache):
    # H3/B2 finite snoop-filter / coherence-directory backing store for the HNF.
    # DirEntry carries no DataBlk, so data-array latency is irrelevant.
    dataAccessLatency = 0
    tagAccessLatency = 1


class HNFCache(RubyCache):
    # end-to-end calibrated 2026-07-06: measured 38.4ns load-to-use (EMR)
    dataAccessLatency = 64
    tagAccessLatency = 2
