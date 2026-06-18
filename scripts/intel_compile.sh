#!/usr/bin/env bash
set -e

# === build_Intel_8462Y ===
python3.11 $(which scons) defconfig build_Intel_8462Y build_opts/X86
python3.11 $(which scons) setconfig build_Intel_8462Y PROTOCOL=CHI RUBY_PROTOCOL_MESI_Two_Level=n RUBY_PROTOCOL_CHI=y NUMBER_BITS_PER_SET=256
python3.11 $(which scons) build_Intel_8462Y/gem5.opt -j$(nproc)

# === build_Intel_8592 ===
python3.11 $(which scons) defconfig build_Intel_8592 build_opts/X86
python3.11 $(which scons) setconfig build_Intel_8592 PROTOCOL=CHI RUBY_PROTOCOL_MESI_Two_Level=n RUBY_PROTOCOL_CHI=y NUMBER_BITS_PER_SET=256
python3.11 $(which scons) build_Intel_8592/gem5.opt -j$(nproc)
