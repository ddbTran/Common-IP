#==============================================================================
# run_sta.tcl
# OpenSTA timing analysis flow
# Technology: Nangate45
#==============================================================================


#------------------------------------------------------------------------------
# 0. Configuration
#------------------------------------------------------------------------------

set TOP           $env(SYN_TOP)
set NETLIST       $env(SYN_OUT_NETLIST)
set SDC           $env(SYN_SDC)
set SYN_OUT_DIR   $env(SYN_OUT_DIR)


#------------------------------------------------------------------------------
# 1. Read Library
#------------------------------------------------------------------------------

read_liberty $env(NANGATE45_SLOW_LIB)
read_liberty $env(NANGATE45_TYP_LIB)
read_liberty $env(NANGATE45_FAST_LIB)

#------------------------------------------------------------------------------
# 2. Read Netlist
#------------------------------------------------------------------------------

read_verilog $NETLIST
link_design $TOP


#------------------------------------------------------------------------------
# 3. Read Constraints
#------------------------------------------------------------------------------

read_sdc $SDC

#------------------------------------------------------------------------------
# 4. Define Corners / Scenes
#------------------------------------------------------------------------------
define_scene ss -liberty NangateOpenCellLibrary_slow
define_scene tt -liberty NangateOpenCellLibrary
define_scene ff -liberty NangateOpenCellLibrary_fast

#------------------------------------------------------------------------------
# 5. Reports
#------------------------------------------------------------------------------
report_checks -format full_clock -path_delay max -fields {fanout capacitance slew input_pin net} > "$SYN_OUT_DIR/setup.rpt"
report_checks -format full_clock -path_delay min -fields {fanout capacitance slew input_pin net} > "$SYN_OUT_DIR/hold.rpt"
puts ""
puts "---- Setup (ss) summary ----"
report_wns -max
report_tns -max
 
puts ""
puts "---- Hold (ff) summary ----"
report_wns -min
report_tns -min
 
exit
