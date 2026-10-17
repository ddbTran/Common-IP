# Asynchronous Ring FIFO

> Transfers data between independent clock domains using a ring of storage slots with synchronized per-slot status bits.

| Item    | Value    |
| ------- | -------- |
| Version | v1.0     |
| Author  | Dat Tran |
| Date    | Oct 2026 |

## 1. Overview

The asynchronous ring FIFO buffers data between a producer and a consumer operating in independent clock domains. Per-slot write and read status bits track ownership and prevent overwriting unread data or reading an unavailable word.

### 1.1 Features

* Independent write and read clocks
* Configurable data width and FIFO depth
* Per-slot status transfer through two-stage synchronizers
* Write ready and read valid handshakes, with full and empty flags
* First-Word Fall-Through (FWFT) / show-ahead read data
* Active-low asynchronous resets for both clock domains
* Supports arbitrary FIFO depths.

## 2. Architecture

### 2.1 Block Diagram

To be added.

### 2.2 IO Ports

| Port        | Direction | Description                                            |
| ----------- | --------- | -------------------------------------------------------|
| `clk_wr_i`  | input     | Write clock                                            |
| `rst_wr_ni` | input     | Active-low asynchronous write-domain reset             |
| `clk_rd_i`  | input     | Read clock                                             |
| `rst_rd_ni` | input     | Active-low asynchronous read-domain reset              |
| `wr_data_i` | input     | Write data, `WIDTH` bits                               |
| `wren_i`    | input     | Write request in the write clock domain                |
| `full_o`    | output    | Current write slot is unavailable, write clock domain  |
| `ready_o`   | output    | Write can be accepted; low during write reset          |
| `rd_data_o` | output    | Current read word, `WIDTH` bits; meaningful when valid |
| `rden_i`    | input     | Read request in the read clock domain                  |
| `empty_o`   | output    | Current read slot is unavailable, read clock domain    |
| `valid_o`   | output    | Read data is available; low during read reset          |

### 2.3 Parameters

| Parameter | Default | Description                                 |
| --------- | ------: | --------------------------------------------|
| `WIDTH`   |      32 | Data width; must be greater than 0          |
| `DEPTH`   |       8 | Number of storage slots; must be at least 2 |

## 3. Functional Description

### 3.1 Write Operation

A write is accepted on the rising edge of `clk_wr_i` when both `wren_i` and `ready_o` are high. The FIFO stores `wr_data_i` in the selected slot, toggles its write status bit, and advances the slot selection around the ring.

`full_o` asserts when the selected write slot still contains unread data according to the synchronized read status. `ready_o = rst_wr_ni & ~full_o`. Requests while `ready_o` is low do not modify the FIFO.

### 3.2 Read Operation

The FIFO provides show-ahead data through a combinational read multiplexer. When `valid_o` is high, `rd_data_o` contains the next word. A read is accepted on the rising edge of `clk_rd_i` when both `rden_i` and `valid_o` are high. The FIFO then toggles the slot's read status bit and advances to the next slot.

`empty_o` asserts when the selected read slot has no unread data according to the synchronized write status. `valid_o = rst_rd_ni & ~empty_o`. Requests while `valid_o` is low do not advance the FIFO. Ignore `rd_data_o` whenever `valid_o` is low.

### 3.3 Clock-Domain Crossing

Write status bits pass through a two-stage synchronizer into the read domain. Read status bits pass through another two-stage synchronizer into the write domain. Slot selection and status updates remain local to their respective domains.

Stored data remains in its slot until the consumer reads it and the read status returns to the producer. The data bus does not pass through bitwise synchronizers. Status synchronization delays visibility of new data and freed slots, so `full_o` and `empty_o` can remain asserted temporarily after a transfer in the opposite domain.

### 3.4 Reset

Assert `rst_wr_ni` and `rst_rd_ni` together to reset the FIFO. Reset clears both status rings and their synchronizers, returning slot selection to the first slot. The FIFO becomes empty, and `ready_o` and `valid_o` are low while their respective resets are asserted.

Reset discards pending data logically; the storage registers are not reset. Independent reset of one domain while retaining the other domain's state is not supported. Release each reset safely relative to its local clock and resume traffic after both domains leave reset.

## 4. Usage

### 4.1 Integration Guide

Connect `clk_wr_i`, `rst_wr_ni`, `wr_data_i`, and `wren_i` to the producer domain. Use `ready_o` to determine when a write is accepted. Connect `clk_rd_i`, `rst_rd_ni`, `rd_data_o`, and `rden_i` to the consumer domain, using `valid_o` to qualify the read data.

Include both `rtl/async_ring_fifo.sv` and the shared `synchronizer` module in the build. `rtl/filelist.f` includes this dependency. The write and read clocks may have different frequencies and phases.

### 4.2 Operation Guide

1. Reset both domains together.
2. Present write data and assert `wren_i`. Hold the request and data until a rising write-clock edge with `ready_o = 1`.
3. Wait for `valid_o = 1` in the read domain, then sample `rd_data_o` on a rising read-clock edge with `rden_i = 1`.
4. Continue writes and reads independently. Each qualifying clock edge accepts one word, including consecutive edges when requests remain asserted.

## 5. Verification

The self-checking testbench compares accepted reads against an independent queue of accepted writes. The default configuration uses `WIDTH=32`, `DEPTH=8`, a 10 ns write-clock period, a 14 ns read-clock period, and seed 1.

| Test                      | Status | Description                                           |
| ------------------------- | ------ | ----------------------------------------------------- |
| Reset                     | PASS   | Initial reset and reset with pending data              |
| Basic data patterns       | PASS   | Zeros, ones, walking ones, and walking zeros           |
| Partial fill and idle     | PASS   | Retains buffered data across a long idle interval      |
| Full and empty boundaries | PASS   | Fill, drain, blocked writes, and blocked reads         |
| Wrap-around               | PASS   | Repeated ring traversal and slot reuse                 |
| Concurrent traffic        | PASS   | Producer and consumer traffic, including full recovery |
| Random stress             | PASS   | 2,000 transfers with randomized data and request gaps  |
| Clock pause and recovery  | PASS   | Pauses either clock, then resumes operation            |

**Default simulation: 2,282 data comparisons — PASS.** These results cover the default configuration; the testbench also exposes width, depth, and clock timing parameters for additional runs.

## 6. Synthesis

The existing synthesis and timing reports under `syn/` record the following results for `WIDTH=32` and `DEPTH=8`:

| Item            | Value                       |
| --------------- | --------------------------- |
| Library         | Nangate45                   |
| Frequency       | 100 MHz write / 100 MHz read |
| Cell Count      | 1110                        |
| Cell Area       | 2504.656 µm²                |
| Sequential Area | 1412.992 µm²                |
| Setup WNS       | 0.00 ns                     |

## 7. Notes

* The current RTL requires `DEPTH >= 2` because its slot-selection expressions use adjacent status bits.
* Full and empty flags reflect local synchronized status, rather than an instantaneous global occupancy count.
* Data storage uses write-clocked registers and a combinational read multiplexer.
* Physical integration must preserve the status synchronizers and ensure each slot's data settles before its synchronized write status permits consumption.
* Synthesis figures are from existing reports; the recorded hold TNS is negative, so they do not establish a clean hold result.
