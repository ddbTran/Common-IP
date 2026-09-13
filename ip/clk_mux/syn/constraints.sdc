#==============================================================================
# constraints.sdc
# Timing constraints for synthesis / STA
#==============================================================================


#------------------------------------------------------------------------------
# 0. Configuration / Variables
#------------------------------------------------------------------------------

# Target operating frequencies [MHz]
set TARGET_FREQ_1 100
set TARGET_FREQ_2 62.5

# Fraction of the target clock period available to the IP implementation.
set CLOCK_DERATE 1.0

# Fraction of the clock period allocated to I/O timing.
set IO_DERATE 0.6

# Clock periods [ns]
set CLOCK_PERIOD_1 [expr {1000.0 / $TARGET_FREQ_1 * $CLOCK_DERATE}]
set CLOCK_PERIOD_2 [expr {1000.0 / $TARGET_FREQ_2 * $CLOCK_DERATE}]


#------------------------------------------------------------------------------
# 1. Clock
#------------------------------------------------------------------------------

create_clock \
    -name i_clk1 \
    -period $CLOCK_PERIOD_1 \
    [get_ports i_clk1]

create_clock \
    -name i_clk2 \
    -period $CLOCK_PERIOD_2 \
    [get_ports i_clk2]

set_clock_uncertainty 0.05 [get_clocks i_clk1]
set_clock_uncertainty 0.05 [get_clocks i_clk2]

# Optional:
# set_clock_latency <value> [get_clocks clk]


#------------------------------------------------------------------------------
# 2. Generated Clock
#------------------------------------------------------------------------------

# Optional:
# create_generated_clock ...
create_generated_clock \
    -add -name o_clk1 \
    -master_clock i_clk1 \
    -source [get_ports i_clk1] \
    -div 1 \
    [get_ports o_clk]

create_generated_clock \
    -add -name o_clk2 \
    -master_clock i_clk2 \
    -source [get_ports i_clk2] \
    -div 1 \
    [get_ports o_clk]


#------------------------------------------------------------------------------
# 3. Ideal Network
#------------------------------------------------------------------------------

set_ideal_network [get_ports i_clk1]
set_ideal_network [get_ports i_clk2]
set_ideal_network [get_ports i_reset1]
set_ideal_network [get_ports i_reset2]

#------------------------------------------------------------------------------
# 4. Clock Groups
#------------------------------------------------------------------------------

# Optional:
# set_clock_groups \
#     -asynchronous \
#     -group [get_clocks clk] \
#     -group [get_clocks <other_clk>]


#------------------------------------------------------------------------------
# 5. I/O Delay
#------------------------------------------------------------------------------

set_input_delay \
    1 \
    -clock [get_clocks i_clk2] \
    [get_ports i_sel]

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

# Optional:
# set_false_path \
#     -from [get_ports <input_ports>] \
#     -to   [get_ports <output_ports>]

#------------------------------------------------------------------------------
# 8. Set Load and Drive
#------------------------------------------------------------------------------

set_load 10 [get_ports o_*]
