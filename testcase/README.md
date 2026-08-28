# Test Cases for MOESI_AMD_Base

gem5 SE mode test suite for MOESI_AMD_Base protocol validation and performance measurement.
Requires `gem5.opt` built with MOESI_AMD_Base protocol

## Directory Layout
coherence/ | coherence_tests | Cache coherence correctness (6 test cases) |
latency/ | latency_bench | Cache hierarchy latency via pointer-chase |
dirtax/ | victim, aggressor, dummy | Directory tax interference experiment |

## Build

```bash
make -C testcase/coherence
make -C testcase/latency
make -C testcase/dirtax
```

## Run

### coherence_tests

Runs 6 cases: invalidation, sharing, ping-pong, O-state, false-sharing, atomic RMW.

```bash
build_moesi/gem5.opt configs/deprecated/example/se.py \
  --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 \
  --l1d_size=32kB --l1i_size=32kB --l2_size=512kB --l3_size=16MB \
  -c testcase/coherence/coherence_tests -o "" \
  2>&1 | grep -E "PASS|FAIL|INFO|done"
```

### latency_bench

```
Usage: latency_bench <N> <step> <iters> <mode:r|w> <flush_n>
```

```bash
build_moesi/gem5.opt configs/deprecated/example/se.py \
  --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 \
  --l1d_size=32kB --l1i_size=32kB --l2_size=512kB --l3_size=16MB \
  -c testcase/latency/latency_bench \
  -o "32768 20219 4096 r 12288" \
  2>&1 | grep "Exiting @ tick"
# ticks/iter = tick / 4096
```

### dirtax (victim / aggressor)

Use `dummy` to fill the second slot of a CorePair so victim and aggressors land in separate CorePairs.

```bash
# baseline
build_moesi/gem5.opt configs/deprecated/example/se.py \
  --ruby --cpu-type=TimingSimpleCPU --num-cpus=2 \
  --l1d_size=32kB --l1i_size=32kB --l2_size=512kB --l3_size=16MB \
  -c testcase/dirtax/victim 2>&1 | grep "Exiting @ tick"

# victim + 1 aggressor (CPU 0=victim, 1=dummy, 2=aggressor, 3=dummy)
build_moesi/gem5.opt configs/deprecated/example/se.py \
  --ruby --cpu-type=TimingSimpleCPU --num-cpus=4 \
  --l1d_size=32kB --l1i_size=32kB --l2_size=512kB --l3_size=16MB \
  -c "testcase/dirtax/victim;testcase/dirtax/dummy;testcase/dirtax/aggressor;testcase/dirtax/dummy" \
  -o ";;;" 2>&1 | grep "Exiting @ tick"

# victim + 3 aggressors
build_moesi/gem5.opt configs/deprecated/example/se.py \
  --ruby --cpu-type=TimingSimpleCPU --num-cpus=8 \
  --l1d_size=32kB --l1i_size=32kB --l2_size=512kB --l3_size=16MB \
  -c "testcase/dirtax/victim;testcase/dirtax/dummy;testcase/dirtax/aggressor;testcase/dirtax/dummy;testcase/dirtax/aggressor;testcase/dirtax/dummy;testcase/dirtax/aggressor;testcase/dirtax/dummy" \
  -o ";;;;;;;" 2>&1 | grep "Exiting @ tick"
```
