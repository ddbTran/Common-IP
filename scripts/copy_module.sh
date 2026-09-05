#!/bin/bash

# -------------------------------------------------------------------------
# Preparation: Check environment variable and arguments
# -------------------------------------------------------------------------
if [ -z "${COMMON_IPS_HOME}" ]; then
    echo "Error: Environment variable COMMON_IPS_HOME is not set."
    exit 1
fi

if [ "$#" -ne 1 ]; then
    echo "Usage: ./copy_module.sh <module_name>"
    echo "Example: ./copy_module.sh clk_mux"
    exit 1
fi

MODULE_NAME="$1"
# Convert module name to uppercase (e.g., clk_mux -> CLK_MUX)
MODULE_NAME_UPPER=$(echo "$MODULE_NAME" | tr '[:lower:]' '[:upper:]')

TEMPLATE_DIR="${COMMON_IPS_HOME}/ip/template"
TARGET_DIR="${COMMON_IPS_HOME}/ip/${MODULE_NAME}"

if [ ! -d "$TEMPLATE_DIR" ]; then
    echo "Error: Template directory '$TEMPLATE_DIR' does not exist."
    exit 1
fi

# -------------------------------------------------------------------------
# Step 0: Copy the template directory to the target directory
# -------------------------------------------------------------------------
echo "=> Copying template to '$TARGET_DIR'..."
if ! cp -r "$TEMPLATE_DIR" "$TARGET_DIR"; then
    echo "Error copying directory"
    exit 1
fi

mkdir -p "${TARGET_DIR}/rtl"
mkdir -p "${TARGET_DIR}/sim"
mkdir -p "${TARGET_DIR}/syn"

# -------------------------------------------------------------------------
# Step 1: Generate RTL file (<module_name>.sv) based on Coding Style
# -------------------------------------------------------------------------
echo "=> Generating RTL file..."
cat << EOF > "${TARGET_DIR}/rtl/${MODULE_NAME}.sv"
// ============================================================================
// Module      : ${MODULE_NAME}
// Description : 
// Author      : 
// ============================================================================

