// ============================================================================
// Module      : clk_mux
// Description : Glitch free clock mux
// Author      : Huy Nguyen 
// ============================================================================

`timescale 1ns/1ps

module clk_mux (
    // --- Ports ---
    input  logic i_reset1,
    input  logic i_reset2,
    input  logic i_clk1,
    input  logic i_clk2,
    input  logic i_sel,

    output logic o_clk
);

// --- Internal signals ---
logic in_and1,  in_and2;
logic out_flop1,out_flop2;
logic out_and1, out_and2;

// --- Combinational logic ---
assign in_and1  = !i_sel    & !out_flop2;
assign in_and2  =  i_sel    & !out_flop1;
assign out_and1 = out_flop1 &  i_clk1;
assign out_and2 = out_flop2 &  i_clk2;

// --- Sequential logic ---
synchronizer #(
    .DEPTH(2),
    .RST_VALUE(1'b0)
) synchronizer1 (
    .clk_i(i_clk1),
    .rst_ni(i_reset1),
    .data_i(in_and1),
    .data_o(out_flop1)
);

synchronizer #(
    .DEPTH(2),
    .RST_VALUE(1'b0)
) synchronizer2 (
    .clk_i(i_clk2),
    .rst_ni(i_reset2),
    .data_i(in_and2),
    .data_o(out_flop2)
);

assign o_clk = out_and1 | out_and2;

endmodule
