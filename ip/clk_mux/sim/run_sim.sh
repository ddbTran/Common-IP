#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Configuration
# ============================================================
# Change IP_HOME and TOP_MODULE accordingly to your IP
#
# Example:
#   IP_HOME="${SYNC_FIFO_HOME}"
#   TOP_MODULE="tb_sync_fifo"

IP_HOME="${CLK_MUX_HOME}"
TOP_MODULE="tb_clk_mux"

source $COMMON_IPS_HOME/ip/template/sim/run_sim_common.sh
