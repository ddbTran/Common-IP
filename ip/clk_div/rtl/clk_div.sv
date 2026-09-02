// ============================================================================
// Module      : clk_div
// Description : Parameterized clock divider
// Author      : Dat Tran <dat.trantan.business@gmail.com>
// ============================================================================

`timescale 1ns/1ps

module clk_div #(
    // Configurable Parameters
    parameter int unsigned DIV_VALUE = 3,

    // Derived Parameters
    localparam int unsigned DIV       = (DIV_VALUE < 2) ? 1 : DIV_VALUE,
    localparam int unsigned CNT_WIDTH = (DIV > 2) ? $clog2(DIV) : 1,
    localparam int unsigned HALF      = (DIV + 1) / 2
) (
    input  logic clk_i,
    input  logic rst_ni,
    output logic clk_o
);

    //----------------------------------------------------------------------
    // Internal signals
    //----------------------------------------------------------------------

    logic clk_active;
    logic clk_div;

    //----------------------------------------------------------------------
    // Clock active synchronizer
    //----------------------------------------------------------------------

    synchronizer #(
        .DEPTH    (2),
        .RST_VALUE(0)
    ) u_clk_active (
        .clk_i  (clk_i),
        .rst_ni (rst_ni),
        .data_i (1'b1),
        .data_o (clk_active)
    );

    //----------------------------------------------------------------------
    // Clock divider
    //----------------------------------------------------------------------

    generate
        // Bypass clk_i when DIV_VALUE < 2
        if (DIV == 1) begin : gen_div_1
            assign clk_div = clk_i;
        end
        // Generate only posedge counter if divide to even value
        else if ((DIV % 2) == 0) begin : gen_div_even
            logic [CNT_WIDTH-1:0] cnt_q;
            logic                 high;

            always_ff @(posedge clk_i or negedge rst_ni) begin
                if (!rst_ni) begin
                    cnt_q <= '0;
                end
                else if (!clk_active) begin
                    cnt_q <= '0;
                end
                else if (cnt_q == CNT_WIDTH'(DIV - 1)) begin
                    cnt_q <= '0;
                end
                else begin
                    cnt_q <= cnt_q + 1'b1;
                end
            end

            assign high    = cnt_q < CNT_WIDTH'(HALF);
            assign clk_div = high;
        end
        // Generate both posedge and negedge counter to divide to odd value
        else begin : gen_div_odd
            logic [CNT_WIDTH-1:0] cnt_p_q;
            logic [CNT_WIDTH-1:0] cnt_n_q;
            logic                 p_high;
            logic                 n_high;

	    always_ff @(posedge clk_i or negedge rst_ni) begin
                if (!rst_ni) begin
                    cnt_p_q <= '0;
                end
                else if (!clk_active) begin
                    cnt_p_q <= '0;
                end
                else if (cnt_p_q == CNT_WIDTH'(DIV - 1)) begin
                    cnt_p_q <= '0;
                end
                else begin
                    cnt_p_q <= cnt_p_q + 1'b1;
                end
            end

            always_ff @(negedge clk_i or negedge rst_ni) begin
                if (!rst_ni) begin
                    cnt_n_q <= '0;
                end
                else if (!clk_active) begin
                    cnt_n_q <= '0;
                end
                else if (cnt_n_q == CNT_WIDTH'(DIV - 1)) begin
                    cnt_n_q <= '0;
                end
                else begin
                    cnt_n_q <= cnt_n_q + 1'b1;
                end
            end

            assign p_high  = cnt_p_q < CNT_WIDTH'(HALF);
            assign n_high  = cnt_n_q < CNT_WIDTH'(HALF);
            assign clk_div = p_high && n_high;
        end
    endgenerate

    //----------------------------------------------------------------------
    // Output clock gating (ICG)
    //----------------------------------------------------------------------

    clk_gate u_clk_gate (
        .clk_i (clk_div),
        .en_i  (clk_active),
        .clk_o (clk_o)
    );

    //----------------------------------------------------------------------
    // Parameter checks
    //----------------------------------------------------------------------

    initial begin
        if (DIV_VALUE < 2)
            $warning("DIV_VALUE < 2, using divide-by-1");
    end

endmodule
