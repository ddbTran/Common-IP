# Synchronous FIFO

> A synchronous FIFO for temporary data storage between a producer and a consumer operating in the same clock domain.

| Item    | Value        |
| ------- | ------------ |
| Version | v1.0         |
| Author  | Dat Tran Tan |
| Date    | August 2026  |

## 1. Overview

The synchronous FIFO provides temporary data storage between a producer and a consumer operating in the same clock domain. It supports parameterizable data width and FIFO depth.

### 1.1 Features

* Single-clock synchronous FIFO
* Parameterizable data width and depth
* Full and empty status flags with FIFO usage monitoring
* Asynchronous reset and synchronous flush

## 2. Architecture

### 2.1 Block Diagram

The FIFO consists of storage, read and write control, and status logic for managing data transfer between the write source and read destination.

### 2.2 IO Ports

| Port      | Direction | Description        |
| --------- | --------- | ------------------ |
| `clk_i`   | input     | Clock signal       |
| `rst_i`   | input     | Asynchronous reset |
| `push_i`  | input     | Write request      |
| `data_i`  | input     | Write data         |
| `pop_i`   | input     | Read request       |
| `data_o`  | output    | Read data          |
| `full_o`  | output    | FIFO full status   |
| `empty_o` | output    | FIFO empty status  |
| `usage_o` | output    | FIFO occupancy     |

### 2.3 Parameters

| Parameter    | Default | Description |
| ------------ | ------: | ----------- |
| `DATA_WIDTH` |      32 | Data width  |
| `DEPTH`      |      16 | FIFO depth  |

## 3. Functional Description

The synchronous FIFO provides temporary storage between a write source and a read destination operating in the same clock domain. Data is written when `push_i` is asserted and the FIFO is not full, and is read when `pop_i` is asserted and the FIFO is not empty.

### 3.1 Write Operation

A write operation is performed on the rising edge of `clk_i` when `push_i` is asserted and `full_o` is deasserted. The input data on `data_i` is stored at the current write location.

### 3.2 Read Operation

The FIFO implements First-Word Fall-Through (FWFT) / show-ahead behavior. When not empty, the next data is available on `data_o`. Assert `pop_i` to consume the current data word on the rising edge of `clk_i`.

### 3.3 Reset Behavior

Asynchronous assertion of `rst_i` resets the FIFO state, including the read and write pointers and status indicators. After reset, the FIFO is empty.

A synchronous flush clears the FIFO contents and restores the FIFO to the empty state on the rising edge of `clk_i`.

The `full_o` and `empty_o` outputs indicate whether the FIFO can accept a write or provide a read, respectively. The `usage_o` output indicates the current FIFO occupancy.

## 4. Usage

### 4.1 Integration Guide

Connect `clk_i` to the system clock and `rst_i` to the asynchronous reset. Connect `data_i` and `push_i` to the write source, and `data_o` and `pop_i` to the read destination.

Use `full_o` to indicate that the FIFO cannot accept additional data, `empty_o` to indicate that no data is available for consumption, and `usage_o` to monitor FIFO occupancy.

### 4.2 Operation Guide

No specific operation sequence is required. The IP operates according to the input requests and status signals after being properly integrated.

## 5. Verification

| Test          | Status | Description                 |
| ------------- | ------ | --------------------------- |
| Reset test    | PASS   | Verify reset behavior       |
| Write test    | PASS   | Verify FIFO write operation |
| Read test     | PASS   | Verify FIFO read operation  |
| Full test     | PASS   | Verify full condition       |
| Empty test    | PASS   | Verify empty condition      |
| Boundary test | PASS   | Verify boundary transitions |

## 6. Synthesis

| Item       | Value        |
| ---------- | ------------ |
| Library    | Nangate45    |
| Frequency  | 100 MHz      |
| Cell Count | 867          |
| Cell Area  | 2168.432 µm² |
| WNS        | +2.05 ns     |

## 7. Notes

* `DATA_WIDTH` must be greater than 0.
* `DEPTH` must be greater than 1.
* The FIFO operates in a single clock domain.
* Synthesis results are based on the Nangate45 library and the documented 100 MHz target frequency.

