# INSTALL — DutyFree-Gem5 (Intel CHI: 8462Y+ / 8592+)
# git branch : intel_streaming_tax

## 0. System dependencies

### CentOS / Rocky / Alma 9

```bash
sudo dnf install -y epel-release
sudo dnf config-manager --set-enabled crb        # CentOS 8 derivatives: powertools
sudo dnf groupinstall -y "Development Tools"
sudo dnf install -y gcc-c++ git m4 automake autoconf zlib-devel \
    protobuf-devel protobuf-compiler gperftools-devel boost-devel \
    hdf5-devel libpng-devel capstone-devel ncurses-devel
sudo dnf install -y python3.11 python3.11-devel python3.11-pip
```

### Ubuntu / Debian

```bash
sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository -y ppa:deadsnakes/ppa      # for python3.11
sudo apt update
sudo apt install -y build-essential git m4 automake autoconf zlib1g-dev \
    libprotobuf-dev protobuf-compiler libgoogle-perftools-dev libboost-all-dev \
    libhdf5-dev libpng-dev libcapstone-dev libncurses-dev \
    python3.11 python3.11-dev python3.11-venv
python3.11 -m ensurepip --upgrade
```

## Setup (before compile)

```bash
python3.11 -m pip install --user scons kconfiglib
export PATH="$HOME/.local/bin:$PATH"
export PYTHON_CONFIG=python3.11-config
```

## Compile

Build **both** targets (8462Y and 8592). The first run also initialises the
kconfig build dirs (CHI protocol + `NUMBER_BITS_PER_SET=256`); later runs rebuild.

```bash
./scripts/intel_compile.sh              # kconfig init (first run) + build 8462Y + 8592
make -C testcase/dirtax                 # victim / aggressor (WB) / dummy
make -C testcase/dutyfree               # STREAMING aggressor variant
```

## Run

Combined DirTax + STREAMING scripts (one per platform × CPU count). Each runs
`alone` / `with_agg` (WB, LLC fill) / `with_streaming` (LLC bypass) per victim WSS,
and writes its TSV into `logs/<name>/results_<name>.tsv`.

```bash
# 8462Y+ (Sapphire Rapids, 2.8GHz, LLC slice 2MiB)
./scripts/intel_8462y_2cpu_dirtax_streaming.sh        # 2 CPU, agg = 4×LLC, full WSS sweep
./scripts/intel_8462y_4cpu_dirtax_streaming.sh        # 4 CPU, agg = 4×LLC, full WSS sweep
./scripts/intel_8462y_8cpu_dirtax_streaming.sh        # 8 CPU, agg = 2×LLC, 53% WSS only

# 8592+ (Emerald Rapids, 1.9GHz, LLC slice 5MiB)
./scripts/intel_8592_2cpu_dirtax_streaming.sh
./scripts/intel_8592_4cpu_dirtax_streaming.sh
./scripts/intel_8592_8cpu_dirtax_streaming.sh

# results only (re-read stats.txt without re-running)
./scripts/intel_8462y_4cpu_dirtax_streaming.sh results
