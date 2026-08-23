# common_cells — RTL Coding Style

## 1. Purpose

This document defines the RTL coding conventions for the `common_cells` repository.

The goals are:

* readable RTL
* synthesizable RTL
* reusable IP
* predictable simulation and synthesis behavior
* compatibility with Verilator and Yosys
* consistent style across all IPs

The style is inspired by conventions commonly used in projects such as PULP and lowRISC, but no project infrastructure is copied.

---

## 2. Language

All new RTL shall use SystemVerilog.

File extension:

```text
.sv
```

Use SystemVerilog constructs such as:

```systemverilog
logic
always_ff
always_comb
typedef
enum
```

Do not use legacy Verilog `wire` / `reg` declarations for new RTL.

---

## 3. File and Module Naming

The module name shall match the RTL filename.

Example:

```text
sync_fifo.sv
```

```systemverilog
module sync_fifo (
  ...
);
```

Use `snake_case` for:

* module names
* signal names
* parameter names
* local variables
* filenames
* directories

Examples:

```text
sync_fifo
read_ptr
write_ptr
data_width
fifo_depth
```

---

## 4. IP Directory Structure

Each IP shall be self-contained under:

```text
cells/src/<ip_name>/
```

Standard structure:

```text
<ip_name>/
├── docs/
├── rtl/
├── sim/
├── sdc/
└── syn/
```

RTL sources belong in:

```text
<ip_name>/rtl/
```

Testbench sources belong in:

```text
<ip_name>/sim/
```

Constraints belong in:

```text
<ip_name>/sdc/
```

IP-specific synthesis configuration belongs in:

```text
<ip_name>/syn/
```

---

## 5. Port Naming

Use suffixes to identify signal direction and polarity.

| Suffix | Meaning           |
| ------ | ----------------- |
| `_i`   | input             |
| `_o`   | output            |
| `_ni`  | active-low input  |
| `_no`  | active-low output |

Examples:

```systemverilog
clk_i
rst_ni
data_i
data_o
valid_i
ready_o
```

Do not use ambiguous names such as:

```text
clk
reset
input
output
```

Prefer:

```text
clk_i
rst_ni
data_i
data_o
```

---

## 6. Clock and Reset

Clock signals shall use:

```text
clk_i
```

Active-low reset shall use:

```text
rst_ni
```

For synchronous reset:

```systemverilog
always_ff @(posedge clk_i) begin
  if (!rst_ni) begin
    ...
  end else begin
    ...
  end
end
```

For asynchronous active-low reset:

```systemverilog
always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    ...
  end else begin
    ...
  end
end
```

Do not add clock or reset ports to purely combinational IPs.

---

## 7. Sequential Logic

Use `always_ff` for sequential logic.

Preferred:

```systemverilog
always_ff @(posedge clk_i) begin
  if (!rst_ni) begin
    count_q <= '0;
  end else begin
    count_q <= count_d;
  end
end
```

Do not use:

```systemverilog
always @(posedge clk_i)
```

for new RTL.

Use non-blocking assignments:

```systemverilog
<=
```

inside sequential blocks.

Do not use blocking assignments for state updates:

```systemverilog
count_q = count_d;
```

---

## 8. Combinational Logic

Use `always_comb` for non-trivial combinational logic.

Example:

```systemverilog
always_comb begin
  count_d = count_q;

  if (write_en) begin
    count_d = count_q + 1'b1;
  end
end
```

For simple expressions, prefer continuous assignments:

```systemverilog
assign empty_o = (count_q == '0);
assign full_o  = (count_q == FIFO_DEPTH);
```

Avoid unnecessary `always_comb` blocks for simple one-line expressions.

---

## 9. Next-State Coding

For sequential blocks, separate state from next-state logic when the logic becomes non-trivial.

Example:

```systemverilog
logic [PTR_WIDTH-1:0] wr_ptr_q;
logic [PTR_WIDTH-1:0] wr_ptr_d;

always_comb begin
  wr_ptr_d = wr_ptr_q;

  if (write_en) begin
    wr_ptr_d = wr_ptr_q + 1'b1;
  end
end

always_ff @(posedge clk_i) begin
  if (!rst_ni) begin
    wr_ptr_q <= '0;
  end else begin
    wr_ptr_q <= wr_ptr_d;
  end
end
```

Use `_q` for registered/state signals.

Use `_d` for next-state signals.

Examples:

```text
count_q
count_d
wr_ptr_q
wr_ptr_d
rd_ptr_q
rd_ptr_d
```

For very small sequential blocks, a direct `always_ff` implementation is acceptable.

---

## 10. Parameters

Parameters shall use `snake_case`.

Example:

```systemverilog
parameter int unsigned data_width = 32,
parameter int unsigned depth      = 16
```

Parameters should have sensible defaults where possible.

Avoid unnecessary parameters.

For example, do not parameterize implementation details unless there is a clear reuse requirement.

