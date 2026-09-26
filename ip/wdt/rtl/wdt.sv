// ============================================================================
// Module      : wdt
// Description : Watchdog Timer
// Author      : Dat Tran <dat.trantan.business@gmail.com>
// ============================================================================

`timescale 1ns/1ps

module wdt #(
    // --- Parameters ---
    parameter int unsigned TIMER_WIDTH = 16,
    parameter int unsigned KICK_WIDTH  =  8
) (
    // --- Configuration Clock Domain ---
    input  logic [TIMER_WIDTH-1:0] timer_default_i,
    input  logic [TIMER_WIDTH-1:0] timer_threshold_i,
    input  logic                   timer_enable_i,
    input  logic [KICK_WIDTH-1 :0] kick_key_i,

    // --- Source Clock Domain ---
    input  logic                   clk_src_i,
    input  logic                   rst_src_ni,
    input  logic [KICK_WIDTH-1 :0] kick_i,

    output logic                   timeout_irq_o,

    // --- Reference Clock Domain ---
    input  logic                   clk_ref_i,
    input  logic                   rst_ref_ni
);

    // --- Internal signals ---
    logic timer_enable_sync;
    logic timer_enable_sync_delay;
    logic timer_enable_re; // enable rising edge
    logic kick_event;
    logic kick_capture;
    logic kick_capture_sync;
    logic [TIMER_WIDTH-1:0] timer_q;
    logic [TIMER_WIDTH-1:0] timer_d;
    logic timeout_cond;
    logic timeout_ref;
    logic timeout_src;

    // --- Combinational logic ---
    always_comb begin
        timer_enable_re = timer_enable_sync && !timer_enable_sync_delay;
        timeout_cond    = (timer_q == timer_threshold_i);
        timer_d         = timer_q;
        if (timer_enable_re) begin
            timer_d = timer_default_i;       // reload when start
        end else if (!timer_enable_sync) begin
            timer_d = timer_q;               // stop switching for power
        end else if (timeout_cond) begin
            timer_d = timer_q;               // trigger level interrupt until being clear
        end else if (!kick_capture_sync) begin
            timer_d = timer_q + 1;
        end else begin
            timer_d = timer_default_i;
        end
    end

    // --- Sequential Logic ---
    // === Clock Reference Domain ===
    synchronizer #(
        .DEPTH(2),
        .RST_VALUE(1'b0)
    ) u_enable_sync (
        .clk_i(clk_ref_i),
        .rst_ni(rst_ref_ni),
        .data_i(timer_enable_i),
        .data_o(timer_enable_sync)
    );

    synchronizer #(
        .DEPTH(2),
        .RST_VALUE(1'b1)
    ) u_kick_capture (
        .clk_i(clk_ref_i),
        .rst_ni(~kick_event),
        .data_i(1'b0),
        .data_o(kick_capture)
    );

    synchronizer #(
        .DEPTH(2),
        .RST_VALUE(1'b0)
    ) u_kick_sync (
        .clk_i(clk_ref_i),
        .rst_ni(rst_ref_ni),
        .data_i(kick_capture),
        .data_o(kick_capture_sync)
    );
    
    always_ff @(posedge clk_ref_i or negedge rst_ref_ni) begin
        if (!rst_ref_ni) begin
            timer_q                 <= '0;
            timer_enable_sync_delay <= 1'b0;
            timeout_ref             <= 1'b0;
        end else begin
            timer_q                 <= timer_d;
            timer_enable_sync_delay <= timer_enable_sync;
            if (!timer_enable_sync_delay) begin
                timeout_ref <= 1'b0;
            end else if (timeout_cond) begin
                timeout_ref <= 1'b1;
            end
        end
    end

    // === Clock Source Domain ===
    synchronizer #(
        .DEPTH(2),
        .RST_VALUE(1'b0)
    ) u_timeout_sync (
        .clk_i(clk_src_i),
        .rst_ni(rst_src_ni),
        .data_i(timeout_ref),
        .data_o(timeout_src)
    );

    always_ff @(posedge clk_src_i or negedge rst_src_ni) begin
        if (!rst_src_ni) begin
            kick_event <= 1'b0;
        end else begin
            kick_event <= (kick_i == kick_key_i) ? 1'b1 : 1'b0;
        end
    end

    // --- Output signals ---
    assign timeout_irq_o = timeout_src;

endmodule
