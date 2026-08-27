#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Environment
# ============================================================

if [[ -z "${COMMON_IPS_HOME:-}" || -z "${TOOL_HOME:-}" ]]; then
    echo "ERROR: Common IPs environment is not initialized."
    echo
    echo "Please run:"
    echo "    source set_env.sh"
    echo
    exit 1
fi

ROOT_DIR="${COMMON_IPS_HOME}"
TOOL_DIR="${TOOL_HOME}"

JOBS="${JOBS:-$(nproc)}"

echo "============================================================"
echo " Building Common IPs toolchain"
echo "============================================================"
echo "ROOT : ${ROOT_DIR}"
echo "TOOL : ${TOOL_DIR}"
echo "JOBS : ${JOBS}"
echo "============================================================"


# ============================================================
# Helper
# ============================================================

clone_repo()
{
    local url="$1"
    local dir="$2"

    if [[ -d "${dir}/.git" ]]; then
        echo "[SKIP] Source already exists: ${dir}"
    else
        echo "[CLONE] ${url}"
        git clone --depth 1 --recurse-submodules "${url}" "${dir}"
    fi
}


# ============================================================
# Yosys
# ============================================================

echo
echo "[1/6] Building Yosys"

if [[ -x "${YOSYS_HOME}/install/bin/yosys" ]]; then

    echo "[SKIP] Yosys already built"

else

    clone_repo \
        "https://github.com/YosysHQ/yosys.git" \
        "${YOSYS_HOME}"

    cd "${YOSYS_HOME}"

    git submodule update --init --recursive

    cmake -B build . \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${YOSYS_HOME}/install"

    cmake --build build \
        --config Release \
        --parallel "${JOBS}"

    cmake --install build

fi


# ============================================================
# ABC
# ============================================================

echo
echo "[2/6] Building ABC"

if [[ -x "${ABC_HOME}/abc" ]]; then

    echo "[SKIP] ABC already built"

else

    clone_repo \
        "https://github.com/berkeley-abc/abc.git" \
        "${ABC_HOME}"

    cd "${ABC_HOME}"

    make -j"${JOBS}"

fi


# ============================================================
# Verilator
# ============================================================

echo
echo "[3/6] Building Verilator"

if [[ -x "${VERILATOR_HOME}/install/bin/verilator" ]]; then

    echo "[SKIP] Verilator already built"

else

    clone_repo \
        "https://github.com/verilator/verilator.git" \
        "${VERILATOR_HOME}"

    cd "${VERILATOR_HOME}"

    autoconf

    ./configure \
        --prefix="${VERILATOR_HOME}/install"

    make -j"${JOBS}"

    make install

fi


# ============================================================
# Icarus Verilog
# ============================================================

echo
echo "[4/6] Building Icarus Verilog"

if [[ -x "${IVERILOG_HOME}/install/bin/iverilog" ]]; then

    echo "[SKIP] Icarus Verilog already built"

else

    clone_repo \
        "https://github.com/steveicarus/iverilog.git" \
        "${IVERILOG_HOME}"

    cd "${IVERILOG_HOME}"

    sh autoconf.sh

    ./configure \
        --prefix="${IVERILOG_HOME}/install"

    make -j"${JOBS}"

    make install

fi


# ============================================================
# OpenSTA
# ============================================================

echo
echo "[5/6] Building OpenSTA"

if [[ -x "${OPENSTA_HOME}/build/sta" ]]; then

    echo "[SKIP] OpenSTA already built"

