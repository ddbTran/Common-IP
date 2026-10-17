
#==============================================================================
# constraints.sdc
# Timing constraints for synthesis / STA
#==============================================================================


#------------------------------------------------------------------------------
# 0. Configuration / Variables
#------------------------------------------------------------------------------

set CLOCK_WR_FREQUENCY 100
set CLOCK_RD_FREQUENCY 100

set CLOCK_DERATE 1.0
set IO_DERATE 0.6

set CLOCK_WR_PERIOD [expr {1000.0 / $CLOCK_WR_FREQUENCY * $CLOCK_DERATE}]
set CLOCK_RD_PERIOD [expr {1000.0 / $CLOCK_RD_FREQUENCY * $CLOCK_DERATE}]

set IO_WR_DELAY [expr {$CLOCK_WR_PERIOD * $IO_DERATE}]
set IO_RD_DELAY [expr {$CLOCK_RD_PERIOD * $IO_DERATE}]

set FIFO_DEPTH 8
set DATA_SETUP_MARGIN 0.2

set SLOT_DATA_PIN_FORMAT  {}
set SLOT_TOKEN_PIN_FORMAT {}


#------------------------------------------------------------------------------
# 1. Clock
#------------------------------------------------------------------------------

create_clock \
    -name clk_wr \
    -period $CLOCK_WR_PERIOD \
    [get_ports clk_wr_i]

create_clock \
    -name clk_rd \
    -period $CLOCK_RD_PERIOD \
    [get_ports clk_rd_i]

set_clock_uncertainty 0.05 [get_clocks clk_wr]
set_clock_uncertainty 0.05 [get_clocks clk_rd]


#------------------------------------------------------------------------------
# 2. Generated Clock
#------------------------------------------------------------------------------

# Optional


#------------------------------------------------------------------------------
# 3. Ideal Network
#------------------------------------------------------------------------------

set_ideal_network [get_ports clk_wr_i]
set_ideal_network [get_ports clk_rd_i]
set_ideal_network [get_ports rst_wr_ni]
set_ideal_network [get_ports rst_rd_ni]


#------------------------------------------------------------------------------
# 4. Clock Groups
#------------------------------------------------------------------------------

set_clock_groups \
    -asynchronous \
    -allow_paths \
    -group [get_clocks clk_wr] \
    -group [get_clocks clk_rd]


#------------------------------------------------------------------------------
# 5. I/O Delay
#------------------------------------------------------------------------------

set_input_delay \
    $IO_WR_DELAY \
    -clock [get_clocks clk_wr] \
    [get_ports {wr_data_i* wren_i}]

set_input_delay \
    $IO_RD_DELAY \
    -clock [get_clocks clk_rd] \
    [get_ports rden_i]

set_output_delay \
    $IO_WR_DELAY \
    -clock [get_clocks clk_wr] \
    [get_ports {full_o ready_o}]

set_output_delay \
    $IO_RD_DELAY \
    -clock [get_clocks clk_rd] \
    [get_ports {rd_data_o* empty_o valid_o}]


#------------------------------------------------------------------------------
# 6. Maximum Delay
#------------------------------------------------------------------------------

set_max_delay $CLOCK_RD_PERIOD \
    -from [all_registers -clock clk_rd -clock_pins] \
    -to   [get_ports rd_data_o*]

#------------------------------------------------------------------------------
# 7. Set Load and Drive
#------------------------------------------------------------------------------

set_load 10 [get_ports *_o]

