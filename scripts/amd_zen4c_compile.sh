#!/usr/bin/env bash
set -e

# repo 루트 (이 스크립트는 <repo>/scripts/ 안에 있음)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUILD=build_amd_zen4_PF
SCONS="python3.11 $(which scons)"

# gem5 v25.x는 kconfig 기반 빌드. 최초 1회 build 디렉토리를 초기화하고
# 프로토콜을 MOESI_AMD_4th_PF로 설정한다 (build_opts/X86 기본은 MESI_Two_Level).
# kconfig 결과는 $BUILD/gem5.build/config 에 저장됨 (gitignore 대상).
if [ ! -f "$BUILD/gem5.build/config" ]; then
    $SCONS defconfig "$BUILD" build_opts/X86
    $SCONS setconfig "$BUILD" \
        PROTOCOL=MOESI_AMD_4th_PF \
        RUBY_PROTOCOL_MESI_Two_Level=n \
        RUBY_PROTOCOL_MOESI_AMD_4th_PF=y
fi

$SCONS "$BUILD/gem5.opt" -j"$(nproc)"
