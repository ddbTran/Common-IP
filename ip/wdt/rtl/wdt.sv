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

    // --- Parameter checks ---
    generate
        if (TIMER_WIDTH < 1) begin : gen_timer_width_assert
            initial $error("TIMER_WIDTH must be >= 1");
        end

        if (KICK_WIDTH < 1) begin : gen_kick_width_assert
            initial $error("KICK_WIDTH must be >= 1");
        end
    endgenerate

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
    logic timeout_ref_q;
    logic timeout_ref_d;
    logic timeout_src;

    // --- Combinational logic ---
    assign timer_enable_re = timer_enable_sync && !timer_enable_sync_delay;
    assign timeout_cond    = (timer_q == timer_threshold_i);

    always_comb begin
        if (timer_enable_re) begin
            timer_d       = timer_default_i;       // reload when start
            timeout_ref_d = 1'b0;
        end else if (!timer_enable_sync) begin
            timer_d       = timer_q;               // stop switching for power
            timeout_ref_d =  1'b0;
        end else if (timeout_cond) begin
            timer_d       = timer_q;               // trigger level interrupt until being clear
            timeout_ref_d = 1'b1;
        end else if (!kick_capture_sync) begin
            timer_d = timer_q + 1'b1;
            timeout_ref_d = 1'b0;  
        end else begin
            timer_d = timer_default_i;
            timeout_ref_d = 1'b0;
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

    // The synchronizer is used as a asynchronous pulse catcher by connecting
    // asynchronous set to kick_event. This implementation create a pulse at reference
    // domain while avoiding removal-time violation with asynchronous deassertion.
    synchronizer #(
        .DEPTH(2),
        .RST_VALUE(1'b1)
    ) u_kick_capture (
        .clk_i(clk_ref_i),
        .rst_ni(~kick_event),
        .data_i(1'b0),
        .data_o(kick_capture)
    );

    // Synchronize the capture pulse to avoid recorvery-time violations caused
    // by asynchronous assertion of the pulse
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
            timeout_ref_q           <= 1'b0;
        end else begin
            timer_q                 <= timer_d;
            timer_enable_sync_delay <= timer_enable_sync;
            timeout_ref_q           <= timeout_ref_d;
        end
    end

    // === Clock Source Domain ===
    synchronizer #(
        .DEPTH(2),
        .RST_VALUE(1'b0)
    ) u_timeout_sync (
        .clk_i(clk_src_i),
        .rst_ni(rst_src_ni),
        .data_i(timeout_ref_q),
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
