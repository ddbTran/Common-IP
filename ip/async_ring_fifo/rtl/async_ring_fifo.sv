// ============================================================================
// Module      : async_ring_fifo
// Description : Asynchronous FIFO using status bit for each slot 
// Author      : Dat Tran <dat.trantan.business@gmail.com>
// ============================================================================

`timescale 1ns/1ps

module async_ring_fifo #(
    parameter WIDTH = 32,
    parameter DEPTH = 8
) (
    input  logic             clk_wr_i,
    input  logic             rst_wr_ni,
    input  logic             clk_rd_i,
    input  logic             rst_rd_ni,

    input  logic [WIDTH-1:0] wr_data_i,
    input  logic             wren_i,
    output logic             full_o,
    output logic             ready_o,

    output logic [WIDTH-1:0] rd_data_o,
    input  logic             rden_i,
    output logic             empty_o,
    output logic             valid_o
);

    // --- Declarations ---
    logic [WIDTH-1:0] data_q [DEPTH];

    logic [DEPTH-1:0] wr_status_q;
    logic [DEPTH-1:0] rd_status_q;

    logic [DEPTH-1:0] rd_status_sync;
    logic [DEPTH-1:0] wr_status_sync;

    logic [DEPTH-1:0] wr_slot_sel;
    logic [DEPTH-1:0] rd_slot_sel;

    logic wr_accept;
    logic rd_accept;

    // --- Write clock domain ---
    synchronizer #(
        .WIDTH     (DEPTH),
        .DEPTH     (2),
        .RST_VALUE (1'b0)
    ) u_sync_rd_status (
        .clk_i  (clk_wr_i),
        .rst_ni (rst_wr_ni),
        .data_i (rd_status_q),
        .data_o (rd_status_sync)
    );

    assign wr_slot_sel[DEPTH-1:1] = wr_status_q[DEPTH-1:1] ^ wr_status_q[DEPTH-2:0];
    assign wr_slot_sel[0]         = wr_status_q[DEPTH-1] ~^ wr_status_q[0];

    assign full_o    = |(wr_slot_sel & (wr_status_q ^ rd_status_sync));
    assign ready_o   = rst_wr_ni & ~full_o;
    assign wr_accept = wren_i & ready_o;

    always_ff @(posedge clk_wr_i or negedge rst_wr_ni) begin
        if (!rst_wr_ni) begin
            wr_status_q <= '0;
        end else if (wr_accept) begin
            wr_status_q <= wr_status_q ^ wr_slot_sel;
        end
    end

    always_ff @(posedge clk_wr_i) begin
        if (wr_accept) begin
            for (int i = 0; i < DEPTH; i++) begin
                if (wr_slot_sel[i]) data_q[i] <= wr_data_i;
            end
        end
    end

    // --- Read clock domain ---
    synchronizer #(
        .WIDTH     (DEPTH),
        .DEPTH     (2),
        .RST_VALUE (1'b0)
    ) u_sync_wr_status (
        .clk_i  (clk_rd_i),
        .rst_ni (rst_rd_ni),
        .data_i (wr_status_q),
        .data_o (wr_status_sync)
    );

    assign rd_slot_sel[DEPTH-1:1] = rd_status_q[DEPTH-1:1] ^ rd_status_q[DEPTH-2:0];
    assign rd_slot_sel[0]         = rd_status_q[DEPTH-1] ~^ rd_status_q[0];

    assign empty_o   = ~|(rd_slot_sel & (wr_status_sync ^ rd_status_q));
    assign valid_o   = rst_rd_ni & ~empty_o;
    assign rd_accept = rden_i & valid_o;

    always_comb begin
        rd_data_o = '0;
        for (int i = 0; i < DEPTH; i++) begin
            if (rd_slot_sel[i])
                rd_data_o = data_q[i];
        end
    end

    always_ff @(posedge clk_rd_i or negedge rst_rd_ni) begin
        if (!rst_rd_ni) begin
            rd_status_q <= '0;
        end else if (rd_accept) begin
            rd_status_q <= rd_status_q ^ rd_slot_sel;
        end
    end

endmodule
