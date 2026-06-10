#!/usr/bin/env bash
set -e

# repo 루트 (이 스크립트는 <repo>/scripts/ 안에 있음)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3.11 $(which scons) build_amd_zen4_PF/gem5.opt PROTOCOL=MOESI_AMD_4th_PF -j$(nproc)