---

## 11. Width Handling

Explicitly define signal widths.

Prefer:

```systemverilog
logic [31:0] data_q;
```

over implicit integer sizing.

Use sized constants where width matters:

```systemverilog
32'd0
1'b0
```

Use unsized `'0` when assigning all bits of a vector:

```systemverilog
data_q <= '0;
```

Be careful with arithmetic expressions involving different widths.

Explicit extension is preferred when carry or overflow matters:

```systemverilog
logic [32:0] result;

assign result = {1'b0, a_i} + {1'b0, b_i};
```

---

## 12. Combinational Completeness

Every variable assigned in an `always_comb` block must receive a value on every possible execution path.

Preferred:

```systemverilog
always_comb begin
  next_state = state_q;

  if (enable_i) begin
    next_state = STATE_ACTIVE;
  end
end
```

Do not create unintended latches.

Avoid incomplete assignments such as:

```systemverilog
always_comb begin
  if (enable_i) begin
    next_state = STATE_ACTIVE;
  end
end
```

unless the intended behavior is explicitly latch-based.

Latch inference is not allowed unless the IP specification explicitly requires it.

---

## 13. Reset Behavior

Reset behavior must be deterministic.

For stateful logic, explicitly define the reset value:

```systemverilog
if (!rst_ni) begin
  wr_ptr_q <= '0;
  rd_ptr_q <= '0;
  count_q  <= '0;
end
```

Do not leave state uninitialized unless explicitly required by the design specification.

Reset should place the block into a valid operational state.

For example, a FIFO should normally become:

```text
empty = 1
full  = 0
```

after reset.

---

## 14. Memory and Arrays

Use SystemVerilog arrays for internal memories.

Example:

```systemverilog
logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
```

Use clear index expressions:

```systemverilog
mem[wr_ptr_q] <= wdata_i;
```

Do not introduce vendor-specific memory primitives in the baseline RTL unless required.

The baseline implementation should remain synthesizable by generic Yosys.

---

## 15. Conditional Logic

Use clear conditions.

Preferred:

```systemverilog
if (wr_en_i && !full_o) begin
  ...
end
```

Avoid deeply nested conditions when a simple enable expression is sufficient.

For example:

```systemverilog
logic write_en;
logic read_en;

assign write_en = wr_en_i && !full_o;
assign read_en  = rd_en_i && !empty_o;
```

This can make control logic easier to inspect and verify.

---

## 16. FSMs

For finite-state machines, use SystemVerilog `enum` where appropriate.

Example:

```systemverilog
typedef enum logic [1:0] {
  IDLE,
  ACTIVE,
  DONE
} state_e;

state_e state_q;
state_e state_d;
```

Use separate state and next-state logic for non-trivial FSMs.

Keep state names descriptive.

Avoid numeric state values scattered throughout RTL.

---

## 17. Generate Blocks

Generate constructs are allowed when required for parameterized hardware.

Example:

```systemverilog
genvar i;

generate
  for (i = 0; i < NUM_STAGES; i++) begin : gen_stage
    ...
  end
endgenerate
```

Generate block names should be descriptive.

Avoid generate logic when a simpler RTL structure is sufficient.

---

## 18. RTL Restrictions

The following constructs shall not be used in synthesizable design RTL:

```systemverilog
#10
#1
initial
$display()
$finish
$monitor()
```

Do not use simulation-only timing controls in RTL.

Simulation-specific constructs belong in the testbench.

Do not use:

```systemverilog
force
release
```

in normal design RTL.

---

## 19. Assertions

Assertions are not required in the baseline RTL phase.

If assertions are introduced later, they should not interfere with the baseline Yosys synthesis flow.

For this phase:

```text
RTL assertions: optional
Formal verification: out of scope
```

---

## 20. Testbench Coding Style

Testbench code may use simulation-specific constructs.

The testbench may use:

```systemverilog
initial
#delay
$display
$finish
```

The testbench should still follow the same naming and formatting conventions.

Example:

```systemverilog
module tb_sync_fifo;

  logic        clk;
  logic        rst_n;
  logic        wr_en;
  logic [31:0] wdata;

  ...
endmodule
```

For consistency with the DUT interface, testbench signals connected to DUT ports should preferably retain the DUT naming:

```systemverilog
logic        clk_i;
logic        rst_ni;
logic        wr_en_i;
logic [31:0] wdata_i;
```

---

## 21. Testbench Checking

Tests must fail with a non-zero simulator exit code.

Preferred pattern:

```systemverilog
if (actual !== expected) begin
  $display("ERROR: ...");
  $finish(1);
end
```

A successful testbench should explicitly terminate successfully:

```systemverilog
$finish(0);
```

Random tests should use deterministic seeds when reproducibility is important.

---

## 22. Filelists

Each IP shall maintain its own filelists.

RTL:

```text
rtl/filelist.f
```

