#!/usr/bin/env bash
#
# build_tools.sh
#
# Build the complete Common-IP toolchain:
#   00  Development Dependencies
#   01  Verilator
#   02  Surfer
#   03  Yosys
#   04  ABC
#   05  OpenSTA (+ CUDD)
#
# The script is idempotent: any tool already built at its pinned version
# is skipped. It stops immediately on the first failure.
#
# Usage:
#   ./scripts/build_tools.sh            # build everything
#   ./scripts/build_tools.sh yosys      # build/re-verify a single stage
#   FORCE_REBUILD=1 ./scripts/build_tools.sh verilator

set -euo pipefail

# ---------------------------------------------------------------------------
# Environment / configuration
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_IPS_HOME="${COMMON_IPS_HOME:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# set_env.sh defines COMMON_IPS_HOME / TOOL_HOME and prepares the environment.
# shellcheck source=/dev/null
source "${COMMON_IPS_HOME}/set_env.sh"

# shellcheck source=/dev/null
source "${COMMON_IPS_HOME}/scripts/tool_versions.sh"

: "${TOOL_HOME:?TOOL_HOME must be set by set_env.sh}"

SRC_HOME="${TOOL_HOME}/src"
STAMP_DIR="${TOOL_HOME}/.stamps"
LOG_DIR="${TOOL_HOME}/.logs"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"

mkdir -p "${SRC_HOME}" "${STAMP_DIR}" "${LOG_DIR}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

CURRENT_STAGE=""

log()  { printf '[build_tools] %s\n' "$*"; }
die()  { printf '[build_tools] ERROR (%s): %s\n' "${CURRENT_STAGE:-setup}" "$*" >&2; exit 1; }

on_error() {
    local exit_code=$?
    printf '\n[build_tools] Build FAILED during stage: %s (exit %d)\n' \
        "${CURRENT_STAGE:-unknown}" "${exit_code}" >&2
    printf '[build_tools] See log: %s\n' "${LOG_DIR}/${CURRENT_STAGE}.log" >&2
    exit "${exit_code}"
}
trap on_error ERR

stamp_path() { echo "${STAMP_DIR}/$1"; }

# is_built <tool> <version>  -> 0 if already built at that version
is_built() {
    local tool="$1" version="$2" stamp
    stamp="$(stamp_path "${tool}")"
    [[ "${FORCE_REBUILD}" != "1" ]] && [[ -f "${stamp}" ]] && \
        [[ "$(cat "${stamp}")" == "${version}" ]]
}

mark_built() {
    local tool="$1" version="$2"
    echo "${version}" > "$(stamp_path "${tool}")"
}

# clone_at <repo_url> <dest_dir> <commit_or_tag>
clone_at() {
    local repo="$1" dest="$2" ref="$3"
    if [[ ! -d "${dest}/.git" ]]; then
        git clone --quiet "${repo}" "${dest}"
    fi
    git -C "${dest}" fetch --quiet --all --tags
    git -C "${dest}" checkout --quiet "${ref}"
    git -C "${dest}" submodule update --quiet --init --recursive
}

run_step() {
    local name="$1"; shift
    CURRENT_STAGE="${name}"
    log "==> ${name}"
    "$@" >"${LOG_DIR}/${name}.log" 2>&1
}

STAGE_FILTER=("$@")

