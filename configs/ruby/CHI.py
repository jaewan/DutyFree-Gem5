# Copyright (c) 2021, 2024 Arm Limited
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

import os

import m5
from m5.defines import buildEnv
from m5.objects import *

from .Ruby import create_topology


def define_options(parser):
    parser.add_argument(
        "--chi-config",
        action="store",
        type=str,
        default=None,
        help="NoC config. parameters and bindings. "
        "Required for CustomMesh topology",
    )
    parser.add_argument("--enable-dvm", default=False, action="store_true")
    parser.add_argument(
        "--cxl-mem-size",
        type=str,
        default="0",
        dest="cxl_mem_size",
        help="Size of CXL memory range above DRAM (0=disabled). "
        "Processes with mem_pool_id=1 allocate from this range.",
    )
    parser.add_argument(
        "--dram-latency",
        type=str,
        default="100ns",
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
    parser.add_argument(
        "--split-mem-ctlr",
        default=False,
        action="store_true",
        dest="split_mem_ctlr",
        help="One SNF per memory range (DRAM SNF = iMC, CXL SNF = CXL root "
        "port), each directly attached to its own memory device. HNFs (LLC) "
        "stay shared and route per address. Models Intel SPR: shared CHA, "
        "separate memory paths below it. Requires --num-dirs=1.",
    )


def read_config_file(file):
    """Read file as a module and return it"""
    import importlib.machinery
    import types

    loader = importlib.machinery.SourceFileLoader("chi_configs", file)
    chi_configs = types.ModuleType(loader.name)
    loader.exec_module(chi_configs)
    return chi_configs


# ---------------------------------------------------------------- Intel CAT
# pqos syntax, so a configuration moves between here and a real machine
# unchanged:
#     pqos -e "llc:1=0x00ff;llc:2=0x3f00"     HNF_CAT_E
#     pqos -a "llc:1=0;llc:2=1,2,3"           HNF_CAT_A
# Cores no association names stay in COS 0, which pqos -R defines as every way.
def _cat_parse_e(spec, assoc):
    cos = {}
    for item in spec.split(";"):
        item = item.strip()
        if not item:
            continue
        res, rest = item.split(":", 1)
        if res.strip() != "llc":
            m5.fatal("HNF_CAT_E: only 'llc' is modelled, got '%s'", res)
        cid, mask = rest.split("=", 1)
        m = int(mask.strip(), 16)
        if m == 0:
            m5.fatal("HNF_CAT_E: COS%s mask is empty; CAT faults on that", cid)
        if m >> assoc:
            m5.fatal(
                "HNF_CAT_E: COS%s mask %#x exceeds %d ways", cid, m, assoc
            )
        # Classic CAT requires a contiguous CBM and #GPs otherwise; newer parts
        # relax it behind CPUID.10H.1:ECX[2]. Refusing it keeps every
        # configuration reproducible on hardware without that bit.
        low = m & -m
        if (m + low) & (m + low - 1):
            m5.fatal("HNF_CAT_E: COS%s mask %#x is not contiguous", cid, m)
        cos[int(cid)] = m
    return cos


def _cat_parse_a(spec):
    assoc = {}
    for item in spec.split(";"):
        item = item.strip()
        if not item:
            continue
        res, rest = item.split(":", 1)
        if res.strip() != "llc":
            m5.fatal("HNF_CAT_A: only 'llc' is modelled, got '%s'", res)
        cid, cores = rest.split("=", 1)
        for tok in cores.split(","):
            tok = tok.strip()
            if not tok:
                continue
            if "-" in tok:
                lo, hi = (int(x) for x in tok.split("-", 1))
            else:
                lo = hi = int(tok)
            for c in range(lo, hi + 1):
                assoc[c] = int(cid)
    return assoc


def _cat_apply(ruby_system, cpus):
    spec_e = os.environ.get("HNF_CAT_E", "")
    spec_a = os.environ.get("HNF_CAT_A", "")
    if not spec_e and not spec_a:
        return
    llc_assoc = int(ruby_system.hnf[0]._cntrl.cache.assoc)

    # Way partitioning hands the replacement policy a candidate list narrowed
    # to the requestor's ways, so the policy has to be one that picks out of
    # the list it is given. Only TreePLRU does not. Checked against the policy
    # object rather than HNF_RP so RubyCache's own default is caught too.
    #
    # DRRIP is deliberately allowed: real Intel LLCs run an adaptive
    # set-dueling policy and CAT at the same time -- Vila et al. (PLDI'20)
    # located Skylake's leader sets while using CAT to cut L3 associativity to
    # 4 -- so partitioning only the non-adaptive policies would model a
    # combination nobody ships. Leader sets are partitioned like every other
    # set, which is what keeps them representative of the followers.
    _rp_name = type(
        ruby_system.hnf[0]._cntrl.cache.replacement_policy
    ).__name__
    if _rp_name == "TreePLRURP":
        m5.fatal(
            "HNF_CAT_* cannot be used with TreePLRU: it computes a way from "
            "a per-set bit tree and then indexes the candidate list with "
            "that way number, so a partial list lands on the wrong entry or "
            "past its end"
        )

    cos = _cat_parse_e(spec_e, llc_assoc)
    core2cos = _cat_parse_a(spec_a)
    if len(cos) > 16:
        m5.fatal("HNF_CAT_E: %d classes; CAT gives 16", len(cos))
    cos.setdefault(0, (1 << llc_assoc) - 1)
    for c in set(core2cos.values()):
        if c not in cos:
            m5.fatal("HNF_CAT_A: COS%d has no mask in HNF_CAT_E", c)

    # way_masks is indexed by the requestor's Cache-controller version, and the
    # L2s sit after every L1, so the offset moves with the core count. Ask each
    # controller for its own number rather than computing one.
    vers = [int(cpu.l2.version) for cpu in cpus]
    vec = [0] * (max(vers) + 1)
    for i, v in enumerate(vers):
        vec[v] = cos[core2cos.get(i, 0)]
    for hnf in ruby_system.hnf:
        hnf._cntrl.cache.way_masks = vec

    print("L3CA COS definitions:")
    for c in sorted(cos):
        print(
            "    L3CA COS%d => MASK %#07x (%2d ways)"
            % (c, cos[c], bin(cos[c]).count("1"))
        )
    print("Core association:")
    for i, v in enumerate(vers):
        print(
            "    Core %d => COS%d   (requestor v%d, mask %#07x)"
            % (i, core2cos.get(i, 0), v, vec[v])
        )


def create_system(
    options, full_system, system, dma_ports, bootmem, ruby_system, cpus
):
    if buildEnv["PROTOCOL"] != "CHI":
        m5.panic("This script requires the CHI build")

    if options.num_dirs < 1:
        m5.fatal("--num-dirs must be at least 1")

    if options.num_l3caches < 1:
        m5.fatal("--num-l3caches must be at least 1")

    if full_system and options.enable_dvm:
        if len(cpus) <= 1:
            m5.fatal("--enable-dvm can't be used with a single CPU")
        for cpu in cpus:
            for decoder in cpu.decoder:
                decoder.dvm_enabled = True

    # read specialized classes from config file if provided
    if options.chi_config:
        chi_defs = read_config_file(options.chi_config)
    elif options.topology == "CustomMesh":
        m5.fatal("--noc-config must be provided if topology is CustomMesh")
    else:
        # Use the defaults from CHI_config
        from . import CHI_config as chi_defs

    # NoC params
    params = chi_defs.NoC_Params
    # Node types
    CHI_RNF = chi_defs.CHI_RNF
    CHI_HNF = chi_defs.CHI_HNF
    CHI_MN = chi_defs.CHI_MN
    CHI_SNF_MainMem = chi_defs.CHI_SNF_MainMem
    CHI_SNF_BootMem = chi_defs.CHI_SNF_BootMem
    CHI_RNI_DMA = chi_defs.CHI_RNI_DMA
    CHI_RNI_IO = chi_defs.CHI_RNI_IO

    # Use HNFCache from chi_defs if defined (per-platform latency), else default
    if hasattr(chi_defs, "HNFCache"):
        _HNFBase = chi_defs.HNFCache
    else:
        _HNFBase = RubyCache

    class HNFCache(_HNFBase):
        size = options.l3_size
        assoc = options.l3_assoc

    # LLC replacement policy. RubyCache's default is TreePLRURP, which inserts
    # at MRU and so has no thrash/scan resistance at all; env LLC_RP selects an
    # RRIP variant instead. Unset (or "plru") keeps the default exactly.
    #   srrip = RRIPRP  (BRRIP with btp=100: every fill inserted at "long")
    #   brrip = BRRIPRP (btp=3: bimodal, mostly "distant")
    #   drrip = DRRIPRP (set-dueling between the two)
    # LLC_RP_HP=0 switches RRIP hit promotion from HP (reset to 0) to FP
    # (decrement), for a sensitivity run.
    _llc_rp = os.environ.get("LLC_RP", "plru").lower()
    if _llc_rp not in ("plru", "srrip", "brrip", "drrip"):
        m5.fatal(f"unknown LLC_RP '{_llc_rp}' (plru|srrip|brrip|drrip)")
    if _llc_rp != "plru":
        _hp = bool(int(os.environ.get("LLC_RP_HP", 1)))
        if _llc_rp == "srrip":
            HNFCache.replacement_policy = RRIPRP(hit_priority=_hp)
        elif _llc_rp == "brrip":
            HNFCache.replacement_policy = BRRIPRP(hit_priority=_hp)
        else:
            # DuelingMonitor::initEntry() walks replacement data in the order
            # CacheMemory instantiates it, which is set-major, so team_size =
            # assoc keeps each leader a whole set. LLC_RP_LEADERS leader sets
            # per team; a cache with few sets needs a smaller number, or every
            # set becomes a leader and there are no followers left to steer.
            from m5.util.convert import toMemorySize

            _leaders = int(os.environ.get("LLC_RP_LEADERS", 32))
            _sets = int(toMemorySize(options.l3_size)) // (
                options.cacheline_size * options.l3_assoc
            )
            if _sets < 2 * _leaders:
                m5.fatal(
                    f"LLC has {_sets} sets; DRRIP with {_leaders} leader sets "
                    f"per team leaves no followers. Lower LLC_RP_LEADERS."
                )
            HNFCache.replacement_policy = DRRIPRP(
                constituency_size=(_sets // _leaders) * options.l3_assoc,
                team_size=options.l3_assoc,
                replacement_policy_a=BRRIPRP(hit_priority=_hp),
                replacement_policy_b=RRIPRP(hit_priority=_hp),
            )
        print(f"CHI: LLC replacement policy = {_llc_rp} (hit_priority={_hp})")

    # other functions use system.cache_line_size assuming it has been set
    assert system.cache_line_size.value == options.cacheline_size

    cpu_sequencers = []
    mem_cntrls = []
    mem_dests = []
    network_nodes = []
    network_cntrls = []
    hnf_dests = []
    all_cntrls = []

    # Creates on RNF per cpu with priv l2 caches
    assert len(cpus) == options.num_cpus

    rnf_cb = getattr(system, "_rnf_gen", CHI_RNF.generate)

    # Generate the Request Nodes
    ruby_system.rnf = rnf_cb(options, ruby_system, cpus)

    for rnf in ruby_system.rnf:
        cpu_sequencers.extend(rnf.getSequencers())
        all_cntrls.extend(rnf.getAllControllers())
        network_nodes.append(rnf)
        network_cntrls.extend(rnf.getNetworkSideControllers())

    mn_cb = getattr(system, "_mn_gen", CHI_MN.generate)

    # Generate the Misc Nodes
    ruby_system.mn = mn_cb(options, ruby_system, cpus)

    for mn in ruby_system.mn:
        all_cntrls.extend(mn.getAllControllers())
        network_nodes.append(mn)
        network_cntrls.extend(mn.getNetworkSideControllers())
        assert mn.getAllControllers() == mn.getNetworkSideControllers()

    # Look for other memories
    other_memories = []
    if bootmem:
        other_memories.append(bootmem)
    if getattr(system, "sram", None):
        other_memories.append(getattr(system, "sram", None))
    on_chip_mem_ports = getattr(system, "_on_chip_mem_ports", None)
    if on_chip_mem_ports:
        other_memories.extend([p.simobj for p in on_chip_mem_ports])

    # Create the LLCs cntrls
    sysranges = [] + system.mem_ranges

    for m in other_memories:
        sysranges.append(m.range)

    # Split mem_ranges into [DRAM..., CXL] early so HNF/SNF creation uses
    # correct ranges. The CXL region is carved off the top of the *last*
    # range: SE keeps the old [DRAM, CXL] split of its single range, and FS
    # (which already has [0,3GB) + [4GiB,...) around the PCI hole) becomes
    # [0,3GB) + [4GiB,X) + [X,...) matching the boot checkpoint's carve in
    # fs.py, so physmem backing stores line up at restore.
    cxl_size_str = getattr(options, "cxl_mem_size", "0")
    if cxl_size_str not in ("0", "0B", "0GiB", "0MiB"):
        from m5.util.convert import toMemorySize

        cxl_bytes = int(toMemorySize(cxl_size_str))
        last = system.mem_ranges[-1]
        dram_bytes = last.size() - cxl_bytes
        assert dram_bytes > 0, "cxl-mem-size >= last mem range"
        system.mem_ranges = list(system.mem_ranges[:-1]) + [
            m5.objects.AddrRange(last.start, size=dram_bytes),
            m5.objects.AddrRange(last.start + dram_bytes, size=cxl_bytes),
        ]

    hnf_list = [i for i in range(options.num_l3caches)]
    CHI_HNF.createAddrRanges(sysranges, system.cache_line_size.value, hnf_list)

    ruby_system.hnf = [
        CHI_HNF(i, ruby_system, HNFCache, None)
        for i in range(options.num_l3caches)
    ]

    _cat_apply(ruby_system, cpus)

    for hnf in ruby_system.hnf:
        network_nodes.append(hnf)
        network_cntrls.extend(hnf.getNetworkSideControllers())
        assert hnf.getAllControllers() == hnf.getNetworkSideControllers()
        all_cntrls.extend(hnf.getAllControllers())
        hnf_dests.extend(hnf.getAllControllers())

    # Create the memory controllers
    # Notice we don't define a Directory_Controller type so we don't use
    # create_directories shared by other protocols.

    # --split-mem-ctlr: one SNF per memory range (DRAM=iMC, CXL=CXL port).
    # HNF creation above is untouched → LLC stays shared; each HNF routes to
    # the owning SNF per address via mapAddressToDownstreamMachine (ranges
    # are disjoint). Memory devices are bound in setup_memory_controllers.
    n_snf = options.num_dirs
    if getattr(options, "split_mem_ctlr", False):
        if options.num_dirs != 1:
            m5.fatal("--split-mem-ctlr requires --num-dirs=1")
        n_snf = len(system.mem_ranges)

    ruby_system.snf = [
        CHI_SNF_MainMem(ruby_system, None, None) for i in range(n_snf)
    ]
    for snf in ruby_system.snf:
        network_nodes.append(snf)
        network_cntrls.extend(snf.getNetworkSideControllers())
        assert snf.getAllControllers() == snf.getNetworkSideControllers()
        mem_cntrls.extend(snf.getAllControllers())
        all_cntrls.extend(snf.getAllControllers())
        mem_dests.extend(snf.getAllControllers())

    if len(other_memories) > 0:
        ruby_system.rom_snf = [
            CHI_SNF_BootMem(ruby_system, None, m) for m in other_memories
        ]
        for snf in ruby_system.rom_snf:
            network_nodes.append(snf)
            network_cntrls.extend(snf.getNetworkSideControllers())
            all_cntrls.extend(snf.getAllControllers())
            mem_dests.extend(snf.getAllControllers())

    # Creates the controller for dma ports and io

    if len(dma_ports) > 0:
        ruby_system.dma_rni = [
            CHI_RNI_DMA(ruby_system, dma_port, None) for dma_port in dma_ports
        ]
        for rni in ruby_system.dma_rni:
            network_nodes.append(rni)
            network_cntrls.extend(rni.getNetworkSideControllers())
            all_cntrls.extend(rni.getAllControllers())

    if full_system:
        ruby_system.io_rni = CHI_RNI_IO(ruby_system, None)
        network_nodes.append(ruby_system.io_rni)
        network_cntrls.extend(ruby_system.io_rni.getNetworkSideControllers())
        all_cntrls.extend(ruby_system.io_rni.getAllControllers())

    # Assign downstream destinations
    for rnf in ruby_system.rnf:
        rnf.setDownstream(hnf_dests)
    if len(dma_ports) > 0:
        for rni in ruby_system.dma_rni:
            rni.setDownstream(hnf_dests)
    if full_system:
        ruby_system.io_rni.setDownstream(hnf_dests)
    for hnf in ruby_system.hnf:
        hnf.setDownstream(mem_dests)

    # Setup data message size for all controllers
    for cntrl in all_cntrls:
        cntrl.data_channel_size = params.data_width

    # Network configurations
    # virtual networks: 0=request, 1=snoop, 2=response, 3=data
    ruby_system.network.number_of_virtual_networks = 4

    ruby_system.network.control_msg_size = params.cntrl_msg_size
    ruby_system.network.data_msg_size = params.data_width
    if options.network == "simple":
        ruby_system.network.buffer_size = params.router_buffer_size

    # Incorporate the params into options so it's propagated to
    # makeTopology and create_topology the parent scripts
    for k in dir(params):
        if not k.startswith("__"):
            setattr(options, k, getattr(params, k))

    if options.topology == "CustomMesh":
        topology = create_topology(network_nodes, options)
    elif options.topology in ["Crossbar", "Pt2Pt"]:
        topology = create_topology(network_cntrls, options)
    else:
        m5.fatal(f"{options.topology} not supported!")

    return (cpu_sequencers, mem_cntrls, topology)
