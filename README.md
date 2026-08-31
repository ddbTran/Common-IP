# Common IPs

A reusable RTL IP repository for digital hardware design.

## 1. Reason

### Overview

* This repository provides a collection of small, reusable, and technology-independent RTL IPs for common digital hardware design needs.

* The IPs are intended to provide reusable building blocks for digital hardware designs and development projects.

* The repository also provides a reproducible local environment for RTL simulation, synthesis, and static timing analysis.

### Philosophy

The repository follows a simple and consistent approach to IP development:

* **Small and focused** — keep each IP centered around a specific function.
* **Reusable RTL** — prefer parameterized and technology-independent implementations.
* **Consistent structure** — use the same basic layout for RTL, simulation, synthesis, and documentation.
* **Reproducible flow** — keep tool versions and library setup under repository control.
* **Practical validation** — validate each IP through simulation, synthesis, and timing analysis where applicable.

The intended development flow is:

```text
RTL
 │
 ▼
Verify
 │
 ▼
Synthesize
 │
 ▼
Timing Analysis
```

The long-term goal is to build a reliable collection of common RTL building blocks that can be reused across hardware projects without rebuilding the same infrastructure from scratch.

---

## 2. Status

The following table defines the target IP set and its current implementation status.

| Name              | Description                                |   RTL   |   SIM   |   SYN   |
| ----------------- | ------------------------------------------ | :-----: | :-----: | :-----: |
| `sync_fifo`       | Synchronous single-clock FIFO              |   Done  |   Done  |   Done  |
| `gray_fifo`       | FIFO using Gray-coded pointers             | Planned | Planned | Planned |
| `ring_fifo`       | Ring-buffer based FIFO                     | Planned | Planned | Planned |
| `clk_div`         | Programmable clock divider                 | Planned | Planned | Planned |
| `clk_mux`         | Clock source multiplexer                   | Planned | Planned | Planned |
| `reset_handshake` | Reset sequencing and handshake logic       | Planned | Planned | Planned |
| `sync`            | Generic clock-domain synchronizer          | Planned | Planned | Planned |
| `rst_sync`        | Reset synchronizer                         | Planned | Planned | Planned |
| `2phase_hs`       | Two-phase clock-domain crossing handshake  | Planned | Planned | Planned |
| `4phase_hs`       | Four-phase clock-domain crossing handshake | Planned | Planned | Planned |
| `pulse_sync`      | Pulse synchronization across clock domains | Planned | Planned | Planned |
| `pulse_expand`    | Pulse expansion for CDC transfer           | Planned | Planned | Planned |
| `rr_arbiter`      | Round-robin arbiter                        | Planned | Planned | Planned |
| `credit_counter`  | Credit-based flow-control counter          | Planned | Planned | Planned |
| `token_bucket`    | Token-bucket rate limiter                  | Planned | Planned | Planned |
| `apb_slave`       | APB slave interface building block         | Planned | Planned | Planned |

### Status Definition

| Status    | Meaning                                          |
| --------- | ------------------------------------------------ |
| `Planned` | Target IP, implementation not started            |
| `WIP`     | Currently under development                      |
| `Done`    | RTL implemented and corresponding flow completed |
| `N/A`     | Not applicable                                   |

An IP is considered **Done** when its RTL, simulation, and synthesis flow have been implemented and validated.

---

## 3. How to Use

### 3.1 Quick Start

Clone the repository:

```bash
git clone https://github.com/ddbTran/Common-IP
cd Common-IP
```

Initialize the repository environment:

```bash
source set_env.sh
```

Build the complete local development environment:

```bash
make build
```

Verify the installed tools:

```bash
yosys -V
verilator --version
sta -version
```

After setup, an IP can be developed and tested independently under:

```text
ip/<ip_name>/
```

For example, the currently integrated `sync_fifo` flow can be run from its IP directory.

---

### 3.2 Repository Structure

The repository is organized around IPs, reusable templates, locally built tools, technology libraries, and repository-level scripts.

