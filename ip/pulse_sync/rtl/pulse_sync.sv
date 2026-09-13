// ============================================================================
// Module      : pulse_sync
// Description : Pulse Signal Synchronizer Between Different Clock Domain
// Author      : Dat Tran <dat.trantan.business@gmail.com> 
// ============================================================================

`timescale 1ns/1ps

module pulse_sync (
    // --- Ports ---
    // --- Source Clock Domain ---
    input  logic clk_src_i,
    input  logic rst_src_ni,
    input  logic pulse_i,
    output logic ready_o,

    // --- Destination Clock Domain ---
    input  logic clk_dst_i,
    input  logic rst_dst_ni,
    output logic pulse_o
);

    // --- Internal signals ---
    logic pulse_detect;

    logic pulse_delay_q, pulse_delay_d;
    logic req_q, req_d;
    logic ack_sync_q, ack_sync_d;
    
    logic req_sync_q, req_sync_d;
    logic req_sync_delay_q, req_sync_delay_d;

    // --- Combinational logic ---
    assign pulse_detect = !pulse_delay_q && pulse_i;

    always_comb begin
        pulse_delay_d    = pulse_i;
        req_d            = req_q;
        ack_sync_d       = req_sync_delay_q;
        req_sync_d       = req_q;
        req_sync_delay_d = req_sync_q;
        if (req_q ^ ack_sync_q) begin
            req_d = req_q;
        end else if (pulse_detect) begin
            req_d = ~req_q;
        end
    end

    // === Source Clock Domain ===
    // --- Sequential logic ---
    always_ff @(posedge clk_src_i or negedge rst_src_ni) begin
        if (!rst_src_ni) begin
            pulse_delay_q  <= '0;
            req_q    <= '0;
        end else begin
            pulse_delay_q  <= pulse_delay_d;
            req_q    <= req_d;
        end
    end
    
    synchronizer #(
        .DEPTH(2),
        .RST_VALUE(1'b0)
    ) u_ack_sync (
        .clk_i(clk_src_i),
        .rst_ni(rst_src_ni),
        .data_i(ack_sync_d),
        .data_o(ack_sync_q)
    );

    // === Destination Clock Domain ===
    // --- Sequential logic ---
    synchronizer #(
        .DEPTH(2),
        .RST_VALUE(1'b0)
    ) u_req_sync (
        .clk_i(clk_dst_i),
        .rst_ni(rst_dst_ni),
        .data_i(req_sync_d),
        .data_o(req_sync_q)
    );

    always_ff @(posedge clk_dst_i or negedge rst_dst_ni) begin
        if (!rst_dst_ni) begin
            req_sync_delay_q <= '0;
        end else begin
            req_sync_delay_q <= req_sync_delay_d;
        end
    end
    
    // --- Output Logic ---
    assign pulse_o = req_sync_delay_q ^ req_sync_q;
    assign ready_o = !(req_q ^ ack_sync_q);

endmodule
