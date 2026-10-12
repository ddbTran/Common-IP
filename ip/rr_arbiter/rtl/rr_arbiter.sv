// ============================================================================
// Module      : rr_arbiter
// Description : Round-robin arbiter, mask method with the pointer stored as
//               the mask (Weber, SNUG 2001, Listing 12)
// Author      : Huy Nguyen
// ============================================================================

`timescale 1ns/1ps

module rr_arbiter #(
    // --- Parameters ---
    parameter int unsigned NUM_REQ = 4
) (
    // --- Ports ---
    input  logic               clk_i,
    input  logic               rst_ni,
    input  logic [NUM_REQ-1:0] req_i,
    output logic [NUM_REQ-1:0] grant_o
);

// --- Internal signals ---
logic [NUM_REQ-1:0] mask_q, mask_d;
logic [NUM_REQ-1:0] req_masked;
logic [NUM_REQ-1:0] mask_higher_pri_reqs, unmask_higher_pri_reqs;
logic [NUM_REQ-1:0] grant_masked, grant_unmasked;
logic               no_req_masked;
logic               any_req;

// --- Combinational logic ---
assign req_masked = req_i & mask_q;

// x - 1 flips every bit up to the lowest set bit, so ~(x ^ (x - 1))
// keeps only the bits above it: the higher_pri_reqs vector of Listing 5
assign mask_higher_pri_reqs   = ~(req_masked ^ (req_masked - NUM_REQ'(1)));
assign unmask_higher_pri_reqs = ~(req_i ^ (req_i - NUM_REQ'(1)));

assign grant_masked   = req_masked & ~mask_higher_pri_reqs;
assign grant_unmasked = req_i & ~unmask_higher_pri_reqs;

assign no_req_masked = ~|req_masked;
assign any_req       = |req_i;

assign grant_o = grant_masked | (grant_unmasked & {NUM_REQ{no_req_masked}});

// Next mask: the winner's higher_pri_reqs, hold when nobody requests
always @(*) begin
    if (!no_req_masked)
        mask_d = mask_higher_pri_reqs;
    else if (any_req)
        mask_d = unmask_higher_pri_reqs;
    else
        mask_d = mask_q;
end

// --- Sequential logic ---
always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        mask_q <= '1;
    end else begin
        mask_q <= mask_d;
    end
end

endmodule
