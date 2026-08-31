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

IP_HOME="${SYNC_FIFO_HOME}"
TOP_MODULE="tb_sync_fifo"


# ============================================================
# Environment
# ============================================================
if [[ -z "${COMMON_IPS_HOME:-}" ]]; then
    echo "ERROR: Environment not initialized."
    echo "Please run: source set_env.sh"
    exit 1
fi

if [[ -z "${IP_HOME}" || -z "${TOP_MODULE}" ]]; then
    echo "ERROR: IP_HOME and TOP_MODULE must be configured."
    exit 1
fi


# ============================================================
# Simulation
# ============================================================

mkdir -p "${IP_HOME}/sim/out"
cd "$SYNC_FIFO_HOME/sim"

verilator \
    --binary \
    --timing \
    --trace-fst \
    --top-module "${TOP_MODULE}" \
    -f "${IP_HOME}/sim/filelist_sim.f" \
    -Mdir "${IP_HOME}/sim/out/obj_dir" \
    -o "${IP_HOME}/sim/out/obj_dir/${TOP_MODULE}"

"${IP_HOME}/sim/out/obj_dir/${TOP_MODULE}"
