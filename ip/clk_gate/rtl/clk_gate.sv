// ============================================================================
// Module      : clk_gate
// Description : Glitch-free clock gating
// Author      : Dat Tran
// ============================================================================

`timescale 1ns/1ps

module clk_gate (
    input  logic clk_i,
    input  logic en_i,
    output logic clk_o
);

    logic en_q;

    always_ff @(negedge clk_i) begin
        en_q <= en_i;
    end

    assign clk_o = clk_i & en_q;

endmodule
