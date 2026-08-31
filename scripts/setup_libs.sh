#!/usr/bin/env bash
#
# setup_libs.sh
#
# Setup the Common-IP technology libraries:
#   Nangate45 FAST / TYP / SLOW
#
# The libraries are provided by OpenSTA examples and are copied
# into the Common-IP library directory.
#
# The script is idempotent: existing libraries are skipped.
# It stops immediately on the first failure.
#
# Usage:
#   ./scripts/setup_libs.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Environment / configuration
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_IPS_HOME="${COMMON_IPS_HOME:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# shellcheck source=/dev/null
source "${COMMON_IPS_HOME}/set_env.sh"

: "${LIB_HOME:?LIB_HOME must be set by set_env.sh}"
: "${OPENSTA_HOME:?OPENSTA_HOME must be set by set_env.sh}"

NANGATE45_HOME="${LIB_HOME}/nangate45"
OPENSTA_EXAMPLES="${OPENSTA_HOME}/examples"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

CURRENT_STAGE=""

log() {
    printf '[setup_lib] %s\n' "$*"
}

die() {
    printf '[setup_lib] ERROR (%s): %s\n' \
        "${CURRENT_STAGE:-setup}" "$*" >&2
    exit 1
}

on_error() {
    local exit_code=$?
    printf '\n[setup_lib] Setup FAILED during stage: %s (exit %d)\n' \
        "${CURRENT_STAGE:-unknown}" "${exit_code}" >&2
    exit "${exit_code}"
}

trap on_error ERR

copy_lib() {
    local src="$1"
    local dst="$2"

    if [[ ! -f "${src}" ]]; then
        die "Library not found: ${src}"
    fi

    if [[ -f "${dst}" ]]; then
        log "    ${dst} already exists, skipping"
        return 0
    fi

    log "    copying $(basename "${src}")"
    cp -v "${src}" "${dst}"
}

# ---------------------------------------------------------------------------
# Nangate45
# ---------------------------------------------------------------------------

setup_nangate45() {
    CURRENT_STAGE="nangate45"

    log "==> Nangate45"

    mkdir -p "${NANGATE45_HOME}"

    copy_lib \
        "${OPENSTA_EXAMPLES}/nangate45_fast.lib.gz" \
        "${NANGATE45_HOME}/nangate45_fast.lib.gz"

    copy_lib \
        "${OPENSTA_EXAMPLES}/nangate45_typ.lib.gz" \
        "${NANGATE45_HOME}/nangate45_typ.lib.gz"

    copy_lib \
        "${OPENSTA_EXAMPLES}/nangate45_slow.lib.gz" \
        "${NANGATE45_HOME}/nangate45_slow.lib.gz"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    log "Common-IP library setup starting"
    log "  LIB_HOME       = ${LIB_HOME}"
    log "  OPENSTA_HOME   = ${OPENSTA_HOME}"

    setup_nangate45

    CURRENT_STAGE="done"
    log "Library setup complete."
}

main
