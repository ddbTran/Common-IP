#!/usr/bin/env bash

# ---------------------------------------------------------------------------
# Working directory
# ---------------------------------------------------------------------------
export COMMON_IPS_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# IP
# ---------------------------------------------------------------------------
export SYNC_FIFO_HOME="${COMMON_IPS_HOME}/ip/sync_fifo"

# ---------------------------------------------------------------------------
# Tool
# ---------------------------------------------------------------------------
export TOOL_HOME="${COMMON_IPS_HOME}/tool"

export YOSYS_HOME="${TOOL_HOME}/yosys"
export ABC_HOME="${TOOL_HOME}/abc"
export VERILATOR_HOME="${TOOL_HOME}/verilator"
export IVERILOG_HOME="${TOOL_HOME}/iverilog"
export OPENSTA_HOME="${TOOL_HOME}/OpenSTA"
export SURFER_HOME="${TOOL_HOME}/surfer"

# ---------------------------------------------------------------------------
# PATH
# ---------------------------------------------------------------------------
[ -d "${YOSYS_HOME}/install/bin" ]     && export PATH="${YOSYS_HOME}/install/bin:${PATH}"
[ -d "${ABC_HOME}" ]                   && export PATH="${ABC_HOME}:${PATH}"
[ -d "${VERILATOR_HOME}/install/bin" ] && export PATH="${VERILATOR_HOME}/install/bin:${PATH}"
[ -d "${IVERILOG_HOME}/install/bin" ]  && export PATH="${IVERILOG_HOME}/install/bin:${PATH}"
[ -d "${OPENSTA_HOME}/build" ]         && export PATH="${OPENSTA_HOME}/build:${PATH}"
[ -d "${SURFER_HOME}/install/bin" ]    && export PATH="${SURFER_HOME}/install/bin:${PATH}"

# ---------------------------------------------------------------------------
# Lib
# ---------------------------------------------------------------------------
