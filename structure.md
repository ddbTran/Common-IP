# Common IP Repository Architecture

## Repository Structure

```text
common_ips/
├── Makefile
├── README.md
├── coding_style.md
├── set_env.sh
│
└── ip/
    └── sync_fifo/
        ├── docs/
        ├── rtl/
        │   ├── filelist.f
        │   └── sync_fifo.sv
        ├── sim/
        │   ├── filelist_sim.f
        │   ├── run_sim.sh
        │   ├── tb_sync_fifo.sv
        │   └── out/
        └── syn/
```

## Repository-Level Components

### `Makefile`

The root `Makefile` manages repository-level tasks only.

Typical responsibilities:

```text
make build
make check
make clean
```

It does **not** dispatch IP-specific simulation or synthesis flows.

IP flows are executed directly inside the corresponding IP directory.

### `set_env.sh`

`set_env.sh` is the single source of truth for repository and IP paths.

Example:

```bash
#!/usr/bin/env bash

export COMMON_IPS_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export SYNC_FIFO_HOME="${COMMON_IPS_HOME}/ip/sync_fifo"
```

When a new IP is added, its environment variable is added here:

```bash
export ASYNC_FIFO_HOME="${COMMON_IPS_HOME}/ip/async_fifo"
```

The environment is loaded with:

```bash
source set_env.sh
```

Scripts and filelists use these environment variables instead of discovering their own paths.

## IP Structure

Each directory under `ip/` represents one independent reusable IP.

```text
ip/<ip_name>/
├── docs/
├── rtl/
├── sim/
└── syn/
```

### `rtl/`

Contains synthesizable RTL and the RTL filelist.

```text
rtl/
├── <ip_name>.sv
└── filelist.f
```

Paths in the filelist use the corresponding IP environment variable.

Example:

```text
${SYNC_FIFO_HOME}/rtl/sync_fifo.sv
```

### `sim/`

Contains the complete functional simulation flow.

```text
sim/
├── filelist_sim.f
├── run_sim.sh
├── tb_<ip_name>.sv
└── out/
```

`run_sim.sh` is IP-specific and uses the environment variable defined in `set_env.sh`.

Example:

```bash
#!/usr/bin/env bash
set -e

cd "${SYNC_FIFO_HOME}/sim"

mkdir -p out

verilator \
    --binary \
    --timing \
    -sv \
    -f filelist_sim.f \
    --top-module tb_sync_fifo \
    --Mdir out/obj_dir \
    -o tb_sync_fifo

./out/obj_dir/tb_sync_fifo
```

The simulation flow is run directly from the IP:

```bash
cd ip/sync_fifo/sim
./run_sim.sh
```

### `syn/`

Contains the complete synthesis flow for the IP.

```text
syn/
├── filelist_syn.f
├── run_syn.sh
└── constraints.sdc
```

The synthesis script uses the corresponding environment variable:

```bash
cd "${SYNC_FIFO_HOME}/syn"
```

Generated synthesis artifacts are kept in generated-output directories and are not committed unless explicitly designated as release artifacts.

### `docs/`

Contains IP-specific documentation, including:

* Specification
* Interface description
* Block diagram
* Configuration
* Integration instructions
* Verification information
* Synthesis information

## Environment Convention

The repository uses environment variables as the common path interface between tools and scripts.

```text
set_env.sh
    │
    ├── COMMON_IPS_HOME
    │
    ├── SYNC_FIFO_HOME
    │       │
    │       ├── rtl/filelist.f
    │       ├── sim/filelist_sim.f
    │       ├── sim/run_sim.sh
    │       └── syn/run_syn.sh
    │
    └── ASYNC_FIFO_HOME
            │
            └── ...
```

The responsibilities are deliberately separated:

| Component    | Responsibility                      |
| ------------ | ----------------------------------- |
| `set_env.sh` | Repository/IP paths and environment |
| `filelist.f` | RTL source composition              |
| `run_sim.sh` | Simulation flow                     |
| `run_syn.sh` | Synthesis flow                      |
| `Makefile`   | Repository-level build/setup        |
| `docs/`      | IP documentation                    |

## Design Principles

### 1. IPs are self-contained

Each IP owns its:

* RTL
* Verification
* Simulation flow
* Synthesis flow
* Documentation

### 2. Environment is centralized

Paths are defined once in `set_env.sh`.

Scripts do not independently discover or reconstruct repository paths.

### 3. IP-specific flows stay inside the IP

Simulation:

```bash
cd ip/sync_fifo/sim
./run_sim.sh
```

Synthesis:

```bash
cd ip/sync_fifo/syn
./run_syn.sh
```

The root `Makefile` does not act as a universal IP command dispatcher.

### 4. Avoid unnecessary abstraction

The repository does not introduce top-level `scripts/`, `src/`, `tb/`, `results/`, or other shared directories unless a real shared requirement appears.

### 5. Generated output is not source

Simulation and synthesis output directories are generated artifacts.

For example:

```text
sim/out/
syn/out/
```

They should be gitignored.

## Frozen Baseline

```text
common_ips/
├── Makefile
├── README.md
├── coding_style.md
├── set_env.sh
└── ip/
    └── <ip_name>/
        ├── docs/
        ├── rtl/
        ├── sim/
        └── syn/
```

The architecture intentionally favors **explicit conventions over generic scripting**.

An IP-specific script may explicitly reference its own environment variable and top module. It does not need to dynamically discover its IP name or directory structure.

