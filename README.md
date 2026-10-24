# Common IPs

A collection of reusable RTL IPs for learning and practicing digital hardware design, with local simulation, synthesis, and static timing analysis flows.

## IPs

| Name                                     | Description                                            |  Status |
| ---------------------------------------- | ------------------------------------------------------ | :-----: |
| [sync_fifo](ip/sync_fifo/)               | Synchronous single-clock FIFO                          |  Active |
| gray_fifo                                | Asynchronous FIFO using Gray-coded pointers            | Ongoing |
| [async_ring_fifo](ip/async_ring_fifo/)   | Asynchronous ring-buffer FIFO using token/status slots |  Active |
| [clk_gate](ip/clk_gate/)                 | Clock gating cell                                      |  Active |
| [clk_div](ip/clk_div/)                   | Programmable runtime clock divider                     |  Active |
| [clk_mux](ip/clk_mux/)                   | Glitch-free clock source multiplexer                   |  Active |
| [synchronizer](ip/synchronizer/)         | Generic level synchronizer across clock domains        |  Active |
| [pulse_sync](ip/pulse_sync/)             | Pulse/event synchronization across clock domains       |  Active |
| [rr_arbiter](ip/rr_arbiter/)             | Round-robin arbiter                                    |  Active |
| [wdt](ip/wdt/)                           | Watchdog timer with three clock domains                |  Active |
| [async_apb_bridge](ip/async_apb_bridge/) | APB transaction bridge across clock domains            |  Active |

## Quick Start

Clone the repository and build the local toolchain and reference libraries:

```bash
git clone https://github.com/ddbTran/Common-IP
cd Common-IP
source set_env.sh
make build
```

See each IP directory for its RTL, documentation, and available simulation and synthesis flows.

## License

Original code and documentation in this repository are licensed under the [MIT License](LICENSE).
Third-party tools, Nangate45 libraries, and third-party reference materials retain their respective licenses.
