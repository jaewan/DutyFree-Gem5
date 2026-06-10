# INSTALL — DutyFree-Gem5 (MOESI_AMD_4th_PF)

AMD Zen 4c **Directory Tax** 현상을 gem5로 재현하고, PF/LLC bypass(STREAMING)로 제거하는 실험 환경 설치 가이드.

대상 OS: **CentOS / Rocky / AlmaLinux 9** (RHEL 9 계열). 다른 배포판은 패키지 이름만 바꾸면 됨.

전체 흐름:

```
0. 시스템/빌드 환경 준비   (Python 3.11 + scons)
        ↓
1. 소스 받기              (git clone + 브랜치 체크아웃)
        ↓
2. 컴파일                 scripts/amd_zen4c_compile.sh
        ↓
3. 테스트케이스 빌드       make -C testcase/...
        ↓
4. 실험 실행              scripts/amd_zen4c_main_testcases.sh
```

> 모든 스크립트는 **자신의 위치를 기준으로 repo 루트를 찾으므로**, 어느 디렉토리에서 호출해도 동작한다. 절대경로 하드코딩은 없다.

---

## 0. 시스템 / 빌드 환경 준비

### 0.1 시스템 패키지

```bash
# 저장소 활성화
sudo dnf install -y epel-release
sudo dnf config-manager --set-enabled crb        # Rocky/Alma/Stream 9
# CentOS 8 계열이면: sudo dnf config-manager --set-enabled powertools

# 빌드 도구 + 라이브러리
sudo dnf groupinstall -y "Development Tools"
sudo dnf install -y \
    gcc-c++ git m4 automake autoconf \
    zlib-devel \
    protobuf-devel protobuf-compiler \
    gperftools-devel \
    boost-devel \
    hdf5-devel libpng-devel \
    capstone-devel \
    ncurses-devel
```

### 0.2 Python 3.11

```bash
sudo dnf install -y python3.11 python3.11-devel python3.11-pip

python3.11 --version
python3.11-config --includes      # Python.h 경로가 출력되어야 함
```

### 0.3 SCons + kconfiglib

```bash
python3.11 -m pip install --user scons kconfiglib

echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
# gem5가 시스템 기본 python 대신 3.11을 쓰도록 강제
echo 'export PYTHON_CONFIG=python3.11-config'   >> ~/.bashrc
source ~/.bashrc

which scons          # ~/.local/bin/scons 로 잡혀야 함
echo "$PYTHON_CONFIG"  # python3.11-config
```

---

## 1. 소스 받기

```bash
git clone git@github.com:jaewan/DutyFree-Gem5.git
cd DutyFree-Gem5

# PF / Directory Tax 실험 브랜치로 전환
git checkout moesi_amd_zen_4c_pf
```

이 브랜치에는 다음이 모두 포함되어 있다:

- `MOESI_AMD_4th_PF` 프로토콜 (ProbeFilter, targeted probe)
- PF bypass (`gem5_set_streaming` M5OP) / LLC bypass (`--llc-streaming-bypass`)
- CXL/DRAM latency 분리 (`--cxl-latency`, `--dram-latency`, `mem_pool_id`)

→ 따라서 **단일 빌드 하나로 모든 실험 기능을 쓸 수 있다.** (예전의 `build_amd_zen4_PF_CXL_latency` 별도 빌드는 불필요)

---

## 2. 컴파일

```bash
./scripts/amd_zen4c_compile.sh
```

내부적으로 실행하는 것:

```bash
python3.11 $(which scons) build_amd_zen4_PF/gem5.opt PROTOCOL=MOESI_AMD_4th_PF -j$(nproc)
```

결과물: **`build_amd_zen4_PF/gem5.opt`**

> 빌드는 코어 수와 디스크 속도에 따라 수십 분 걸릴 수 있다. 검증:
> ```bash
> ./build_amd_zen4_PF/gem5.opt --version
> ```

### (참고) MOESI_AMD_Base 기본 프로토콜만 빌드하려면

PF 없이 베이스 프로토콜을 보려면 수동으로:

```bash
python3.11 $(which scons) defconfig build_moesi build_opts/X86
python3.11 $(which scons) menuconfig build_moesi      # PROTOCOL=MOESI_AMD_Base 선택
python3.11 $(which scons) build_moesi/gem5.opt -j$(nproc)
```

---

## 3. 테스트케이스 빌드

C 워크로드(victim / aggressor / dummy 등)를 정적 바이너리로 컴파일한다.

```bash
make -C testcase/coherence    # coherence 정합성 6종
make -C testcase/latency      # 캐시 계층 latency 측정
make -C testcase/dirtax       # Directory Tax: victim / aggressor / dummy
make -C testcase/dutyfree     # STREAMING(PF/LLC bypass)용 victim / aggressor / dummy
```

