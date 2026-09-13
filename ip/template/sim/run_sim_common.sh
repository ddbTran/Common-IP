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
cd "${IP_HOME}/sim"

verilator \
    --binary \
    --timing \
    --trace-fst \
    --no-sched-zero-delay \
    --top-module "${TOP_MODULE}" \
    -f "${IP_HOME}/sim/filelist_sim.f" \
    -Mdir "${IP_HOME}/sim/out/obj_dir" \
    -o "${IP_HOME}/sim/out/obj_dir/${TOP_MODULE}"

"${IP_HOME}/sim/out/obj_dir/${TOP_MODULE}"
