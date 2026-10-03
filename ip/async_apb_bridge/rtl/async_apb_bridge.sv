// ============================================================================
// Module      : async_apb_bridge
// Description : Asynchronous APB Bridge
// Author      : Dat Tran <dat.trantan.business@gmail.com>
// ============================================================================
`timescale 1ns/1ps

module async_apb_bridge #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 32
) (
    // --- Master clock domain ---
    input  logic                     clk_m_i,
    input  logic                     rst_m_ni,

    // --- Slave clock domain ---
    input  logic                     clk_s_i,
    input  logic                     rst_s_ni,

    // --- APB4 Master Interface ---
    output logic [ADDR_WIDTH-1:0]    m_paddr_o,
    output logic [2:0]               m_pprot_o,
    output logic                     m_psel_o,
    output logic                     m_penable_o,
    output logic                     m_pwrite_o,
    output logic [DATA_WIDTH-1:0]    m_pwdata_o,
    output logic [DATA_WIDTH/8-1:0]  m_pstrb_o,
    input  logic                     m_pready_i,
    input  logic [DATA_WIDTH-1:0]    m_prdata_i,
    input  logic                     m_pslverr_i,

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
    output logic                     s_pslverr_o
);

    // Parameter checks
    generate
        if (DATA_WIDTH < 8 || DATA_WIDTH % 8 != 0) begin : gen_data_width_assert
            initial $error("DATA_WIDTH must be byte-aligned and >= 8");
        end

        if (ADDR_WIDTH < 1) begin : gen_addr_width_assert
            initial $error("ADDR_WIDTH must be >= 1");
        end
    endgenerate

    // --- Internal signals ---
    // CDC request channel
    logic                     cdc_req_w;
    logic [ADDR_WIDTH-1:0]    cdc_paddr_w;
    logic [2:0]               cdc_pprot_w;
    logic                     cdc_pwrite_w;
    logic [DATA_WIDTH-1:0]    cdc_pwdata_w;
    logic [DATA_WIDTH/8-1:0]  cdc_pstrb_w;

    // CDC response channel
    logic                     cdc_ack_w;
    logic [DATA_WIDTH-1:0]    cdc_prdata_w;
    logic                     cdc_pslverr_w;

    apb_mstr_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_apb_mstr_if (
        .clk_m_i      (clk_m_i),
        .rst_m_ni     (rst_m_ni),

        .m_paddr_o    (m_paddr_o),
        .m_pprot_o    (m_pprot_o),
        .m_psel_o     (m_psel_o),
        .m_penable_o  (m_penable_o),
        .m_pwrite_o   (m_pwrite_o),
        .m_pwdata_o   (m_pwdata_o),
        .m_pstrb_o    (m_pstrb_o),

        .m_pready_i   (m_pready_i),
        .m_prdata_i   (m_prdata_i),
        .m_pslverr_i  (m_pslverr_i),

        .m_req_i      (cdc_req_w),
        .m_paddr_i    (cdc_paddr_w),
        .m_pprot_i    (cdc_pprot_w),
        .m_pwrite_i   (cdc_pwrite_w),
        .m_pwdata_i   (cdc_pwdata_w),
        .m_pstrb_i    (cdc_pstrb_w),

        .m_ack_o      (cdc_ack_w),
        .m_prdata_o   (cdc_prdata_w),
        .m_pslverr_o  (cdc_pslverr_w)
    );

    apb_slv_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_apb_slv_if (
        .clk_s_i      (clk_s_i),
        .rst_s_ni     (rst_s_ni),

        .s_paddr_i    (s_paddr_i),
        .s_pprot_i    (s_pprot_i),
        .s_psel_i     (s_psel_i),
        .s_penable_i  (s_penable_i),
        .s_pwrite_i   (s_pwrite_i),
        .s_pwdata_i   (s_pwdata_i),
        .s_pstrb_i    (s_pstrb_i),

        .s_pready_o   (s_pready_o),
        .s_prdata_o   (s_prdata_o),
        .s_pslverr_o  (s_pslverr_o),

        .s_req_o      (cdc_req_w),
        .s_paddr_o    (cdc_paddr_w),
        .s_pprot_o    (cdc_pprot_w),
        .s_pwrite_o   (cdc_pwrite_w),
        .s_pwdata_o   (cdc_pwdata_w),
        .s_pstrb_o    (cdc_pstrb_w),

        .s_ack_i      (cdc_ack_w),
        .s_prdata_i   (cdc_prdata_w),
        .s_pslverr_i  (cdc_pslverr_w)
    );

endmodule
