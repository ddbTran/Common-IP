#==============================================================================
# run_ys.tcl
# Yosys synthesis flow for sync_fifo
# Technology: Nangate45
#==============================================================================


#------------------------------------------------------------------------------
# 1. Configuration
#------------------------------------------------------------------------------

set TOP          $env(SYN_TOP)
set SYN_FILELIST $env(SYN_FILELIST)
set LIBERTY      $env(NANGATE45_TYP_LIB)
set SDC          $env(SYN_SDC)
set OUT_NETLIST  $env(SYN_OUT_NETLIST)


#------------------------------------------------------------------------------
# 2. Read
#------------------------------------------------------------------------------

yosys read_slang -F $SYN_FILELIST -top $TOP

#------------------------------------------------------------------------------
# 3. Analyze and Elaborate
#------------------------------------------------------------------------------

yosys prep -top $TOP

#------------------------------------------------------------------------------
# 4. Synthesis
#------------------------------------------------------------------------------

yosys memory_map
yosys opt
yosys techmap
yosys opt

yosys dfflibmap -liberty $LIBERTY
yosys abc -liberty $LIBERTY -constr $SDC
yosys opt
yosys clean


#------------------------------------------------------------------------------
# 5. Write Output and Report
#------------------------------------------------------------------------------
yosys check
yosys stat -liberty $LIBERTY

yosys write_verilog -noattr $OUT_NETLIST

puts ""
puts "============================================================"
puts "Yosys synthesis completed"
puts "TOP      : $TOP"
puts "LIBRARY  : Nangate45"
puts "NETLIST  : $OUT_NETLIST"
puts "============================================================"
