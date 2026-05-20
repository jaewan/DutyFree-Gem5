#!/usr/bin/env bash
set -e

python3.11 $(which scons) build_pf/gem5.opt PROTOCOL=MOESI_AMD_4th_PF -j$(nproc)
