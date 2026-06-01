import math

from common import FileSystemConfig

import m5
from m5.defines import buildEnv
from m5.objects import *
from m5.util import addToPath

from .Ruby import (
    create_topology,
    send_evicts,
)

addToPath("../")

from topologies.Cluster import Cluster
from topologies.Crossbar import Crossbar


class CntrlBase:
    _seqs = 0

    @classmethod
    def seqCount(cls):
        CntrlBase._seqs += 1
        return CntrlBase._seqs - 1

    _cntrls = 0

    @classmethod
    def cntrlCount(cls):
        CntrlBase._cntrls += 1
        return CntrlBase._cntrls - 1

    _version = 0

    @classmethod
    def versionCount(cls):
        cls._version += 1
        return cls._version - 1


class L1DCache(RubyCache):
    resourceStalls = False

    def create(self, options):
        self.size = MemorySize(options.l1d_size)
        self.assoc = options.l1d_assoc
        self.replacement_policy = TreePLRURP()


class L1ICache(RubyCache):
    resourceStalls = False

    def create(self, options):
        self.size = MemorySize(options.l1i_size)
        self.assoc = options.l1i_assoc
        self.replacement_policy = TreePLRURP()


class L2Cache(RubyCache):
    resourceStalls = False

    def create(self, options):
        self.size = MemorySize(options.l2_size)
        self.assoc = options.l2_assoc
        self.replacement_policy = TreePLRURP()


class CPCntrl(MOESI_AMD_4th_PF_CorePair_Controller, CntrlBase):
    def create(self, options, ruby_system, system):
        self.version = self.versionCount()

        self.L1Icache = L1ICache()
        self.L1Icache.create(options)
        self.L1D0cache = L1DCache()
        self.L1D0cache.create(options)
        self.L1D1cache = L1DCache()
        self.L1D1cache.create(options)
        self.L2cache = L2Cache()
        self.L2cache.create(options)

        self.sequencer = RubySequencer(ruby_system=ruby_system)
        self.sequencer.version = self.seqCount()
        self.sequencer.dcache = self.L1D0cache
        self.sequencer.ruby_system = ruby_system
        self.sequencer.coreid = 0
        self.sequencer.is_cpu_sequencer = True

        self.sequencer1 = RubySequencer(ruby_system=ruby_system)
        self.sequencer1.version = self.seqCount()
        self.sequencer1.dcache = self.L1D1cache
        self.sequencer1.ruby_system = ruby_system
        self.sequencer1.coreid = 1
        self.sequencer1.is_cpu_sequencer = True

        self.mandatory_queue_latency = 2
        self.l2_hit_latency = options.l2_latency
        self.llc_streaming_bypass = options.llc_streaming_bypass
        self.issue_latency = options.cpu_to_dir_latency
        self.send_evictions = send_evicts(options)
        self.ruby_system = ruby_system

        if options.recycle_latency:
            self.recycle_latency = options.recycle_latency


class DirCntrl(MOESI_AMD_4th_PF_Directory_Controller, CntrlBase):
    def create(self, options, dir_ranges, ruby_system, system):
        self.version = self.versionCount()
        self.response_latency = 30
        self.addr_ranges = dir_ranges
        self.directory = RubyDirectoryMemory(
            block_size=ruby_system.block_size_bytes
        )

        self.ProbeFilterMemory = RubyCache(
            size=MemorySize(getattr(options, "pf_size", "2MiB")),
            assoc=int(getattr(options, "pf_assoc", 16)),
            tagAccessLatency=1,
            dataAccessLatency=1,
            resourceStalls=False,
            replacement_policy=TreePLRURP(),
        )

        self.number_of_TBEs = options.num_tbes
        self.ruby_system = ruby_system

        if options.recycle_latency:
            self.recycle_latency = options.recycle_latency