Simulation:

```text
sim/filelist.f
```

The global scripts shall consume these filelists rather than hard-coding individual RTL source filenames.

Example:

```text
# rtl/filelist.f
sync_fifo.sv
```

Simulation filelist:

```text
# sim/filelist.f
../rtl/sync_fifo.sv
tb_sync_fifo.sv
```

---

## 23. Synthesis Compatibility

RTL shall be compatible with generic Yosys synthesis.

Avoid unnecessary:

* vendor-specific primitives
* technology-specific cells
* proprietary synthesis directives
* simulator-only constructs

The baseline RTL should describe the intended hardware rather than a specific implementation.

---

## 24. Tool Compatibility

The baseline RTL must be checked with:

```text
Verilator
Yosys
```

Minimum checks:

```bash
verilator --lint-only
```

and:

```text
Yosys synthesis
```

An RTL construct should not be introduced solely because it works in simulation if it cannot be synthesized.

---

## 25. Formatting

Use:

```text
Indentation : 2 spaces
Tabs        : prohibited
Line ending : LF
Encoding    : UTF-8
```

Example:

```systemverilog
module sync_fifo #(
  parameter int unsigned data_width = 32,
  parameter int unsigned depth      = 16
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,
  input  logic                  wr_en_i,
  input  logic [data_width-1:0] wdata_i,
  input  logic                  rd_en_i,
  output logic [data_width-1:0] rdata_o,
  output logic                  full_o,
  output logic                  empty_o
);

  ...

endmodule
```

Align related declarations where it improves readability, but do not sacrifice readability merely to maintain column alignment.

---

## 26. Comments

Comments should explain **why**, not simply repeat **what** the RTL does.

Good:

```systemverilog
// Count tracks the number of valid entries currently stored in the FIFO.
logic [COUNT_WIDTH-1:0] count_q;
```

Less useful:

```systemverilog
// Increment count.
count_q <= count_q + 1'b1;
```

Avoid excessive comments for obvious RTL.

---

## 27. Module Header

Each RTL module should begin with a short description.

Example:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
//
// Synchronous single-clock FIFO.
//
// Stores DATA_WIDTH-bit words and provides full/empty status.

module sync_fifo #(
  ...
);
```

The exact license header may be updated when the repository license is finalized.

---

## 28. Signal Naming for State

Use `_q` for registered state:

```text
state_q
count_q
wr_ptr_q
rd_ptr_q
```

Use `_d` for next-state values:

```text
state_d
count_d
wr_ptr_d
rd_ptr_d
```

Use descriptive names for combinational signals:

```text
write_en
read_en
full
empty
```

If a signal is an actual module port, retain the direction suffix:

```text
wr_en_i
rd_en_i
full_o
empty_o
```

---

## 29. Avoid Unnecessary Complexity

The first implementation of an IP should prioritize:

```text
correctness
readability
synthesizability
```

over:

```text
micro-optimization
clever RTL
tool-specific optimization
minimum line count
```

For example, the baseline synchronous FIFO should use straightforward:

```text
memory
write pointer
read pointer
count
full
empty
```

logic before considering more specialized FIFO implementations.

---

## 30. Design Principle

The repository follows this separation:

```text
IP-specific RTL
        ↓
cells/src/<ip_name>/

Common simulation flow
        ↓
script/sim/

Common synthesis flow
        ↓
script/syn/

Repository entry point
        ↓
Makefile

Global configuration
        ↓
configs/

Generated output
        ↓
build/
```

The RTL coding style must remain independent of the global flow implementation.

---

## 31. Review Checklist

Before considering an RTL block complete:

### Naming

* [ ] Module name matches filename
* [ ] `snake_case` is used consistently
* [ ] Port suffixes are correct
* [ ] Clock/reset naming is correct
* [ ] Registered signals use `_q`
* [ ] Next-state signals use `_d`

### RTL

* [ ] SystemVerilog is used
* [ ] `logic` is used instead of new `wire/reg`
* [ ] Sequential logic uses `always_ff`
* [ ] Combinational logic uses `always_comb` or `assign`
* [ ] No unintended latches
* [ ] Reset behavior is deterministic
* [ ] Widths are explicit where required
* [ ] No simulation-only constructs in design RTL

### Tool compatibility

* [ ] Verilator lint passes
* [ ] Yosys synthesis passes
* [ ] No unnecessary vendor-specific constructs

### Maintainability

* [ ] RTL is readable
* [ ] Comments explain non-obvious design decisions
* [ ] No unnecessary complexity
* [ ] IP-specific configuration stays inside the IP directory

---

## 32. Baseline Rule

When there is a choice between two valid RTL implementations, prefer the implementation that is:

1. simpler,
2. easier to understand,
3. easier to simulate,
4. easier to synthesize,
5. easier to reuse.

Optimization should be driven by measured synthesis results rather than by prematurely complicated RTL.

