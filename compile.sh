#!/usr/bin/env bash
set -e

python3.11 $(which scons) build_amd_zen4_PF/gem5.opt PROTOCOL=MOESI_AMD_4th_PF -j$(nproc)
