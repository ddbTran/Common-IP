// ============================================================================
// Module      : clk_div
// Author      : Dat Tran Tan <dat.trantan.business@gmail.com>
// Description : Configurable clock divider
// ============================================================================

`timescale 1ns/1ps

module clk_div #(
    parameter int unsigned MAX_DIVISION     = 16,
    parameter int unsigned DEFAULT_DIVISION = 2,

    localparam int unsigned CNT_WIDTH       = $clog2(MAX_DIVISION+1)
) (
    input  logic                 clk_i,
    input  logic                 rst_ni,
    input  logic                 en_i,

    input  logic [CNT_WIDTH-1:0] div_i,
    input  logic                 valid_i,
    output logic                 ready_o,

    output logic                 clk_o
);

  typedef enum logic [1:0] {
    StIdle,
    StFunc,
    StWait
  } state_e;

  state_e state_q, state_d;

  logic [CNT_WIDTH-1:0] cnt_q, cnt_d;
  logic [CNT_WIDTH-1:0] div_q, div_d;

  logic toggle_en;

  always_comb begin
    state_d = state_q;
    unique case (state_q)
      StIdle: begin
        if (en_i) begin
          state_d = StFunc;
        end
      end
      StFunc: begin
        if (!en_i || (valid_i && (div_q != div_i))) state_d = StWait;
      end
      StWait: begin
        if (cnt_q == 0) begin
          state_d = StIdle;
        end
      end
      default: begin
        state_d = StIdle;
      end
    endcase
  end

  always_comb begin
    cnt_d   = cnt_q;
    div_d   = div_q;
    ready_o = 1'b0;
    toggle_en   = 1'b0;

    unique case (state_q)
      StIdle: begin
        cnt_d   = '0;
        ready_o = 1'b1;
       if (valid_i) begin
          div_d = div_i;
        end
      end

      StFunc: begin
        cnt_d = (cnt_q == (div_q - 1)) ? '0 : cnt_q + 1'b1;
        toggle_en = (div_q > 1);
        ready_o = (valid_i && (div_i == div_q)) ? 1'b1 : 1'b0;
      end

      StWait: begin
        cnt_d = (cnt_q == (div_q - 1)) ? '0 : cnt_q + 1'b1;
        toggle_en = (div_q > 1);
        if (cnt_q == (div_q - 1'b1)) begin
          ready_o = 1'b1;

          if (valid_i) begin
            div_d = div_i;
          end
        end
      end

      default: begin
        cnt_d   = '0;
        div_d   = CNT_WIDTH'(DEFAULT_DIVISION);
        ready_o = 1'b0;
        toggle_en   = 1'b0;
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= StIdle;
      cnt_q   <= '0;
      div_q   <= CNT_WIDTH'(DEFAULT_DIVISION);
    end else begin
      state_q <= state_d;
      cnt_q   <= cnt_d;
      div_q   <= div_d;
    end
  end

  logic toggle_p_q, toggle_p_d;
  logic toggle_n_q, toggle_n_d;

  always_comb begin
    toggle_p_d = 1'b0;
    toggle_n_d = 1'b0;
    if(toggle_en) begin
        if (div_q[0]) begin
          toggle_p_d = (cnt_q == '0)                    ? ~toggle_p_q : toggle_p_q;
          toggle_n_d = (cnt_q == ((div_q >> 1) + 1'b1)) ? ~toggle_n_q : toggle_n_q;
        end else begin
          toggle_p_d = ((cnt_q == '0) || cnt_q == (div_q >> 1)) ? ~toggle_p_q : toggle_p_q;
          toggle_n_d = 1'b0;
        end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      toggle_p_q <= 1'b0;
    end else begin
      toggle_p_q <= toggle_p_d;
    end
  end

  always_ff @(negedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      toggle_n_q <= 1'b0;
    end else begin
      toggle_n_q <= toggle_n_d;
    end
  end

  logic odd_clk;
  logic even_clk;
  logic div_clk;
  logic gen_clk;

  logic icg_en;
  always_ff @(negedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      icg_en <= 0;
    end else begin
      case (state_q)
        StIdle: icg_en <= 0;
        StFunc: icg_en <= (!en_i && (cnt_q == (div_q - 1))) ? 0 : 1;
        StWait: icg_en <= div_q == 1 ? ~icg_en : cnt_q == (div_q - 1) ? ~icg_en : icg_en;
        default: icg_en <= 0;
      endcase
    end
  end


  assign odd_clk  = toggle_p_q ^ toggle_n_q;
  assign even_clk = toggle_p_q;
  assign div_clk = div_q[0] ? odd_clk : even_clk;
  assign gen_clk = (div_q > 1) ? div_clk : clk_i;

  
  assign clk_o = gen_clk && icg_en;

endmodule