컴파일 옵션은 각 `Makefile`에 `gcc -O1 -static -march=x86-64`로 고정되어 있다.
(`dutyfree/aggressor`는 `gem5_set_streaming`을 호출해 streaming line을 PF/LLC에서 우회시킨다.)

---

## 4. 실험 실행

### 4.1 기본/정합성/probe 확인 (선택)

```bash
./scripts/amd_zen4c_basic_test.sh      # hello + coherence 6종, 결과 logs/basic/
./scripts/amd_zen4c_latency_test.sh    # L1/L2/MEM latency, 결과 logs/latency/
./scripts/amd_zen4c_probe_test.sh      # broadcast vs targeted probe, 결과 logs/probe/
```

### 4.2 메인 실험 — Directory Tax + bypass (Case A~H)

```bash
# 케이스 하나만 (권장: 자원 부담 적음)
./scripts/amd_zen4c_main_testcases.sh B

# 결과만 다시 집계 (이미 실행된 로그에서 TSV 생성)
./scripts/amd_zen4c_main_testcases.sh results

# 전체 (A~H) — 주의: 케이스당 9개 gem5 프로세스를 병렬로 띄운다
./scripts/amd_zen4c_main_testcases.sh all
```

각 케이스는 3개 variant × 3개 배치 = **9개 gem5 run**을 띄운다:

- variant: `baseline` / `pfbypass`(PF 우회) / `pfbypass_llc`(PF+LLC 우회)
- 배치: `victim_only` / `diff_L3`(aggressor가 다른 CorePair) / `same_L3`(같은 CCX)

설정 (스크립트 내장): O3CPU×4, 3.1GHz, L1D 256KiB/a8, L1I 64KiB/a8, L2 4MiB/a16,
DRAM=75ns(victim, pool 0) / CXL=200ns(aggressor, pool 1).

> ⚠️ `all`은 8케이스 × 9 = 최대 72개 O3CPU 프로세스를 동시에 띄운다. 메모리/CPU가
> 충분하지 않으면 `A`, `B` … 처럼 케이스별로 나눠 실행할 것.

결과:

- 로그: `logs/main_cases/<label>/<variant>/{victim_only,diff_L3,same_L3}/stats.txt`
- 요약: `logs/main_cases/results.tsv` (Table 1 victim slowdown / Table 2 PF replacement / Table 3 L2 miss)

### 4.3 파라미터 탐색 (victim/PF sweep)

```bash
./scripts/amd_zen4c_find_testcase.sh        # 전체 sweep (동시 최대 32 프로세스)
./scripts/amd_zen4c_find_testcase.sh results
```

결과: `logs/find_testcase/results.tsv` (diff_L3 ≤ 2.0 AND same_L3 ≥ 3.0 → ★)

---

## 환경 변수 / 커스터마이즈

- **`GEM5`** — gem5 바이너리 경로 override. 다른 빌드로 돌리고 싶을 때:
  ```bash
  GEM5=/path/to/other/gem5.opt ./scripts/amd_zen4c_main_testcases.sh B
  ```
  (기본값: `<repo>/build_amd_zen4_PF/gem5.opt`)

---

## 기대 결과 (요지)

| 현상 | 측정 |
|------|------|
| Directory Tax 재현 | victim DRAM read **3.26×** 증가 |
| PF bypass | `diff_L3` 슬로다운 **→ 1.00×** (PF_Repl = 0) |
| LLC bypass | `same_L3` 슬로다운 **→ 1.00×** |
| Case B (vic=4M, pf8m/a128) | baseline `same_L3` **4.138×**, bypass로 완전 해소 |

배경/이론은 논문 *"Separate Prefetching from Allocation for Immutable CXL Streams"* 참고.

---

## 트러블슈팅

- **`scons`가 python 2/3.9로 잡힘** → `PYTHON_CONFIG=python3.11-config` 환경변수 확인 (0.3).
- **`Python.h` not found** → `python3.11-devel` 설치 확인.
- **`gem5.opt` 없음 (실험 스크립트 실패)** → 2단계 컴파일을 먼저 수행. 빌드 디렉토리는 `build_amd_zen4_PF`.
- **메모리 부족 / OOM** → `all` 대신 케이스별(`A`,`B`,…) 실행, 또는 동시 실행 수를 줄여라.
- **PF 용량이 예상과 다름** → gem5는 `num_sets = pf_size/(assoc×64B)`를 2의 거듭제곱으로 내림한다.
  `assoc = pf_MB × 16`이면 `num_sets=1024`로 정확히 동작.
