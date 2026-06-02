#!/usr/bin/env bash
set -e

ROOT=/home/naivete/DutyFree-Gem5-pakeunji

# Intel 8462Y+ (Sapphire Rapids) — NUMBER_BITS_PER_SET=256
python3.11 $(which scons) $ROOT/build_Intel_8462Y/gem5.opt -j$(nproc)

# Intel 8592+ (Emerald Rapids) — NUMBER_BITS_PER_SET=256
python3.11 $(which scons) $ROOT/build_Intel_8592/gem5.opt -j$(nproc)
