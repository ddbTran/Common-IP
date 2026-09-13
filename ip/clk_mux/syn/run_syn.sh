#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# run_syn.sh
# Synthesis + STA driver — TEMPLATE
#
# Usage:
#   1. In the top-level set_env.sh, add a *_HOME export for the new IP,
#      following the existing pattern, e.g.:
#        export NEW_IP_HOME="${IP_HOME}/new_ip"
#   2. Copy this whole syn/ directory into ip/<ip_name>/syn/
#   3. Edit SYN_TOP and IP_HOME below for the new IP
#   4. Write ip/<ip_name>/syn/filelist_syn.f (one RTL file per line)
#   5. Adjust constraints.sdc (clock/reset port names, frequency, etc.)
#   6. From repo root: source set_env.sh
#   7. ./run_syn.sh
#==============================================================================

#------------------------------------------------------------------------------
# Configuration — EDIT PER IP
#------------------------------------------------------------------------------

SYN_TOP="clk_mux"        # e.g. "sync_fifo"
IP_HOME="${CLK_MUX_HOME}"   # e.g. "${SYNC_FIFO_HOME}" — must be exported
                                 # by the top-level set_env.sh (see step 1 above)

source $COMMON_IPS_HOME/ip/template/syn/run_syn_common.sh
