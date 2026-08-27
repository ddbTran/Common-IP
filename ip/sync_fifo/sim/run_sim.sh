#!/usr/bin/env bash
#
# run_sim.sh — STANDARD TEMPLATE
#
# Copied as-is into every <cell>/sim/ folder. Self-locates based on
# where it lives on disk (parent directory = cell root) — no CELL
# argument needed, works unmodified for every cell.
#
#   cells/<cell>/sim/run_sim.sh
#                ^^^ CELL is derived from this
#
# Local convention (per cell):
#   sim/tb_<cell>.sv     <- testbench
#   sim/filelist_sim.f   <- RTL + tb sources for this sim build
#   sim/run_sim.sh       <- this script
#   sim/out/             <- generated output (gitignored, NOT committed)
#
# Usage (run from anywhere):
#   ./run_sim.sh
#
# Exit code:
#   0   -> build succeeded and testbench passed
#   !=0 -> compile error or testbench failure ($fatal)

set -euo pipefail

# ---------------------------------------------------------------------------
# 0. Self-locate: sim/ -> cell root -> cell name
# ---------------------------------------------------------------------------
SIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CELL_DIR="$(cd "${SIM_DIR}/.." && pwd)"
CELL="$(basename "${CELL_DIR}")"
TOP_MODULE="tb_${CELL}"

SIM_FILELIST="${SIM_DIR}/filelist_sim.f"

OUT_DIR="${SIM_DIR}/out"
OBJ_DIR="${OUT_DIR}/obj_dir"
BUILD_LOG="${OUT_DIR}/run_sim_build.log"
RUN_LOG="${OUT_DIR}/run_sim.log"

# ---------------------------------------------------------------------------
# 1. Sanity checks
# ---------------------------------------------------------------------------
if ! command -v verilator >/dev/null 2>&1; then
  echo "error: verilator not found in PATH" >&2
  exit 1
fi

if [[ ! -f "${SIM_FILELIST}" ]]; then
  echo "error: sim filelist not found: ${SIM_FILELIST}" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"

# ---------------------------------------------------------------------------
# 2. Build (filelist paths are relative to sim/, so run from there)
# ---------------------------------------------------------------------------
echo "==> Building '${CELL}' testbench with Verilator"
(
  cd "${SIM_DIR}"
  ${VERILATOR_HOME}/bin/verilator \
    --binary \
    -Wall \
    --timing \
    -sv \
    -f "$(basename "${SIM_FILELIST}")" \
    --top-module "${TOP_MODULE}" \
    --Mdir "${OBJ_DIR}" \
    -o "${TOP_MODULE}"
) 2>&1 | tee "${BUILD_LOG}"

build_status="${PIPESTATUS[0]}"
if [[ ${build_status} -ne 0 ]]; then
  echo "==> Build FAILED for '${CELL}' (see ${BUILD_LOG})" >&2
  exit "${build_status}"
fi

# ---------------------------------------------------------------------------
# 3. Run
# ---------------------------------------------------------------------------
echo "==> Running '${CELL}' simulation"
"${OBJ_DIR}/${TOP_MODULE}" 2>&1 | tee "${RUN_LOG}"
run_status="${PIPESTATUS[0]}"

if [[ ${run_status} -ne 0 ]]; then
  echo "==> Simulation FAILED for '${CELL}' (see ${RUN_LOG})" >&2
  exit "${run_status}"
fi

echo "==> Simulation PASSED for '${CELL}'"
echo "    log : ${RUN_LOG}"
exit 0
