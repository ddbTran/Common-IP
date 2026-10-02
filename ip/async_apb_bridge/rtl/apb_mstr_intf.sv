`timescale 1ns/1ps

module apb_mstr_if #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 32
) (
    // --- Master clock domain ---
    input  logic                     clk_m_i,
    input  logic                     rst_m_ni,

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

    // --- Crossing Interface ---
    input  logic                     m_req_i,
    input  logic [ADDR_WIDTH-1:0]    m_paddr_i,
    input  logic [2:0]               m_pprot_i,
    input  logic                     m_pwrite_i,
    input  logic [DATA_WIDTH-1:0]    m_pwdata_i,
    input  logic [DATA_WIDTH/8-1:0]  m_pstrb_i,

    output logic                     m_ack_o,
    output logic [DATA_WIDTH-1:0]    m_prdata_o,
    output logic                     m_pslverr_o
);

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_SETUP,
        ST_ACCESS,
        ST_WAIT
    } state_t;
    state_t state_q, state_d;

    // --- Internal signals ---
    logic                     m_psel_q, m_psel_d;
    logic                     m_penable_q, m_penable_d;
    logic [ADDR_WIDTH-1:0]    m_paddr_q, m_paddr_d;
    logic [2:0]               m_pprot_q, m_pprot_d;
    logic                     m_pwrite_q, m_pwrite_d;
    logic [DATA_WIDTH-1:0]    m_pwdata_q, m_pwdata_d;
    logic [DATA_WIDTH/8-1:0]  m_pstrb_q, m_pstrb_d;

    logic                     m_ack_q, m_ack_d;
    logic [DATA_WIDTH-1:0]    m_prdata_q, m_prdata_d;
    logic                     m_pslverr_q, m_pslverr_d;

    logic                     m_req_sync;

    // --- Combinational logic ---
    always_comb begin
        casez (state_q)
            ST_IDLE: begin
                if (m_req_sync) begin
                    state_d = ST_SETUP;
                end else begin
                    state_d = ST_IDLE;
                end
            end
            ST_SETUP: begin
                state_d = ST_ACCESS;
            end
            ST_ACCESS: begin
                if (m_pready_i) begin
                    state_d = ST_WAIT;
                end else begin
                    state_d = ST_ACCESS;
                end
            end
            ST_WAIT: begin
                if (!m_req_sync) begin
                    state_d = ST_IDLE;
                end else begin
                    state_d = ST_WAIT;
                end
            end
            default: begin
                state_d = ST_IDLE;
            end
        endcase
    end

    always_comb begin
        m_psel_d    = m_psel_q;
        m_penable_d = m_penable_q;
        m_paddr_d   = m_paddr_q;
        m_pprot_d   = m_pprot_q;
        m_pwrite_d  = m_pwrite_q;
        m_pwdata_d  = m_pwdata_q;
        m_pstrb_d   = m_pstrb_q;
        m_ack_d     = m_ack_q;
        m_prdata_d  = m_prdata_q;
        m_pslverr_d = m_pslverr_q;
        casez (state_q)
            ST_IDLE: begin
                if (m_req_sync) begin
                    m_psel_d    = 1'b1;
                    m_penable_d = 1'b0;
                    m_paddr_d   = m_paddr_i;
                    m_pprot_d   = m_pprot_i;
                    m_pwrite_d  = m_pwrite_i;
                    m_pwdata_d  = m_pwdata_i;
                    m_pstrb_d   = m_pstrb_i;
                end else begin
                    m_psel_d    = 1'b0;
                    m_penable_d = 1'b0;
                end
            end
            ST_SETUP: begin
                    m_psel_d    = 1'b1;
                    m_penable_d = 1'b1;            
            end
            ST_ACCESS: begin
                if (m_pready_i) begin
                    m_psel_d    = 1'b0;
                    m_penable_d = 1'b0;
                    m_ack_d     = 1'b1;
                    m_prdata_d  = m_prdata_i;
                    m_pslverr_d = m_pslverr_i;
                end
            end
            ST_WAIT: begin
                if (!m_req_sync) begin
                    m_ack_d    = 1'b0;
                end
            end
        endcase
    end

    // --- Sequential logic ---
    synchronizer #(
        .DEPTH(2),
        .RST_VALUE(1'b0)
    ) u_req_sync (
        .clk_i(clk_m_i),
        .rst_ni(rst_m_ni),
        .data_i(m_req_i),
        .data_o(m_req_sync)
    );

    always_ff @(posedge clk_m_i or negedge rst_m_ni) begin
        if (!rst_m_ni) begin
            state_q     <= ST_IDLE;
            m_psel_q    <= '0;
            m_penable_q <= '0;
            m_paddr_q   <= '0;
            m_pprot_q   <= '0;
            m_pwrite_q  <= '0;
            m_pwdata_q  <= '0;
            m_pstrb_q   <= '0;
            m_ack_q     <= '0;
            m_prdata_q  <= '0;
            m_pslverr_q <= '0;
        end else begin
            state_q     <= state_d;
            m_psel_q    <= m_psel_d;
            m_penable_q <= m_penable_d;
            m_paddr_q   <= m_paddr_d;
            m_pprot_q   <= m_pprot_d;
            m_pwrite_q  <= m_pwrite_d;
            m_pwdata_q  <= m_pwdata_d;
            m_pstrb_q   <= m_pstrb_d;
            m_ack_q     <= m_ack_d;
            m_prdata_q  <= m_prdata_d;
            m_pslverr_q <= m_pslverr_d;
       end
    end

    assign m_psel_o    = m_psel_q;
    assign m_penable_o = m_penable_q;
    assign m_paddr_o   = m_paddr_q;
    assign m_pprot_o   = m_pprot_q;
    assign m_pwrite_o  = m_pwrite_q;
    assign m_pwdata_o  = m_pwdata_q;
    assign m_pstrb_o   = m_pstrb_q;
    assign m_ack_o     = m_ack_q;
    assign m_prdata_o  = m_prdata_q;
    assign m_pslverr_o = m_pslverr_q;

endmodule
