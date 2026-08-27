#!/usr/bin/env bash
#
# tool_versions.sh
#
# Centralized configuration for the pinned Common-IP toolchain.
#
# This file ONLY defines versions/commits and upstream source locations.
# It does not build, install, or export environment paths — see set_env.sh
# for that. Tool versions must be maintained ONLY here.
#
# Intended usage: sourced by scripts/build_tools.sh
#   source "${COMMON_IPS_HOME}/scripts/tool_versions.sh"

# Guard against being executed directly instead of sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "tool_versions.sh must be sourced, not executed." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Pinned versions / commits
# ---------------------------------------------------------------------------

export VERILATOR_VERSION="99c6f9ced88a43eff7b4bd8f21b9e1f13dd0b7ff"
export SURFER_VERSION="86eedfd0cda70fc0a61ab200ebf37aabf97c5cde"
export YOSYS_VERSION="13b43f8c85ec430a33ee55d058fb4c32b42b6910"
export OPENSTA_VERSION="d1b2b3962cd47539c748bb163da5de2bd5d2f85f"
export CUDD_VERSION="3.0.0"

# ---------------------------------------------------------------------------
# Upstream source locations
# ---------------------------------------------------------------------------

export VERILATOR_REPO="https://github.com/verilator/verilator.git"
export SURFER_REPO="https://gitlab.com/surfer-project/surfer.git"
export YOSYS_REPO="https://github.com/YosysHQ/yosys.git"
export OPENSTA_REPO="https://github.com/The-OpenROAD-Project/OpenSTA.git"

# CUDD is distributed as a tagged release tarball, not pulled from a
# rolling git history, so it is versioned via a release string.
export CUDD_URL="https://github.com/The-OpenROAD-Project/cudd/archive/refs/tags/${CUDD_VERSION}.tar.gz"

# ---------------------------------------------------------------------------
# Convenience: ordered tool list used by build_tools.sh / check_tools.sh
# so both scripts iterate in a single, consistent order.
# ---------------------------------------------------------------------------

export COMMON_IP_TOOL_ORDER=(verilator surfer yosys opensta)
