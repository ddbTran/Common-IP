`timescale 1ns/1ps

module apb_slv_if #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 32
) (
    // --- Slave clock domain ---
    input  logic                     clk_s_i,
    input  logic                     rst_s_ni,

    // --- APB4 Slave Interface ---
    input  logic [ADDR_WIDTH-1:0]    s_paddr_i,
    input  logic [2:0]               s_pprot_i,
    input  logic                     s_psel_i,
    input  logic                     s_penable_i,
    input  logic                     s_pwrite_i,
    input  logic [DATA_WIDTH-1:0]    s_pwdata_i,
    input  logic [DATA_WIDTH/8-1:0]  s_pstrb_i,
    output logic                     s_pready_o,
    output logic [DATA_WIDTH-1:0]    s_prdata_o,
    output logic                     s_pslverr_o,

    // --- Crossing Interface ---
    output logic                     s_req_o,
    output logic [ADDR_WIDTH-1:0]    s_paddr_o,
    output logic [2:0]               s_pprot_o,
    output logic                     s_pwrite_o,
    output logic [DATA_WIDTH-1:0]    s_pwdata_o,
    output logic [DATA_WIDTH/8-1:0]  s_pstrb_o,

    input  logic                     s_ack_i,
    input  logic [DATA_WIDTH-1:0]    s_prdata_i,
    input  logic                     s_pslverr_i
);

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_REQ,
        ST_ACK
    } state_t;
    state_t state_q, state_d;

    // --- Internal signals ---
    logic                     s_req_q, s_req_d;
    logic [ADDR_WIDTH-1:0]    s_paddr_q, s_paddr_d;
    logic [2:0]               s_pprot_q, s_pprot_d;
    logic                     s_pwrite_q, s_pwrite_d;
    logic [DATA_WIDTH-1:0]    s_pwdata_q, s_pwdata_d;
    logic [DATA_WIDTH/8-1:0]  s_pstrb_q, s_pstrb_d;

    logic                     s_pready_q, s_pready_d;
    logic [DATA_WIDTH-1:0]    s_prdata_q, s_prdata_d;
    logic                     s_pslverr_q, s_pslverr_d;

    logic                     s_ack_sync;

    // --- Combinational logic ---
    always_comb begin
        casez (state_q)
            ST_IDLE: begin
                if (s_psel_i && !s_penable_i) begin
                    state_d = ST_REQ;
                end else begin
                    state_d = ST_IDLE;
                end
            end
            ST_REQ: begin
                if (s_ack_sync) begin
                    state_d = ST_ACK;
                end else begin
                    state_d = ST_REQ;
                end
            end
            ST_ACK: begin
                if (!s_ack_sync) begin
                    state_d = ST_IDLE;
                end else begin
                    state_d = ST_ACK;
                end
            end
            default: begin
                state_d = ST_IDLE;
            end
        endcase
    end

    always_comb begin
        s_req_d     = s_req_q;
        s_paddr_d   = s_paddr_q;
        s_pprot_d   = s_pprot_q;
        s_pwrite_d  = s_pwrite_q;
        s_pwdata_d  = s_pwdata_q;
        s_pstrb_d   = s_pstrb_q;
        s_pready_d  = 1'b0;
        s_prdata_d  = s_prdata_q;
        s_pslverr_d = s_pslverr_q;
        casez (state_q)
            ST_IDLE: begin
                if (s_psel_i && !s_penable_i) begin
                    s_req_d     = 1'b1;
                    s_paddr_d   = s_paddr_i;
                    s_pprot_d   = s_pprot_i;
                    s_pwrite_d  = s_pwrite_i;
                    s_pwdata_d  = s_pwdata_i;
                    s_pstrb_d   = s_pstrb_i;
                end
            end
            ST_REQ: begin
                if (s_ack_sync) begin
                    s_req_d     = 1'b0;
                end
            end
            ST_ACK: begin
                if (!s_ack_sync) begin
                    s_pready_d  = 1'b1;
                    s_prdata_d  = s_prdata_i;
                    s_pslverr_d = s_pslverr_i;
                end
            end
            default: begin end
        endcase
    end

    // --- Sequential logic ---
    synchronizer #(
        .DEPTH(2),
        .RST_VALUE(1'b0)
    ) u_ack_sync (
        .clk_i(clk_s_i),
        .rst_ni(rst_s_ni),
        .data_i(s_ack_i),
        .data_o(s_ack_sync)
    );

    always_ff @(posedge clk_s_i or negedge rst_s_ni) begin
        if (!rst_s_ni) begin
            state_q     <= ST_IDLE;
            s_req_q     <= '0;
            s_paddr_q   <= '0;
            s_pprot_q   <= '0;
            s_pwrite_q  <= '0;
            s_pwdata_q  <= '0;
            s_pstrb_q   <= '0;
            s_pready_q  <= '0;
            s_prdata_q  <= '0;
            s_pslverr_q <= '0;
        end else begin
            state_q     <= state_d;
            s_req_q     <= s_req_d;
            s_paddr_q   <= s_paddr_d;
            s_pprot_q   <= s_pprot_d;
            s_pwrite_q  <= s_pwrite_d;
            s_pwdata_q  <= s_pwdata_d;
            s_pstrb_q   <= s_pstrb_d;
            s_pready_q  <= s_pready_d;
            s_prdata_q  <= s_prdata_d;
            s_pslverr_q <= s_pslverr_d;
        end
    end

    assign s_req_o     = s_req_q;
    assign s_paddr_o   = s_paddr_q;
    assign s_pprot_o   = s_pprot_q;
    assign s_pwrite_o  = s_pwrite_q;
    assign s_pwdata_o  = s_pwdata_q;
    assign s_pstrb_o   = s_pstrb_q;
    assign s_pready_o  = s_pready_q;
    assign s_prdata_o  = s_prdata_q;
    assign s_pslverr_o = s_pslverr_q;

endmodule