want_stage() {
    # If the user passed specific stage names on argv, only build those.
    # With no argv filter, every stage is wanted.
    local target="$1"
    [[ ${#STAGE_FILTER[@]} -eq 0 ]] && return 0
    local arg
    for arg in "${STAGE_FILTER[@]}"; do
        [[ "${arg}" == "${target}" ]] && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# 00 - Development Dependencies
# ---------------------------------------------------------------------------

REQUIRED_DEV_PACKAGES=(
    git gcc g++ make cmake autoconf automake libtool pkg-config
    bison flex tcl-dev swig curl python3
)

stage_dev_deps() {
    CURRENT_STAGE="00-dev-deps"
    log "==> 00 Development Dependencies"

    local missing=()
    local pkg
    for pkg in "${REQUIRED_DEV_PACKAGES[@]}"; do
        dpkg -s "${pkg}" >/dev/null 2>&1 || missing+=("${pkg}")
    done

    if ! command -v cargo >/dev/null 2>&1; then
        missing+=("cargo")
    fi

    if [[ ${#missing[@]} -eq 0 ]]; then
        log "    all development dependencies already present"
        return 0
    fi

    log "    missing: ${missing[*]}"
    if ! command -v apt-get >/dev/null 2>&1; then
        die "missing dependencies (${missing[*]}) and apt-get is unavailable; install them manually"
    fi

    local apt_missing=() need_cargo=0
    for pkg in "${missing[@]}"; do
        [[ "${pkg}" == "cargo" ]] && { need_cargo=1; continue; }
        apt_missing+=("${pkg}")
    done

    if [[ ${#apt_missing[@]} -gt 0 ]]; then
        sudo apt-get update -qq
        sudo apt-get install -y -qq "${apt_missing[@]}"
    fi

    if [[ "${need_cargo}" -eq 1 ]]; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
        # shellcheck source=/dev/null
        source "${HOME}/.cargo/env"
    fi
}

# ---------------------------------------------------------------------------
# 01 - Verilator
# ---------------------------------------------------------------------------

build_verilator() {
    local tool=verilator
    if is_built "${tool}" "${VERILATOR_VERSION}"; then
        log "==> 01 Verilator (already built, skipping)"
        return 0
    fi
    log "==> 01 Verilator"
    CURRENT_STAGE="01-verilator"

    local src="${SRC_HOME}/verilator"
    clone_at "${VERILATOR_REPO}" "${src}" "${VERILATOR_VERSION}"

    (
        cd "${src}"
        autoconf
        ./configure --prefix="${TOOL_HOME}/verilator"
        make -j"${JOBS}"
        make install
    )

    mark_built "${tool}" "${VERILATOR_VERSION}"
}

# ---------------------------------------------------------------------------
# 02 - Surfer
# ---------------------------------------------------------------------------

build_surfer() {
    local tool=surfer
    if is_built "${tool}" "${SURFER_VERSION}"; then
        log "==> 02 Surfer (already built, skipping)"
        return 0
    fi
    log "==> 02 Surfer"
    CURRENT_STAGE="02-surfer"

    local src="${SRC_HOME}/surfer"
    clone_at "${SURFER_REPO}" "${src}" "${SURFER_VERSION}"

    (
        cd "${src}"
        cargo build --release
        install -Dm755 target/release/surfer "${TOOL_HOME}/surfer/bin/surfer"
    )

    mark_built "${tool}" "${SURFER_VERSION}"
}

# ---------------------------------------------------------------------------
# 03 - Yosys
# ---------------------------------------------------------------------------

build_yosys() {
    local tool=yosys
    if is_built "${tool}" "${YOSYS_VERSION}"; then
        log "==> 03 Yosys (already built, skipping)"
        return 0
    fi
    log "==> 03 Yosys"
    CURRENT_STAGE="03-yosys"

    local src="${SRC_HOME}/yosys"
    clone_at "${YOSYS_REPO}" "${src}" "${YOSYS_VERSION}"

    (
        cd "${src}"
        make config-gcc
        make -j"${JOBS}" PREFIX="${TOOL_HOME}/yosys"
        make install PREFIX="${TOOL_HOME}/yosys"
    )

    mark_built "${tool}" "${YOSYS_VERSION}"
}

# ---------------------------------------------------------------------------
# 04 - ABC (standalone, distinct from the ABC bundled inside Yosys)
# ---------------------------------------------------------------------------

build_abc() {
    local tool=abc
    if is_built "${tool}" "${ABC_VERSION}"; then
        log "==> 04 ABC (already built, skipping)"
        return 0
    fi
    log "==> 04 ABC"
    CURRENT_STAGE="04-abc"

    local src="${SRC_HOME}/abc"
    clone_at "${ABC_REPO}" "${src}" "${ABC_VERSION}"

    (
        cd "${src}"
        make -j"${JOBS}"
        install -Dm755 abc "${TOOL_HOME}/abc/bin/abc"
    )

    mark_built "${tool}" "${ABC_VERSION}"
}

# ---------------------------------------------------------------------------
# 05 - OpenSTA (with CUDD as a dependency)
# ---------------------------------------------------------------------------

build_cudd() {
    local tool=cudd
    if is_built "${tool}" "${CUDD_VERSION}"; then
        log "    CUDD already built, skipping"
        return 0
    fi
    log "    building CUDD dependency"

    local src="${SRC_HOME}/cudd"
    mkdir -p "${src}"
    curl -fsSL "${CUDD_URL}" -o "${SRC_HOME}/cudd-${CUDD_VERSION}.tar.gz"
    tar -xzf "${SRC_HOME}/cudd-${CUDD_VERSION}.tar.gz" -C "${src}" --strip-components=1

    (
        cd "${src}"
        autoreconf -fi 2>/dev/null || true
        ./configure --prefix="${TOOL_HOME}/cudd"
        make -j"${JOBS}"
        make install
    )

    mark_built "${tool}" "${CUDD_VERSION}"
}

build_opensta() {
    local tool=opensta
    if is_built "${tool}" "${OPENSTA_VERSION}"; then
        log "==> 05 OpenSTA (already built, skipping)"
        return 0
    fi
    log "==> 05 OpenSTA"
    CURRENT_STAGE="05-opensta"

    build_cudd

    local src="${SRC_HOME}/opensta"
    clone_at "${OPENSTA_REPO}" "${src}" "${OPENSTA_VERSION}"

    (
        cd "${src}"
        mkdir -p build && cd build
        cmake -DCMAKE_INSTALL_PREFIX="${TOOL_HOME}/opensta" \
              -DCUDD_DIR="${TOOL_HOME}/cudd" \
              ..
        make -j"${JOBS}"
        make install
    )

    mark_built "${tool}" "${OPENSTA_VERSION}"
}

# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------

main() {
    log "Common-IP toolchain build starting (TOOL_HOME=${TOOL_HOME})"

    want_stage "dev-deps"  && run_step "00-dev-deps"  stage_dev_deps
    want_stage "verilator" && run_step "01-verilator" build_verilator
    want_stage "surfer"    && run_step "02-surfer"    build_surfer
    want_stage "yosys"     && run_step "03-yosys"     build_yosys
    want_stage "abc"       && run_step "04-abc"       build_abc
    want_stage "opensta"   && run_step "05-opensta"   build_opensta

    CURRENT_STAGE="done"
    log "Toolchain build complete."
    log "Run scripts/check_tools.sh to verify the installation."
}

main
