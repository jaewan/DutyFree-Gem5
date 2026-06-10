#!/usr/bin/env bash
set -e

# repo 루트 (이 스크립트는 <repo>/scripts/ 안에 있음)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCONS="python3.11 $(which scons)"

# gem5 v25.x는 kconfig 기반 빌드. 최초 1회 build 디렉토리를 초기화하고
# 프로토콜을 CHI로 설정한다 (build_opts/X86 기본은 MESI_Two_Level).
# 16/20-way LLC를 위해 NUMBER_BITS_PER_SET=256으로 확장한다.
# kconfig 결과는 $BUILD/gem5.build/config 에 저장됨 (gitignore 대상).
for BUILD in build_Intel_8462Y build_Intel_8592; do
    if [ ! -f "$BUILD/gem5.build/config" ]; then
        $SCONS defconfig "$BUILD" build_opts/X86
        $SCONS setconfig "$BUILD" \
            PROTOCOL=CHI \
            RUBY_PROTOCOL_MESI_Two_Level=n \
            RUBY_PROTOCOL_CHI=y \
            NUMBER_BITS_PER_SET=256
    fi
    $SCONS "$BUILD/gem5.opt" -j"$(nproc)"
done