\`timescale 1ns/1ps

module ${MODULE_NAME} #(
    // --- Parameters ---
    parameter int unsigned DATA_WIDTH = 32
) (
    // --- Ports ---
    input  logic clk_i,
    input  logic rst_ni
);

    // --- Internal signals ---

    // --- Combinational logic ---

    // --- Sequential logic ---

    // --- Memory / datapath ---

endmodule
EOF

# -------------------------------------------------------------------------
# Step 2: Generate Testbench file (tb_<module_name>.sv)
# -------------------------------------------------------------------------
echo "=> Generating Testbench file..."
cat << EOF > "${TARGET_DIR}/sim/tb_${MODULE_NAME}.sv"
\`timescale 1ns/1ps

module tb_${MODULE_NAME};

    // Testbench implementation

endmodule
EOF

# -------------------------------------------------------------------------
# Step 3: Modify run_sim.sh
# -------------------------------------------------------------------------
echo "=> Modifying run_sim.sh..."
RUN_SIM_FILE="${TARGET_DIR}/sim/run_sim.sh"
if [ -f "$RUN_SIM_FILE" ]; then
    sed -i "s|IP_HOME=\"\"|IP_HOME=\"\${${MODULE_NAME_UPPER}_HOME}\"|g" "$RUN_SIM_FILE"
    sed -i "s|TOP_MODULE=\"\"|TOP_MODULE=\"tb_${MODULE_NAME}\"|g" "$RUN_SIM_FILE"
else
    echo "   [Warning] run_sim.sh not found in ${TEMPLATE_DIR}/sim/!"
fi

# -------------------------------------------------------------------------
# Step 4: Modify run_syn.sh
# -------------------------------------------------------------------------
echo "=> Modifying run_syn.sh..."
RUN_SYN_FILE="${TARGET_DIR}/syn/run_syn.sh"
if [ -f "$RUN_SYN_FILE" ]; then
    sed -i "s|SYN_TOP=\"\"|SYN_TOP=\"${MODULE_NAME}\"|g" "$RUN_SYN_FILE"
    sed -i "s|IP_HOME=\"\${IP_HOME}\"|IP_HOME=\"\${${MODULE_NAME_UPPER}_HOME}\"|g" "$RUN_SYN_FILE"
else
    echo "   [Warning] run_syn.sh not found in ${TEMPLATE_DIR}/syn/!"
fi

# -------------------------------------------------------------------------
# Step 5: Generate rtl/filelist.f
# -------------------------------------------------------------------------
echo "=> Generating RTL filelist..."
cat << EOF > "${TARGET_DIR}/rtl/filelist.f"
\$${MODULE_NAME_UPPER}_HOME/rtl/${MODULE_NAME}.sv
EOF

# -------------------------------------------------------------------------
# Step 6: Generate sim/filelist_sim.f
# -------------------------------------------------------------------------
echo "=> Generating Simulation filelist..."
cat << EOF > "${TARGET_DIR}/sim/filelist_sim.f"
-f \$${MODULE_NAME_UPPER}_HOME/rtl/filelist.f
\$${MODULE_NAME_UPPER}_HOME/sim/tb_${MODULE_NAME}.sv
EOF

# -------------------------------------------------------------------------
# Step 6.5: Modify syn/filelist_syn.f
# -------------------------------------------------------------------------
echo "=> Modifying Synthesis filelist..."
FILELIST_SYN_FILE="${TARGET_DIR}/syn/filelist_syn.f"
if [ -f "$FILELIST_SYN_FILE" ]; then
    sed -i "s|\${IP_HOME}/rtl/filelist.f|\${${MODULE_NAME_UPPER}_HOME}/rtl/filelist.f|g" "$FILELIST_SYN_FILE"
else
    echo "   [Warning] filelist_syn.f not found in ${TEMPLATE_DIR}/syn/!"
fi

# -------------------------------------------------------------------------
# Step 7: Update set_env.sh (Smart Append under # IP section)
# -------------------------------------------------------------------------
echo "=> Updating set_env.sh..."
ENV_FILE="${COMMON_IPS_HOME}/set_env.sh"
if [ -f "$ENV_FILE" ]; then
    EXPORT_LINE="export ${MODULE_NAME_UPPER}_HOME=\"\${IP_HOME}/${MODULE_NAME}\""
    
    if grep -Fq "$EXPORT_LINE" "$ENV_FILE"; then
        echo "   Environment variable already exists in set_env.sh. Skipping."
    else
        INSERT_LINE=-1
        IN_IP_SECTION=0
        LINE_NUM=0
        
        while IFS= read -r line || [ -n "$line" ]; do
            LINE_NUM=$((LINE_NUM + 1))
            
            # Nhận diện vùng "# IP"
            if [[ "$line" == *"# IP"* ]]; then
                IN_IP_SECTION=1
                INSERT_LINE=$LINE_NUM
                continue
            fi
            
            # Quét các dòng nằm trong vùng "# IP"
            if [ $IN_IP_SECTION -eq 1 ]; then
                # Thoát nếu gặp vùng mới bắt đầu bằng "# "
                if [[ "$line" =~ ^#\ [A-Za-z] ]] && [[ "$line" != *"# IP"* ]]; then
                    break
                fi
                # Cập nhật vị trí insert xuống dòng export cuối cùng
                if [[ "$line" == "export "* ]]; then
                    INSERT_LINE=$LINE_NUM
                fi
            fi
        done < "$ENV_FILE"
        
        if [ $INSERT_LINE -ne -1 ]; then
            # Dùng awk để chèn dòng vào sau INSERT_LINE
            awk -v n="$INSERT_LINE" -v s="$EXPORT_LINE" 'NR==n {print $0; print s; next} 1' "$ENV_FILE" > "${ENV_FILE}.tmp" && mv "${ENV_FILE}.tmp" "$ENV_FILE"
            echo "   Added '${EXPORT_LINE}' to set_env.sh."
        else
            echo "   [Warning] Marker '# IP' not found! Appending to the end of set_env.sh."
            echo "" >> "$ENV_FILE"
            echo "$EXPORT_LINE" >> "$ENV_FILE"
        fi
    fi
else
    echo "   [Warning] set_env.sh not found at '${COMMON_IPS_HOME}'!"
fi

echo "=> DONE! Module '$MODULE_NAME' generated successfully at '$TARGET_DIR'."
