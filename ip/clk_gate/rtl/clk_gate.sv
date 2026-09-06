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
    /* verilator lint_off COMBDLY */
    always_latch begin
        if (clk_i == 1'b0) en_q = en_i;
    end
    /* verilator lint_on COMBDLY */
    assign clk_o = clk_i & en_q;

endmodule