def define_options(parser):
    parser.add_argument("--num-subcaches", type=int, default=4)
    parser.add_argument("--cpu-to-dir-latency", type=int, default=15)
    parser.add_argument(
        "--no-resource-stalls", action="store_false", default=True
    )
    parser.add_argument("--num-tbes", type=int, default=256)
    parser.add_argument("--l2-latency", type=int, default=9)
    parser.add_argument("--pf-size", type=str, default="2MiB", dest="pf_size")
    parser.add_argument("--pf-assoc", type=int, default=16, dest="pf_assoc")
    parser.add_argument(
        "--llc-streaming-bypass",
        action="store_true",
        default=False,
        dest="llc_streaming_bypass",
        help="STREAMING lines bypass L2 (LLC): L1D <-> Memory only",
    )
    parser.add_argument(
        "--cxl-mem-size",
        type=str,
        default="0",
        dest="cxl_mem_size",
        help="Size of CXL memory range appended above DRAM (0=disabled). "
        "Processes with mem_pool_id=1 allocate from this range.",
    )
    parser.add_argument(
        "--dram-latency",
        type=str,
        default="75ns",
        dest="dram_latency",
        help="SimpleMemory latency for the DRAM range (pool 0)",
    )
    parser.add_argument(
        "--cxl-latency",
        type=str,
        default="200ns",
        dest="cxl_latency",
        help="SimpleMemory latency for the CXL range (pool 1)",
    )
    # Override common cache defaults to match AMD Zen 4c
    parser.set_defaults(
        l1d_size="32KiB",
        l1d_assoc=8,
        l1i_size="64KiB",
        l1i_assoc=8,
        l2_size="16MiB",
        l2_assoc=16,
    )


