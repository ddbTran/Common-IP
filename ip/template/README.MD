# <IP Name>

> <One-line description of the IP.>

**Version:** v0.1  
**Author:** <Author Name>  
**Status:** <Development / Stable / Experimental>

---

## Overview

### Purpose

<Describe the purpose of the IP in 2-4 sentences.>

### Features

- <Feature 1>
- <Feature 2>
- <Feature 3>

---

## Architecture

### Block Diagram

![<IP Name> block diagram](docs/<ip_name>_diagram.png)

### IO Ports

| Group | Port | Direction | Width | Description |
|---|---|---|---|---|
| Clock/Reset | `clk_i` | Input | 1 | Clock signal |
| Clock/Reset | `rst_ni` | Input | 1 | Active-low reset |
| <Group> | `<port_name_i>` | Input | `<WIDTH>` | <Description> |
| <Group> | `<port_name_o>` | Output | `<WIDTH>` | <Description> |

### Config Parameters

| Parameter | Default | Range | Description |
|---|---:|---|---|
| `<PARAM_NAME>` | `<default>` | `<range>` | <Description> |

---

## Functional Description

### <Operation / Feature>

<Describe the functional behavior of this operation or feature. 
Reference exact port and parameter names where appropriate.>

### Reset Behavior

<Describe reset assertion, deassertion, and resulting state.>

### <Additional Behavior>

<Describe any other relevant behavior such as flush, bypass,
error handling, status flags, arbitration, or special modes.>

---

## Interface Behavior

<Optional section for timing/transaction behavior that is important
for integration.>

### <Scenario>

<Describe the expected sequence of inputs and outputs.>

```text
<Optional timing diagram / ASCII waveform>