```text
common_ips/
│
├── ip/
│   │
│   ├── <ip_name>/
│   │   ├── doc/
│   │   │   └── IP_<ip_name>.pdf
│   │   │
│   │   ├── rtl/
│   │   │   ├── <ip_name>.sv
│   │   │   └── filelist.f
│   │   │
│   │   ├── sim/
│   │   │   ├── tb_<ip_name>.sv
│   │   │   ├── filelist_sim.f
│   │   │   ├── run_sim.sh
│   │   │   └── out/
│   │   │
│   │   └── syn/
│   │       ├── filelist_syn.f
│   │       ├── constraints.sdc
│   │       ├── run_syn.sh
│   │       ├── outputs/
│   │       └── logs/
│   │
│   └── template/
│       ├── sim/
│       │   └── run_sim.sh
│       │
│       └── syn/
│           └── run_syn.sh
│
├── libs/
│   └── nangate45/
│       ├── nangate45_fast.lib.gz
│       ├── nangate45_typ.lib.gz
│       └── nangate45_slow.lib.gz
│
├── tool/
│   ├── verilator/
│   ├── surfer/
│   ├── yosys/
│   ├── abc/
│   └── OpenSTA/
│
├── scripts/
│   ├── build_tools.sh
│   ├── check_tools.sh
│   ├── setup_libs.sh
│   └── tool_versions.sh
│
├── set_env.sh
├── Makefile
└── README.md
```

#### IP Directory

Each IP is self-contained under:

```text
ip/<ip_name>/
```

The standard structure is:

```text
ip/<ip_name>/
├── doc/
├── rtl/
├── sim/
└── syn/
```

Each directory has a specific responsibility:

| Directory | Purpose                                           |
| --------- | ------------------------------------------------- |
| `doc/`    | IP specification and design documentation         |
| `rtl/`    | Synthesizable RTL and RTL filelist                |
| `sim/`    | Testbench and Verilator simulation flow           |
| `syn/`    | Yosys synthesis, timing constraints, and STA flow |

#### Template

```text
ip/template/
```

contains reusable simulation and synthesis flow templates.

These templates provide the common infrastructure for a new IP and should be copied rather than recreated manually.

#### Libraries

```text
libs/nangate45/
```

contains the Nangate45 reference standard-cell libraries used by the synthesis and timing flows.

The current library set contains:

```text
nangate45_fast.lib.gz
nangate45_typ.lib.gz
nangate45_slow.lib.gz
```

The libraries are provided by the OpenSTA examples and are installed into the repository by `scripts/setup_libs.sh`.

#### Tools

```text
tool/
```

contains locally built versions of the tools used by the repository.

The main tools are:

* Verilator — RTL simulation
* Surfer — waveform inspection
* Yosys — RTL synthesis
* ABC — optimization and technology mapping backend used by Yosys
* OpenSTA — static timing analysis

#### Scripts

```text
scripts/
```

contains repository-level automation such as:

* toolchain building
* tool verification
* library setup
* tool-version management

#### Environment

`set_env.sh` defines repository-wide paths and tool/library environment variables.

IP-specific paths follow the same convention. For example:

```bash
export SYNC_FIFO_HOME="${IP_HOME}/sync_fifo"
```

Scripts should use these environment variables rather than hard-coding absolute paths.

---

### 3.3 Build

The repository uses pinned tool versions defined in:

```text
scripts/tool_versions.sh
```

Build the complete environment with:

```bash
make build
```

The build prepares:

* Verilator
* Surfer
* Yosys
* ABC
* OpenSTA
* required dependencies
* Nangate45 reference libraries

The build is designed to be idempotent. Already-built components are skipped.

Individual tools can also be rebuilt:

```bash
./scripts/build_tools.sh verilator
./scripts/build_tools.sh surfer
./scripts/build_tools.sh yosys
./scripts/build_tools.sh opensta
```

To force a rebuild:

```bash
FORCE_REBUILD=1 ./scripts/build_tools.sh yosys
```

Build logs and stamps are kept under:

```text
tool/.logs/
tool/.stamps/
```

---

### 3.4 Develop

New IP development should start from the repository's templates.

Create the IP directory:

```bash
mkdir -p ip/<ip_name>
```

Then create the standard structure:

