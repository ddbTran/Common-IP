#==============================================================================
# constraints.sdc
# Timing constraints for synthesis / STA — wdt module
#==============================================================================


#------------------------------------------------------------------------------
# 0. Configuration / Variables
#------------------------------------------------------------------------------

# Target operating frequency of the source (functional) clock [MHz]
set TARGET_FREQUENCY_SRC 100

# Target operating frequency of the reference (watchdog) clock [MHz]
# NOTE: WDT reference clocks are often a slow, independent oscillator
# (e.g. 32.768 kHz). Adjust to match the real reference clock on your SoC.
set TARGET_FREQUENCY_REF 10

# Virtual clock frequency for the configuration bus domain [MHz].
# No real clock port exists for this domain in this module; the virtual
# clock only gives set_input_delay a timing reference.
set TARGET_FREQUENCY_CFG 100

# Fraction of the target clock period available to the IP implementation.
set CLOCK_DERATE 1.0

# Fraction of the clock period allocated to I/O timing.
set IO_DERATE 0.6

# Clock periods [ns]
set CLOCK_PERIOD_SRC [expr {1000.0 / $TARGET_FREQUENCY_SRC * $CLOCK_DERATE}]
set CLOCK_PERIOD_REF [expr {1000.0 / $TARGET_FREQUENCY_REF * $CLOCK_DERATE}]
set CLOCK_PERIOD_CFG [expr {1000.0 / $TARGET_FREQUENCY_CFG * $CLOCK_DERATE}]

# I/O delays [ns]
set IO_DELAY_SRC [expr {$CLOCK_PERIOD_SRC * $IO_DERATE}]
set IO_DELAY_REF [expr {$CLOCK_PERIOD_REF * $IO_DERATE}]
set IO_DELAY_CFG [expr {$CLOCK_PERIOD_CFG * $IO_DERATE}]


#------------------------------------------------------------------------------
# 1. Clocks
#------------------------------------------------------------------------------

create_clock \
    -name clk_src \
    -period $CLOCK_PERIOD_SRC \
    [get_ports clk_src_i]

create_clock \
    -name clk_ref \
    -period $CLOCK_PERIOD_REF \
    [get_ports clk_ref_i]

# Virtual clock for the configuration domain (no physical port —
# timer_default_i / timer_threshold_i / timer_enable_i / kick_key_i are
# quasi-static config values with no clock of their own in this block).
create_clock \
    -name clk_cfg_virtual \
    -period $CLOCK_PERIOD_CFG

set_clock_uncertainty 0.05 [get_clocks clk_src]
set_clock_uncertainty 0.05 [get_clocks clk_ref]
set_clock_uncertainty 0.05 [get_clocks clk_cfg_virtual]

# Optional:
# set_clock_latency <value> [get_clocks clk_src]
# set_clock_latency <value> [get_clocks clk_ref]


#------------------------------------------------------------------------------
# 2. Generated Clock
#------------------------------------------------------------------------------

# N/A — no internally generated/divided clocks in this module.


#------------------------------------------------------------------------------
# 3. Ideal Network
#------------------------------------------------------------------------------

set_ideal_network [get_ports clk_src_i]
set_ideal_network [get_ports clk_ref_i]
set_ideal_network [get_ports rst_src_ni]
set_ideal_network [get_ports rst_ref_ni]


#------------------------------------------------------------------------------
# 4. Clock Groups
#------------------------------------------------------------------------------

# clk_src, clk_ref and the cfg virtual clock are all mutually asynchronous.
# Every crossing out of the cfg domain, and the src<->ref crossing, goes
# through 2-flop synchronizers, so none of these groups should see
# setup/hold analysis against each other.
set_clock_groups \
    -asynchronous \
    -group [get_clocks clk_src] \
    -group [get_clocks clk_ref] \
    -group [get_clocks clk_cfg_virtual]


#------------------------------------------------------------------------------
# 5. I/O Delay
#------------------------------------------------------------------------------

# --- clk_src_i domain I/O ---
set_input_delay \
    $IO_DELAY_SRC \
    -clock [get_clocks clk_src] \
    [get_ports kick_i]

set_output_delay \
    $IO_DELAY_SRC \
    -clock [get_clocks clk_src] \
    [get_ports timeout_irq_o]

# --- Configuration domain I/O (virtual clock) ---
set_input_delay \
    $IO_DELAY_CFG \
    -clock [get_clocks clk_cfg_virtual] \
    [get_ports {timer_default_i timer_threshold_i timer_enable_i kick_key_i}]

# No registered outputs in the clk_ref_i domain (timeout_ref stays internal).


#------------------------------------------------------------------------------
# 6. Maximum Delay
#------------------------------------------------------------------------------

# Optional:
# set_max_delay <value> \
#     -from [get_ports <input_ports>] \
#     -to   [get_ports <output_ports>]


#------------------------------------------------------------------------------
# 7. False Path
#------------------------------------------------------------------------------

# The cfg-domain inputs (timer_default_i, timer_threshold_i, timer_enable_i,
# kick_key_i) only enter synchronous logic through the first synchronizer
# flop of u_enable_sync / are directly compared inside a clk_src_i register
# (kick_key_i). The virtual clock above still lets the tool check their
# input-side timing; if your flow double-counts this against the
# asynchronous clock-group exclusion, you can relax further with:
# set_false_path -from [get_ports timer_enable_i]    -to [get_pins u_enable_sync/*/D]
# set_false_path -from [get_ports kick_key_i]         -to [get_pins */kick_event_reg/D]


#------------------------------------------------------------------------------
# 8. Set Load and Drive
#------------------------------------------------------------------------------

set_load 10 [get_ports *_o]
