# Common IPs

A reusable RTL IP repository for digital hardware design.

## 1. Reason

### Repository

This repository provides a collection of small, reusable, and technology-independent RTL IPs for common digital hardware design needs.

The IPs are intended to serve as building blocks for larger systems such as:

* SoCs
* Interconnects
* Chiplets
* Communication and control subsystems

The repository also provides a reproducible local flow for RTL simulation, synthesis, and static timing analysis.

### Aim

The aim is to build a consistent and reusable environment where each IP can be:

```text
Designed
   │
   ▼
Verified
   │
   ▼
Synthesized
   │
   ▼
Timing analyzed
```

Each IP should be independently usable and should follow the same development and validation conventions.

### Goal

The long-term goal is to provide a reliable collection of common RTL building blocks that can be reused across hardware projects without rebuilding the same infrastructure from scratch.

The repository is also intended to make IP development reproducible by keeping:

* RTL
* simulation
* synthesis
* timing constraints
* tool versions
* library setup

under a consistent repository structure.

### Philosophy

The repository follows several principles:

* **Small and focused** — each IP should solve one well-defined hardware problem.
* **Reusable** — IPs should be parameterized where appropriate and independent of a specific system.
* **Technology-independent RTL** — avoid technology-specific implementation in the RTL whenever possible.
* **Self-contained** — each IP contains the information and scripts required to verify and synthesize it.
* **Reproducible** — tool versions and technology libraries are explicitly managed.
* **Consistent** — all IPs should follow the same basic RTL, simulation, and synthesis conventions.
* **Fail-fast** — invalid configurations and failed verification steps should be detected as early as possible.
* **Composable** — small IPs should be usable as building blocks for larger designs.

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

### 3.1 Repository Structure

The repository is organized into three main areas:

```text
common_ips/
│
├── ip/
│   ├── <ip_name>/
│   │   ├── doc/
│   │   ├── rtl/
│   │   ├── sim/
│   │   └── syn/
│   │
│   └── template/
│       ├── sim/
│       └── syn/
│
├── libs/
│   └── nangate45/
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

Each IP is isolated under:

```text
ip/<ip_name>/
```

and normally contains:

```text
ip/<ip_name>/
├── doc/
├── rtl/
├── sim/
└── syn/
```

The `template/` directory provides the starting point for new IP flows.

---

### 3.2 Build

Clone the repository:

```bash
git clone https://github.com/ddbTran/Common-IP
cd Common-IP
```

Initialize the repository environment:

```bash
source set_env.sh
```

Build the complete local toolchain:

```bash
make build
```

The build includes:

* Verilator
* Surfer
* Yosys
* ABC
* OpenSTA
* required dependencies
* Nangate45 reference libraries

The build is designed to be idempotent, so already-built components are skipped.

After building, verify the environment:

```bash
yosys -V
verilator --version
sta -version
```

The repository should resolve these tools from its local `tool/` directory rather than depending on system-installed versions.

---

### 3.3 Develop

New IP development should start from the repository template.

Create the IP directory:

```bash
mkdir -p ip/<ip_name>
```

The expected structure is:

```text
ip/<ip_name>/
├── doc/
│   └──IP_<ip_name>.pdf
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

The reusable templates can be copied:

```bash
cp -r ip/template/sim ip/<ip_name>/sim
cp -r ip/template/syn ip/<ip_name>/syn
```

Then implement the following components.

#### RTL

Add the synthesizable RTL under:

```text
ip/<ip_name>/rtl/
```

and define the source order in:

```text
ip/<ip_name>/rtl/filelist.f
```

The RTL should be:

* synthesizable
* technology-independent
* parameterized where appropriate
* documented at the interface level

#### Simulation

Add the testbench under:

```text
ip/<ip_name>/sim/
```

and define the simulation sources in:

```text
filelist_sim.f
```

The simulation flow should use Verilator and should provide a clear pass/fail result.

Waveform tracing may be enabled for debugging and inspected using Surfer.

#### Synthesis

Add the synthesis configuration under:

```text
ip/<ip_name>/syn/
```

The synthesis filelist is:

```text
filelist_syn.f
```

and timing constraints are specified in:

```text
constraints.sdc
```

The synthesis flow should produce a gate-level netlist and run timing analysis using the repository's Nangate45 reference library.

---

### 3.4 IP Environment

Each IP should expose a repository environment variable when needed.

For example:

```bash
export SYNC_FIFO_HOME="${IP_HOME}/sync_fifo"
```

A new IP should follow the same convention:

```bash
export <IP_NAME>_HOME="${IP_HOME}/<ip_name>"
```

IP-specific scripts should use the corresponding environment variable instead of hard-coding absolute repository paths.

---

### 3.5 Development Flow

The expected development flow for an IP is:

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
                    │  SS / TT / FF│
                    └──────────────┘
```

For each IP, the expected validation sequence is:

```text
1. Implement RTL
2. Run simulation
3. Fix functional failures
4. Run synthesis
5. Check generated netlist
6. Run STA
7. Check timing results
8. Update IP status
```

---

### 3.6 Contributing

To contribute a new IP:

1. Create `ip/<ip_name>/`
2. Implement the RTL
3. Add `rtl/filelist.f`
4. Add a Verilator testbench
5. Add `sim/filelist_sim.f`
6. Add `sim/run_sim.sh`
7. Add `syn/filelist_syn.f`
8. Add `syn/constraints.sdc`
9. Add `syn/run_syn.sh`
10. Register `<IP_NAME>_HOME` in `set_env.sh`
11. Run simulation
12. Run synthesis and STA
13. Update the IP status table

A contribution should follow the repository's existing structure and conventions.

The goal is that another developer can enter:

```text
ip/<ip_name>/
```

and immediately understand:

* what the IP does
* where the RTL is
* how to simulate it
* how to synthesize it
* how timing is constrained
* where the generated results are stored

---

## License

License information will be added when the repository license is finalized.

