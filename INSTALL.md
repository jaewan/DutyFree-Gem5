# INSTALL — DutyFree-Gem5 (MOESI_AMD_4th_PF)
# git branch : moesi_amd_zen_4c_pf

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

```bash
./scripts/amd_zen4c_compile.sh          # kconfig init (first run) + build
make -C testcase/dirtax                 # victim / aggressor / dummy
make -C testcase/dutyfree               # STREAMING variants
```

## Run

```bash
./scripts/amd_zen4c_main_testcases.sh B        # single case
./scripts/amd_zen4c_main_testcases.sh all      # all cases (A-H)
./scripts/amd_zen4c_main_testcases.sh results  # aggregate -> logs/main_cases/results.tsv
```
