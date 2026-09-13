#==============================================================================
# constraints.sdc
# Timing constraints for synthesis / STA
#==============================================================================


#------------------------------------------------------------------------------
# 0. Configuration / Variables
#------------------------------------------------------------------------------

# Target operating frequency [MHz]
set CLOCK_FREQUENCY 100  

# Fraction of the target clock period available to the IP implementation.
set CLOCK_DERATE 1.0

# Fraction of the clock period allocated to I/O timing.
set IO_DERATE 0.6

# Clock period [ns]
set CLOCK_PERIOD [expr {1000.0 / $CLOCK_FREQUENCY * $CLOCK_DERATE}]

# I/O delay [ns]
set IO_DELAY [expr {$CLOCK_PERIOD * $IO_DERATE}]


#------------------------------------------------------------------------------
# 1. Clock
#------------------------------------------------------------------------------

create_clock \
    -name clk_src \
    -period $CLOCK_PERIOD \
    [get_ports clk_src_i]

create_clock \
    -name clk_dst \
    -period $CLOCK_PERIOD \
    [get_ports clk_dst_i]

set_clock_uncertainty 0.05 [get_clocks {clk_src clk_dst}]

# Optional:
# set_clock_latency <value> [get_clocks clk]


#------------------------------------------------------------------------------
# 2. Generated Clock
#------------------------------------------------------------------------------

# Optional:
# create_generated_clock ...


#------------------------------------------------------------------------------
# 3. Ideal Network
#------------------------------------------------------------------------------

set_ideal_network [get_ports {clk_src_i clk_dst_i}]
set_ideal_network [get_ports {rst_src_ni rst_dst_ni}]


#------------------------------------------------------------------------------
# 4. Clock Groups
#------------------------------------------------------------------------------

# Optional:
# set_clock_groups \
#     -asynchronous \
#     -group [get_clocks clk] \
#     -group [get_clocks <other_clk>]
set_clock_groups \
    -asynchronous \
    -group [get_clocks clk_src] \
    -group [get_clocks clk_dst]


#------------------------------------------------------------------------------
# 5. I/O Delay
#------------------------------------------------------------------------------

set_input_delay \
    $IO_DELAY \
    -clock [get_clocks clk_src] \
    [get_ports pulse_i]

set_output_delay \
    $IO_DELAY \
    -clock [get_clocks clk_src] \
    [get_ports ready_o]

set_output_delay \
    $IO_DELAY \
    -clock [get_clocks clk_dst] \
    [get_ports pulse_o]

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

set_load 10 [get_ports *_o]
