# RTL Coding Style

## 1. File Structure

Each RTL source file should generally follow this order:

```text
Header
`timescale
module declaration
Parameters
Ports
Internal signals
Combinational logic
Sequential logic
Memory / datapath
endmodule
```

Keep the structure consistent across the repository.

---

## 2. Header

Keep the header short and consistent:

```systemverilog
// ============================================================================
// Module      : <module_name>
// Description : <short description>
// Author      : Dat Tran
// ============================================================================

`timescale 1ns/1ps

```

Do not add unnecessary information to the header.

---

## 3. Parameters

Use `parameter int unsigned` for configurable parameters.

Use `localparam` for derived values.

```systemverilog
module <module_name> #(
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned DEPTH      = 8,
    localparam int unsigned PTR_WIDTH = $clog2(DEPTH)
) (
```

Use `UPPER_SNAKE_CASE` for parameters.

---

## 4. Ports

Use suffixes to indicate signal direction and registered state:

| Suffix | Meaning          |
| ------ | ---------------- |
| `_i`   | Input            |
| `_o`   | Output           |
| `_q`   | Registered state |
| `_d`   | Next-state       |

Use `_ni` for active-low inputs.

Example:

```systemverilog
input  logic                  clk_i,
input  logic                  rst_ni,
input  logic                  push_i,
input  logic [DATA_WIDTH-1:0] data_i,
output logic                  full_o,
output logic                  empty_o
```

---

## 5. Internal Signals

Use descriptive names for internal signals.

Registered state and next-state signals should use `_q` and `_d`:

```systemverilog
logic [31:0] count_q;
logic [31:0] count_d;
```

Related signals may be declared together:

```systemverilog
logic [PTR_WIDTH-1:0] write_ptr_q, write_ptr_d;
logic [PTR_WIDTH-1:0] read_ptr_q,  read_ptr_d;
```

Combinational control signals may use descriptive names without a suffix:

```systemverilog
logic push_en;
logic pop_en;
```

---

## 6. Combinational Logic

Use `always_comb` for combinational logic.

```systemverilog
always_comb begin
    state_d = state_q;

    if (condition)
        state_d = NEXT_STATE;
end
```

For simple expressions, prefer continuous assignments:

```systemverilog
assign push_en = push_i && !full_o;
assign pop_en  = pop_i  && !empty_o;
```

---

## 7. Sequential Logic

Use `always_ff` for sequential logic.

```systemverilog
always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        state_q <= '0;
    end else begin
        state_q <= state_d;
    end
end
```

Keep reset and state updates explicit and easy to follow.

---

## 8. Memory / Datapath

Use appropriate sequential or combinational constructs according to the required hardware behavior.

For synchronous memory writes:

```systemverilog
always_ff @(posedge clk_i) begin
    if (write_en)
        mem_q[write_addr] <= data_i;
end
```

---

## 9. Naming

### Signals

```text
clk_i
rst_ni
data_i
data_o
valid_i
ready_o
count_q
count_d
state_q
state_d
```

### Parameters

```text
DATA_WIDTH
DEPTH
ADDR_WIDTH
PTR_WIDTH
```

Use descriptive names and keep naming consistent across the repository.

---

## 10. Formatting

* Use 4 spaces for indentation.
* Do not use tabs.
* Terminate statements with `;`.
* Keep spacing around operators consistent.
* Avoid excessive column alignment.
* Use blank lines to separate logical blocks.
* Keep RTL files concise.

---

## 11. General Rules

Prefer:

```text
Simple
Explicit
Readable
Synthesizable
Technology-independent
```

Avoid:

```text
Unnecessary abstraction
Excessive comments
Overly long formatting
Clever but difficult-to-read constructs
Tool-specific RTL unless required
```

Small RTL IPs should be concise and easy to review.

The architecture and control flow should be understandable directly from the RTL.