```text
ip/<ip_name>/
├── doc/
│   └── IP_<ip_name>.pdf
│
├── rtl/
│   ├── <ip_name>.sv
│   └── filelist.f
│
├── sim/
│   ├── tb_<ip_name>.sv
│   ├── filelist_sim.f
│   └── run_sim.sh
│
└── syn/
    ├── filelist_syn.f
    ├── constraints.sdc
    └── run_syn.sh
```

The simulation and synthesis infrastructure can be copied from the templates:

```bash
cp -r ip/template/sim ip/<ip_name>/sim
cp -r ip/template/syn ip/<ip_name>/syn
```

#### RTL

Add the synthesizable RTL under:

```text
ip/<ip_name>/rtl/
```

and define the RTL compilation order in:

```text
ip/<ip_name>/rtl/filelist.f
```

The RTL should be:

* synthesizable
* technology-independent
* parameterized where appropriate
* consistent with the IP specification

#### Documentation

Add the IP specification under:

```text
ip/<ip_name>/doc/
```

The documentation should describe the IP interface, behavior, parameters, assumptions, and other information required to use the block correctly.

#### Simulation

Add the testbench and simulation configuration under:

```text
ip/<ip_name>/sim/
```

The simulation filelist is:

```text
filelist_sim.f
```

and the flow is executed through:

```text
run_sim.sh
```

The simulation flow uses Verilator and should provide a clear pass/fail result.

Waveform tracing may be enabled for debugging and inspected using Surfer.

Simulation outputs are stored under:

```text
ip/<ip_name>/sim/out/
```

#### Synthesis

Add the synthesis configuration under:

```text
ip/<ip_name>/syn/
```

The synthesis RTL filelist is:

```text
filelist_syn.f
```

Timing constraints are defined in:

```text
constraints.sdc
```

and the synthesis/STA flow is executed through:

```text
run_syn.sh
```

Generated netlists and reports are stored under:

```text
ip/<ip_name>/syn/outputs/
```

while execution logs are stored under:

```text
ip/<ip_name>/syn/logs/
```

---

### 3.5 IP Environment

Each IP should expose a repository environment variable when required by its scripts.

For example:

```bash
export SYNC_FIFO_HOME="${IP_HOME}/sync_fifo"
```

A new IP should follow the same convention:

```bash
export <IP_NAME>_HOME="${IP_HOME}/<ip_name>"
```

IP-specific scripts should reference the corresponding environment variable rather than hard-coding repository paths.

---

### 3.6 Development Flow

The expected development flow is:

```text
                    ┌──────────────┐
                    │     RTL      │
                    └──────┬───────┘
                           │
                           ▼
                    ┌──────────────┐
                    │   Verilator  │
                    │  Simulation  │
                    └──────┬───────┘
                           │
                         PASS
                           │
                           ▼
                    ┌──────────────┐
                    │    Yosys     │
                    │   + ABC      │
                    └──────┬───────┘
                           │
                           ▼
                    ┌──────────────┐
                    │   Netlist    │
                    └──────┬───────┘
                           │
                           ▼
                    ┌──────────────┐
                    │   OpenSTA    │
                    └──────────────┘
```

The expected validation sequence for an IP is:

```text
1. Implement RTL
2. Add/update IP documentation
3. Run simulation
4. Fix functional failures
5. Run synthesis
6. Check the generated netlist
7. Run STA
8. Check timing results
9. Update the IP status
```

---

### 3.7 Contributing

To contribute a new IP:

1. Create `ip/<ip_name>/`
2. Add the IP specification under `doc/`
3. Implement the RTL
4. Add `rtl/filelist.f`
5. Add a Verilator testbench
6. Add `sim/filelist_sim.f`
7. Add `sim/run_sim.sh`
8. Add `syn/filelist_syn.f`
9. Add `syn/constraints.sdc`
10. Add `syn/run_syn.sh`
11. Register `<IP_NAME>_HOME` in `set_env.sh`
12. Run simulation
13. Run synthesis and STA
14. Update the status table

A contribution should follow the repository's existing structure and conventions.

The goal is that another developer can enter:

```text
ip/<ip_name>/
```

and immediately understand:

* what the IP does
* how the IP is specified
* where the RTL is
* how to simulate it
* how to synthesize it
* how timing is constrained
* where generated results and logs are stored

---

## License

License information will be added when the repository license is finalized.

