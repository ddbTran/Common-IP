#!/usr/bin/env bash

# ============================================================
# Common IPs - Environment
# ============================================================

# ------------------------------------------------------------
# Working directory
# ------------------------------------------------------------

export COMMON_IPS_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# ------------------------------------------------------------
# IP
# ------------------------------------------------------------
export IP_HOME="${COMMON_IPS_HOME}/ip"

export SYNC_FIFO_HOME="${IP_HOME}/sync_fifo"
export SYNCHRONIZER_HOME="${IP_HOME}/synchronizer"
export CLK_GATE_HOME="${IP_HOME}/clk_gate"
export CLK_DIV_HOME="${IP_HOME}/clk_div"
export CLK_MUX_HOME="${IP_HOME}/clk_mux"

# ------------------------------------------------------------
# Tool
# ------------------------------------------------------------

export TOOL_HOME="${COMMON_IPS_HOME}/tool"

export YOSYS_HOME="${TOOL_HOME}/yosys"
export ABC_HOME="${TOOL_HOME}/abc"
export VERILATOR_HOME="${TOOL_HOME}/verilator"
export IVERILOG_HOME="${TOOL_HOME}/iverilog"
export OPENSTA_HOME="${TOOL_HOME}/OpenSTA"
export SURFER_HOME="${TOOL_HOME}/surfer"

# ------------------------------------------------------------
# Lib
# ------------------------------------------------------------

export LIB_HOME="${COMMON_IPS_HOME}/libs"

export NANGATE45_HOME="${LIB_HOME}/nangate45"

export NANGATE45_FAST_LIB="${NANGATE45_HOME}/nangate45_fast.lib.gz"
export NANGATE45_TYP_LIB="${NANGATE45_HOME}/nangate45_typ.lib.gz"
export NANGATE45_SLOW_LIB="${NANGATE45_HOME}/nangate45_slow.lib.gz"

# ------------------------------------------------------------
# PATH
# ------------------------------------------------------------

prepend_path()
{
    local dir="$1"

    [[ -d "${dir}" ]] || return 0

    case ":${PATH}:" in
        *":${dir}:"*)
            ;;
        *)
            export PATH="${dir}:${PATH}"
            ;;
    esac
}

prepend_path "${YOSYS_HOME}/install/bin"
prepend_path "${ABC_HOME}"
prepend_path "${VERILATOR_HOME}/install/bin"
prepend_path "${IVERILOG_HOME}/install/bin"
prepend_path "${OPENSTA_HOME}/build"
prepend_path "${SURFER_HOME}/install/bin"

# Clear bash's cached command-path table so any tool rebuilt/reinstalled
# since this shell started resolves to the new binary immediately.
hash -r