def create_system(
    options, full_system, system, dma_devices, bootmem, ruby_system, cpus=None
):
    if buildEnv["PROTOCOL"] != "MOESI_AMD_4th_PF":
        m5.util.panic("This script requires the MOESI_AMD_4th_PF protocol.")

    cpu_sequencers = []
    l1_cntrl_nodes = []
    dir_cntrl_nodes = []

    mainCluster = Cluster(extBW=512, intBW=512)

    if options.numa_high_bit:
        numa_bit = options.numa_high_bit
    else:
        dir_bits = int(math.log(options.num_dirs, 2))
        block_size_bits = int(math.log(options.cacheline_size, 2))
        numa_bit = block_size_bits + dir_bits - 1

    for i in range(options.num_dirs):
        dir_ranges = []
        for r in system.mem_ranges:
            addr_range = m5.objects.AddrRange(
                r.start,
                size=r.size(),
                intlvHighBit=numa_bit,
                intlvBits=dir_bits,
                intlvMatch=i,
            )
            dir_ranges.append(addr_range)

        dir_cntrl = DirCntrl()
        dir_cntrl.create(options, dir_ranges, ruby_system, system)

        dir_cntrl.requestFromCores = MessageBuffer(ordered=True)
        dir_cntrl.requestFromCores.in_port = ruby_system.network.out_port

        dir_cntrl.responseFromCores = MessageBuffer()
        dir_cntrl.responseFromCores.in_port = ruby_system.network.out_port

        dir_cntrl.unblockFromCores = MessageBuffer()
        dir_cntrl.unblockFromCores.in_port = ruby_system.network.out_port

        dir_cntrl.probeToCore = MessageBuffer()
        dir_cntrl.probeToCore.out_port = ruby_system.network.in_port

        dir_cntrl.responseToCore = MessageBuffer()
        dir_cntrl.responseToCore.out_port = ruby_system.network.in_port

        dir_cntrl.triggerQueue = MessageBuffer(ordered=True)

        dir_cntrl.requestToMemory = MessageBuffer()
        dir_cntrl.responseFromMemory = MessageBuffer()

        exec("system.dir_cntrl%d = dir_cntrl" % i)
        dir_cntrl_nodes.append(dir_cntrl)
        mainCluster.add(dir_cntrl)

    assert (options.num_cpus % 2) == 0

    cpuCluster = Cluster(extBW=512, intBW=512)
    for i in range((options.num_cpus + 1) // 2):
        cp_cntrl = CPCntrl()
        cp_cntrl.create(options, ruby_system, system)

        exec("system.cp_cntrl%d = cp_cntrl" % i)
        cpu_sequencers.extend([cp_cntrl.sequencer, cp_cntrl.sequencer1])

        cp_cntrl.requestFromCore = MessageBuffer()
        cp_cntrl.requestFromCore.out_port = ruby_system.network.in_port

        cp_cntrl.responseFromCore = MessageBuffer()
        cp_cntrl.responseFromCore.out_port = ruby_system.network.in_port

        cp_cntrl.unblockFromCore = MessageBuffer()
        cp_cntrl.unblockFromCore.out_port = ruby_system.network.in_port

        cp_cntrl.probeToCore = MessageBuffer()
        cp_cntrl.probeToCore.in_port = ruby_system.network.out_port

        cp_cntrl.responseToCore = MessageBuffer()
        cp_cntrl.responseToCore.in_port = ruby_system.network.out_port

        cp_cntrl.mandatoryQueue = MessageBuffer()
        cp_cntrl.triggerQueue = MessageBuffer(ordered=True)

        cpuCluster.add(cp_cntrl)

    if not full_system:
        for i in range((options.num_cpus + 1) // 2):
            FileSystemConfig.register_cpu(
                physical_package_id=0,
                core_siblings=range(options.num_cpus),
                core_id=i * 2,
                thread_siblings=[],
            )
            FileSystemConfig.register_cpu(
                physical_package_id=0,
                core_siblings=range(options.num_cpus),
                core_id=i * 2 + 1,
                thread_siblings=[],
            )
            FileSystemConfig.register_cache(
                level=0,
                idu_type="Instruction",
                size=options.l1i_size,
                line_size=options.cacheline_size,
                assoc=options.l1i_assoc,
                cpus=[i * 2, i * 2 + 1],
            )
            FileSystemConfig.register_cache(
                level=0,
                idu_type="Data",
                size=options.l1d_size,
                line_size=options.cacheline_size,
                assoc=options.l1d_assoc,
                cpus=[i * 2],
            )
            FileSystemConfig.register_cache(
                level=0,
                idu_type="Data",
                size=options.l1d_size,
                line_size=options.cacheline_size,
                assoc=options.l1d_assoc,
                cpus=[i * 2 + 1],
            )
            FileSystemConfig.register_cache(
                level=1,
                idu_type="Unified",
                size=options.l2_size,
                line_size=options.cacheline_size,
                assoc=options.l2_assoc,
                cpus=[i * 2, i * 2 + 1],
            )

    assert len(dma_devices) == 0

    mainCluster.add(cpuCluster)
    ruby_system.network.number_of_virtual_networks = 10

    # Split mem_ranges into [DRAM, CXL] when --cxl-mem-size is given.
    # setup_memory_controllers (called after us in Ruby.create_system) will
    # create one SimpleMemory per range; Ruby.py then sets per-range latency.
    cxl_size_str = getattr(options, "cxl_mem_size", "0")
    if cxl_size_str not in ("0", "0B", "0GiB", "0MiB"):
        from m5.util.convert import toMemorySize

        cxl_bytes = int(toMemorySize(cxl_size_str))
        total_bytes = system.mem_ranges[0].size()
        dram_bytes = total_bytes - cxl_bytes
        assert dram_bytes > 0, "cxl-mem-size >= mem-size"
        system.mem_ranges = [
            m5.objects.AddrRange(0, size=dram_bytes),
            m5.objects.AddrRange(dram_bytes, size=cxl_bytes),
        ]

    return (cpu_sequencers, dir_cntrl_nodes, mainCluster)
