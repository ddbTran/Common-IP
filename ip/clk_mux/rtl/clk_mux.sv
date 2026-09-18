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
logic in_and1,   in_and2;
logic out_sync1, out_sync2;
logic out_flop1, out_flop2;
logic out_and1,  out_and2;
logic out_icg1,  out_icg2;

// --- Combinational logic ---
assign in_and1  = !i_sel    & !out_flop2;
assign in_and2  =  i_sel    & !out_flop1;

// --- Sequential logic ---
synchronizer #(
    .DEPTH(2),
    .RST_VALUE(1'b0)
) synchronizer1 (
    .clk_i(i_clk1),
    .rst_ni(i_reset1),
    .data_i(in_and1),
    .data_o(out_sync1)
);

synchronizer #(
    .DEPTH(2),
    .RST_VALUE(1'b0)
) synchronizer2 (
    .clk_i(i_clk2),
    .rst_ni(i_reset2),
    .data_i(in_and2),
    .data_o(out_sync2)
);

always_ff @(posedge i_clk1 or negedge i_reset1) begin
    if (!i_reset1)
        out_flop1 <= 0;
    else
        out_flop1 <= out_sync1;
end

always_ff @(posedge i_clk2 or negedge i_reset2) begin
    if (!i_reset2)
        out_flop2 <= 0;
    else
        out_flop2 <= out_sync2;
end

clk_gate clk_gate1 (.clk_i(i_clk1), .en_i(out_sync1), .clk_o(out_icg1));
clk_gate clk_gate2 (.clk_i(i_clk2), .en_i(out_sync2), .clk_o(out_icg2));

assign o_clk = out_icg1 | out_icg2;

endmodule
