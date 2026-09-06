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

SYN_TOP="sync_fifo"        # e.g. "sync_fifo"
IP_HOME="${SYNC_FIFO_HOME}"   # e.g. "${SYNC_FIFO_HOME}" — must be exported
                                 # by the top-level set_env.sh (see step 1 above)

#------------------------------------------------------------------------------
# Configuration — derived, should not need editing
#------------------------------------------------------------------------------

export SYN_TOP
export SYN_FILELIST="${IP_HOME}/syn/filelist_syn.f"
export SYN_SDC="${IP_HOME}/syn/constraints.sdc"

export SYN_OUT_DIR="${IP_HOME}/syn/outputs"
export SYN_OUT_NETLIST="${SYN_OUT_DIR}/${SYN_TOP}_netlist.v"

export SYN_LOG_DIR="${IP_HOME}/syn/logs"
export SYN_SYN_LOG="${SYN_LOG_DIR}/run_syn.log"
export SYN_STA_LOG="${SYN_LOG_DIR}/run_sta.log"

SYN_SCRIPT="${IP_HOME}/syn/run_syn.tcl"
STA_SCRIPT="${IP_HOME}/syn/run_sta.tcl"

#------------------------------------------------------------------------------
# Sanity checks (fail fast, before burning time on synthesis)
#------------------------------------------------------------------------------

if [[ "$SYN_TOP" == "CHANGE_ME" ]]; then
    echo "ERROR: Set SYN_TOP in run_syn.sh to this IP's top-level module name." >&2
    exit 1
fi

if [[ -z "$IP_HOME" ]]; then
    echo "ERROR: IP_HOME is empty in run_syn.sh." >&2
    echo "       Set it to this IP's *_HOME var (e.g. \"\${SYNC_FIFO_HOME}\")," >&2
    echo "       and make sure that var is exported by the top-level set_env.sh." >&2
    exit 1
fi

if [[ ! -f "$SYN_FILELIST" ]]; then
    echo "ERROR: Filelist not found: $SYN_FILELIST" >&2
    exit 1
fi

if [[ ! -f "$SYN_SDC" ]]; then
    echo "ERROR: SDC not found: $SYN_SDC" >&2
    exit 1
fi

: "${NANGATE45_SLOW_LIB:?NANGATE45_SLOW_LIB not set — did you source set_env.sh?}"
: "${NANGATE45_TYP_LIB:?NANGATE45_TYP_LIB not set — did you source set_env.sh?}"
: "${NANGATE45_FAST_LIB:?NANGATE45_FAST_LIB not set — did you source set_env.sh?}"

command -v yosys >/dev/null || { echo "ERROR: yosys not on PATH. Source set_env.sh first." >&2; exit 1; }
command -v sta   >/dev/null || { echo "ERROR: sta not on PATH. Source set_env.sh first."   >&2; exit 1; }

#------------------------------------------------------------------------------
# Prepare — wipe stale results so a partial/failed run can never look like a
# fresh pass.
#------------------------------------------------------------------------------

rm -rf "$SYN_OUT_DIR" "$SYN_LOG_DIR"
mkdir -p "$SYN_OUT_DIR" "$SYN_LOG_DIR"

#------------------------------------------------------------------------------
# 1. Synthesis
#------------------------------------------------------------------------------

echo ""
echo "============================================================"
echo "Running Yosys synthesis"
echo "============================================================"
yosys -V | tee -a "$SYN_SYN_LOG"

yosys -l "$SYN_SYN_LOG" -c "$SYN_SCRIPT"

if [[ ! -s "$SYN_OUT_NETLIST" ]]; then
    echo "ERROR: Synthesis did not produce a netlist: $SYN_OUT_NETLIST" >&2
    exit 1
fi

#------------------------------------------------------------------------------
# 2. Static Timing Analysis
#------------------------------------------------------------------------------

echo ""
echo "============================================================"
echo "Running OpenSTA timing analysis"
echo "============================================================"
sta -version | tee -a "$SYN_STA_LOG"

# -exit: terminate after the script runs instead of dropping to an
# interactive prompt on error (which would hang an unattended/CI run).
set +e
sta -exit "$STA_SCRIPT" 2>&1 | tee -a "$SYN_STA_LOG"
STA_STATUS=${PIPESTATUS[0]}
set -e

if [[ $STA_STATUS -ne 0 ]]; then
    echo "ERROR: OpenSTA exited with status $STA_STATUS — see $SYN_STA_LOG" >&2
    exit "$STA_STATUS"
fi

#------------------------------------------------------------------------------
# Timing violation check
#------------------------------------------------------------------------------

SETUP_WNS=$(awk '$1 == "wns" && $2 == "max" {print $3}' "$SYN_STA_LOG" | tail -1)
HOLD_WNS=$(awk '$1 == "wns" && $2 == "min" {print $3}' "$SYN_STA_LOG" | tail -1)

echo ""
echo "============================================================"
echo "Timing Summary"
echo "============================================================"
echo "Setup WNS : ${SETUP_WNS:-N/A} ns"
echo "Hold  WNS : ${HOLD_WNS:-N/A} ns"
echo "============================================================"

TIMING_VIOLATION=0

if [[ -n "$SETUP_WNS" ]] && awk "BEGIN {exit !($SETUP_WNS < 0)}"; then
    echo "WARNING: Setup timing violation detected: WNS = $SETUP_WNS ns"
    TIMING_VIOLATION=1
fi

if [[ -n "$HOLD_WNS" ]] && awk "BEGIN {exit !($HOLD_WNS < 0)}"; then
    echo "WARNING: Hold timing violation detected: WNS = $HOLD_WNS ns"
    TIMING_VIOLATION=1
fi

if [[ $TIMING_VIOLATION -eq 0 ]]; then
    echo "Timing status: PASS"
else
    echo "Timing status: VIOLATION"
    echo "WARNING: Timing violations detected — see $SYN_STA_LOG"
fi

#------------------------------------------------------------------------------
# Done
#------------------------------------------------------------------------------

echo ""
echo "============================================================"
echo "Synthesis + STA completed — $TIMING_VIOLATION timing violations"
echo "TOP         : $SYN_TOP"
echo "NETLIST     : $SYN_OUT_NETLIST"
echo "REPORTS     : $SYN_OUT_DIR"
echo "SYN LOG     : $SYN_SYN_LOG"
echo "STA LOG     : $SYN_STA_LOG"
echo "============================================================"
