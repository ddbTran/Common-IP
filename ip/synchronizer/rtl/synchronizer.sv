// ============================================================================
// Module      : synchronizer
// Description : Multi-stage clock-domain synchronizer
// Author      : Dat Tran
// ============================================================================

`timescale 1ns/1ps

module synchronizer #(
    // Configurable Parameters
    parameter int unsigned DEPTH     = 2,
    parameter logic        RST_VALUE = 1'b0,

    // Derived Parameters
    localparam int unsigned SYNC_DEPTH = (DEPTH < 2) ? 2 : DEPTH
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic data_i,
    output logic data_o
);

    logic [SYNC_DEPTH-1:0] sync_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            sync_q <= {SYNC_DEPTH{RST_VALUE}};
        end
        else begin
            sync_q[0] <= data_i;

            for (int unsigned i = 1; i < SYNC_DEPTH; i++)
                sync_q[i] <= sync_q[i-1];
        end
    end

    assign data_o = sync_q[SYNC_DEPTH-1];

    initial begin
        if (DEPTH < 2)
            $warning("DEPTH < 2, using 2 stages");
    end

endmodule
