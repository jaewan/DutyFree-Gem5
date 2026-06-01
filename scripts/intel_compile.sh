#!/usr/bin/env bash
set -e

python3.11 $(which scons) defconfig build_X86_CHI build_opts/X86_CHI
python3.11 $(which scons) build_X86_CHI/gem5.opt -j$(nproc)