else

    clone_repo \
        "https://github.com/The-OpenROAD-Project/OpenSTA.git" \
        "${OPENSTA_HOME}"

    cd "${OPENSTA_HOME}"

    git submodule update --init --recursive

    # --------------------------------------------------------
    # CUDD
    # --------------------------------------------------------

    CUDD_HOME="${OPENSTA_HOME}/cudd"
    CUDD_INSTALL="${CUDD_HOME}/install"

    if [[ ! -f "${CUDD_INSTALL}/include/cudd.h" ]]; then

        echo "[BUILD] CUDD"

        if [[ ! -d "${CUDD_HOME}/.git" ]]; then

            echo "[CLONE] CUDD"

            git clone \
                --depth 1 \
                --branch 3.0.0 \
                "https://github.com/cuddorg/cudd.git" \
                "${CUDD_HOME}"

        fi

        cd "${CUDD_HOME}"

        autoreconf -fi

        ./configure \
            --prefix="${CUDD_INSTALL}"

        make -j"${JOBS}"
        make install

    else

        echo "[SKIP] CUDD already built"

    fi

    # --------------------------------------------------------
    # OpenSTA
    # --------------------------------------------------------

    cd "${OPENSTA_HOME}"

    cmake -S . \
        -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCUDD_DIR="${CUDD_INSTALL}"

    cmake --build build \
        --parallel "${JOBS}"

fi


# ============================================================
# Surfer
# ============================================================

echo
echo "[6/6] Building Surfer"

if [[ -x "${SURFER_HOME}/install/bin/surfer" ]]; then

    echo "[SKIP] Surfer already built"

else

    # --------------------------------------------------------
    # Rust / Cargo
    # --------------------------------------------------------

    if ! command -v cargo >/dev/null 2>&1; then

        echo "[DEPENDENCY] Rust / Cargo not found"
        echo "[INSTALL] Rust"

        curl --proto '=https' \
             --tlsv1.2 \
             -sSf \
             https://sh.rustup.rs | \
            sh -s -- -y

        source "${HOME}/.cargo/env"

    else

        echo "[SKIP] Rust / Cargo already installed"

    fi

    # --------------------------------------------------------
    # Surfer
    # --------------------------------------------------------

    clone_repo \
        "https://gitlab.com/surfer-project/surfer.git" \
        "${SURFER_HOME}"

    cd "${SURFER_HOME}"

    git submodule update --init --recursive

    cargo build \
        --release

    mkdir -p "${SURFER_HOME}/install/bin"

    cp \
        target/release/surfer \
        "${SURFER_HOME}/install/bin/surfer"

fi

# ============================================================
# Verification
# ============================================================

echo
echo "============================================================"
echo " Verifying toolchain"
echo "============================================================"

FAILED=0

run_test()
{
    local name="$1"
    shift

    printf "  %-12s " "${name}"

    if "$@" >/dev/null 2>&1; then
        echo "PASS"
    else
        echo "FAIL"
        FAILED=1
    fi
}


# ------------------------------------------------------------
# Yosys
# ------------------------------------------------------------

run_test "yosys" \
    "${YOSYS_HOME}/install/bin/yosys" \
    -V


# ------------------------------------------------------------
# Yosys-ABC
# ------------------------------------------------------------

run_test "yosys-abc" \
    "${YOSYS_HOME}/install/bin/yosys-abc" \
    -c "quit"


# ------------------------------------------------------------
# ABC
# ------------------------------------------------------------

run_test "abc" \
    "${ABC_HOME}/abc" \
    -c "quit"


# ------------------------------------------------------------
# Verilator
# ------------------------------------------------------------

run_test "verilator" \
    "${VERILATOR_HOME}/install/bin/verilator" \
    --version


# ------------------------------------------------------------
# Icarus Verilog
# ------------------------------------------------------------

run_test "iverilog" \
    "${IVERILOG_HOME}/install/bin/iverilog" \
    -V


# ------------------------------------------------------------
# OpenSTA
# ------------------------------------------------------------

run_test "sta" \
    "${OPENSTA_HOME}/build/sta" \
    -version


# ------------------------------------------------------------
# Surfer
# ------------------------------------------------------------

run_test "surfer" \
    "${SURFER_HOME}/install/bin/surfer" \
    --version


# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

echo
echo "============================================================"

if [[ "${FAILED}" -eq 0 ]]; then
    echo " Toolchain verification: PASS"
    echo "============================================================"
else
    echo " Toolchain verification: FAIL"
    echo "============================================================"
    exit 1
fi
