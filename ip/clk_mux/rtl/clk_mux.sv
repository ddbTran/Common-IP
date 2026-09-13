// ============================================================================
// Module      : clk_mux
// Description : Glitch free clock mux
// Author      : Huy Nguyen 
// ============================================================================

`timescale 1ns/1ps

module clk_mux (
    // --- Ports ---
    input  logic i_reset,
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
always @(posedge i_clk1 or negedge i_reset) begin
    if (!i_reset)
        out_flop1 <= 0;
    else
        out_flop1 <= in_and1;
end

always @(posedge i_clk2 or negedge i_reset) begin
    if (!i_reset)
        out_flop2 <= 0;
    else
        out_flop2 <= in_and2;
end

assign o_clk = out_and1 | out_and2;

endmodule
