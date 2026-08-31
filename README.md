# Common IPs

A reusable RTL IP repository for digital hardware design.

The repository provides small, technology-independent building blocks commonly required in SoC, interconnect, and chiplet-oriented designs, together with a reproducible open-source verification and synthesis flow.

## Coverage

The repository currently covers the following IP categories:

```text
common_ip/
├── fifo/
│   ├── sync_fifo/
│   ├── gray_fifo/
│   └── ring_fifo/
│
├── clock/
│   ├── clk_div/
│   └── clk_mux/
│
├── reset/
│   └── reset_handshake/
│
├── cdc/
│   ├── sync/
│   ├── rst_sync/
│   ├── 2phase_hs/
│   ├── 4phase_hs/
│   ├── pulse_sync/
│   └── pulse_expand/
│
├── control/
│   ├── rr_arbiter/
│   ├── credit_counter/
│   └── token_bucket/
│
└── interface/
    └── apb_slave/
```

The IP set is organized around common digital-design infrastructure:

* **FIFO** — buffering and clock-domain data movement
* **Clock** — basic clock manipulation and selection
* **Reset** — reset sequencing and coordination
* **CDC** — clock-domain crossing primitives and handshakes
* **Control** — arbitration, credit-based flow control, and rate limiting
* **Interface** — standard peripheral/interface building blocks

The repository is intentionally composed of **small, composable IPs** rather than large subsystem-level blocks.

## Current Status

The repository is currently under active development.

### IP status

The repository structure defines the target IP coverage shown above. At the moment, the **synchronous FIFO (`sync_fifo`) is the currently integrated IP flow**, with the common environment already exposing:

```bash
SYNC_FIFO_HOME="${IP_HOME}/sync_fifo"
```

The remaining IP directories represent the planned/common-IP structure and are progressively implemented and validated.

### Toolchain status

A reproducible local toolchain is provided for:

| Tool      | Purpose                                       |
| --------- | --------------------------------------------- |
| Verilator | RTL simulation and waveform generation        |
| Surfer    | Waveform inspection                           |
| Yosys     | RTL synthesis                                 |
| ABC       | Logic optimization used by the synthesis flow |
| OpenSTA   | Static timing analysis                        |
| Nangate45 | Reference standard-cell timing library        |

Tool versions are centrally pinned in:

```text
scripts/tool_versions.sh
```

This avoids relying on whatever version happens to be installed on the host system.

### Flow status

The repository already provides:

* environment setup
* pinned tool versions
* automated toolchain build
* tool verification
* Nangate45 library setup
* reusable simulation template
* reusable synthesis + STA template
* per-IP output and log directories

The synthesis template runs:

```text
RTL
 │
 ▼
Yosys
 │
 ▼
Gate-level netlist
 │
 ▼
OpenSTA
 │
 ▼
Timing reports
```

and treats timing violations as a failed run.

## Repository Layout

```text
common_ips/
│
├── ip/
│   ├── sync_fifo/
│   │   ├── rtl/
│   │   ├── sim/
│   │   └── syn/
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

The exact IP tree will grow as individual IPs are implemented.

## Environment Setup

From the repository root:

```bash
source set_env.sh
```

This initializes:

```text
COMMON_IPS_HOME
IP_HOME
TOOL_HOME
LIB_HOME
```

and the individual tool/library variables.

It also adds the locally built tools to `PATH`.

For example:

```bash
yosys -V
sta -version
verilator --version
```

should resolve to the versions maintained by this repository.

## Build the Toolchain

The complete toolchain can be built with:

```bash
make build
```

This performs:

1. Development dependency installation
2. Verilator build
3. Surfer build
4. Yosys build
5. OpenSTA build, including CUDD
6. Tool verification
7. Nangate45 library setup

The build is designed to be **idempotent**. Already-built pinned versions are skipped.

Individual stages can also be rebuilt:

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

## Using an IP

Each IP should be self-contained under:

```text
ip/<ip_name>/
```

A typical IP contains:

```text
ip/<ip_name>/
├── rtl/
├── sim/
└── syn/
```

### RTL

RTL sources belong in:

```text
ip/<ip_name>/rtl/
```

A filelist should define the RTL compilation order.

For example:

```text
ip/<ip_name>/rtl/filelist.f
```

### Simulation

The simulation flow uses Verilator.

The reusable template is:

```text
ip/template/sim/run_sim.sh
```

For a new IP, copy the simulation directory:

```bash
cp -r ip/template/sim ip/<ip_name>/sim
```

Then configure:

```bash
IP_HOME="${<IP_NAME>_HOME}"
TOP_MODULE="<testbench_top>"
```

and provide:

```text
ip/<ip_name>/sim/filelist_sim.f
```

After sourcing the environment:

```bash
source set_env.sh
./ip/<ip_name>/sim/run_sim.sh
```

Simulation output is generated under:

```text
ip/<ip_name>/sim/out/
```

The Verilator flow enables FST waveform tracing, which can be inspected using Surfer.

## Synthesis and STA

The reusable synthesis template is:

```text
ip/template/syn/
```

For a new IP:

```bash
cp -r ip/template/syn ip/<ip_name>/syn
```

Configure the IP-specific top module and environment variable in:

```text
ip/<ip_name>/syn/run_syn.sh
```

For example:

```bash
SYN_TOP="sync_fifo"
IP_HOME="${SYNC_FIFO_HOME}"
```

The synthesis filelist is:

```text
ip/<ip_name>/syn/filelist_syn.f
```

and timing constraints are specified in:

```text
ip/<ip_name>/syn/constraints.sdc
```

Then run:

```bash
source set_env.sh
./ip/<ip_name>/syn/run_syn.sh
```

The flow performs:

```text
Yosys synthesis
      │
      ▼
netlist.v
      │
      ▼
OpenSTA
      │
      ▼
timing analysis
```

Outputs are placed in:

```text
ip/<ip_name>/syn/outputs/
```

Logs are placed in:

```text
ip/<ip_name>/syn/logs/
```

The synthesis flow fails if:

* the RTL filelist is missing
* the SDC file is missing
* Yosys is unavailable
* OpenSTA is unavailable
* synthesis does not produce a netlist
* OpenSTA exits with an error
* timing violations are detected

This makes the synthesis + STA flow suitable for repeatable local runs and CI integration.

## Adding a New IP

The intended workflow is:

```text
1. Create ip/<ip_name>/
2. Add RTL
3. Add rtl/filelist.f
4. Add simulation flow
5. Add simulation filelist
6. Add synthesis flow
7. Add syn/filelist_syn.f
8. Add constraints.sdc
9. Register <IP_NAME>_HOME in set_env.sh
10. Run simulation
11. Run synthesis + STA
```

For example:

```bash
export NEW_IP_HOME="${IP_HOME}/new_ip"
```

The IP-specific scripts should then reference:

```bash
${NEW_IP_HOME}
```

rather than hard-coding repository paths.

## Design Philosophy

The repository follows several principles:

* **Small IPs** — each block should solve one well-defined hardware problem.
* **Reusable RTL** — avoid technology-specific implementation wherever possible.
* **Self-contained IP flows** — simulation and synthesis configuration live with the IP.
* **Reproducible tools** — tool versions are pinned centrally.
* **Automated verification** — simulation and timing analysis should be executable from scripts.
* **Fail-fast flows** — missing configuration and timing violations should terminate the run.
* **Technology-aware validation** — synthesis and STA use the Nangate45 reference library.
* **Composable architecture** — individual primitives can be combined into larger protocols and subsystems.

## License

License information will be added when the repository license is finalized.

