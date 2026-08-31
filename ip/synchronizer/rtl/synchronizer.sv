// ============================================================================
// Module      : synchronizer
// Description : Multi-stage clock-domain synchronizer
// Author      : Dat Tran
// ============================================================================

`timescale 1ns/1ps

module synchronizer #(
    parameter int unsigned DEPTH     = 2,
    parameter logic        RST_VALUE = 1'b0
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic data_i,
    output logic data_o
);

    logic [DEPTH-1:0] sync_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            sync_q <= {DEPTH{RST_VALUE}};
        end else begin
            sync_q[0] <= data_i;

            for (int unsigned i = 1; i < DEPTH; i++)
                sync_q[i] <= sync_q[i-1];
        end
    end

    assign data_o = sync_q[DEPTH-1];

endmodule
