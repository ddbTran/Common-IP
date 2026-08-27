#!/usr/bin/env bash
#
# check_tools.sh
#
# Verify that the installed Common-IP toolchain is usable:
#   Verilator, Surfer, Yosys, Yosys-ABC, ABC, OpenSTA
#
# Exits non-zero if any required tool fails.

set -uo pipefail
# NOTE: intentionally not using `set -e` here — a failing check must be
# recorded and reported, not abort the script.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_IPS_HOME="${COMMON_IPS_HOME:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# shellcheck source=/dev/null
source "${COMMON_IPS_HOME}/set_env.sh"

: "${TOOL_HOME:?TOOL_HOME must be set by set_env.sh}"

OVERALL_PASS=1

# ---------------------------------------------------------------------------
# check <label> <binary> <version_args...>
#
# Resolves <binary> on PATH (falling back to a few common install
# locations under TOOL_HOME), runs it with the given version arguments,
# and prints a PASS/FAIL line. Does not abort the script on failure.
# ---------------------------------------------------------------------------

resolve_bin() {
    local binary="$1" candidate
    if command -v "${binary}" >/dev/null 2>&1; then
        command -v "${binary}"
        return 0
    fi
    for candidate in \
        "${TOOL_HOME}/verilator/bin/${binary}" \
        "${TOOL_HOME}/surfer/bin/${binary}" \
        "${TOOL_HOME}/yosys/bin/${binary}" \
        "${TOOL_HOME}/abc/bin/${binary}" \
        "${TOOL_HOME}/opensta/bin/${binary}"
    do
        [[ -x "${candidate}" ]] && { echo "${candidate}"; return 0; }
    done
    return 1
}

check() {
    local label="$1" binary="$2"; shift 2
    local bin_path

    if ! bin_path="$(resolve_bin "${binary}")"; then
        printf "  %-12s %s\n" "${label}" "FAIL (not found)"
        OVERALL_PASS=0
        return
    fi

    if "${bin_path}" "$@" >/dev/null 2>&1; then
        printf "  %-12s %s\n" "${label}" "PASS"
    else
        printf "  %-12s %s\n" "${label}" "FAIL (did not run: ${bin_path})"
        OVERALL_PASS=0
    fi
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

echo "============================================================"
echo " Verifying Common-IP toolchain"
echo "============================================================"
echo

check "verilator" "verilator"   --version
check "surfer"    "surfer"      --version
check "yosys"     "yosys"       -V
check "yosys-abc" "yosys-abc"   -c "version"
check "abc"       "abc"         -c "version"
check "sta"       "sta"         -version

echo
echo "============================================================"
if [[ "${OVERALL_PASS}" -eq 1 ]]; then
    echo " Toolchain verification: PASS"
    echo "============================================================"
    exit 0
else
    echo " Toolchain verification: FAIL"
    echo "============================================================"
    exit 1
fi
