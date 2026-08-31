// ============================================================================
// Module      : reset_sync
// Description : Synchronizes an active-low reset signal to a clock domain.
// Author      : Dat Tran
// ============================================================================

`timescale 1ns/1ps

module reset_sync #(
    parameter int unsigned STAGES    = 2,
    parameter logic        RST_VALUE = 1'b0
) (
    input  logic clk_i,
    input  logic rst_ni,
    output logic rst_no
);

    logic [STAGES-1:0] sync_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            sync_q <= {STAGES{RST_VALUE}};
        end else begin
            sync_q <= {sync_q[STAGES-2:0], ~RST_VALUE};
        end
    end

    assign rst_no = sync_q[STAGES-1];

endmodule
