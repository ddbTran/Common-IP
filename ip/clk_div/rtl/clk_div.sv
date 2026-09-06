// ============================================================================
// Module      : clk_div
// Author      : Dat Tran Tan <dat.trantan.business@gmail.com>
// Description : Runtime configurable clock divider
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

  generate
    if (MAX_DIVISION < 1) begin : gen_max_division_assert
      initial begin
        $error("MAX_DIVISION must be >= 1");
      end
    end

    if (DEFAULT_DIVISION > MAX_DIVISION) begin : gen_default_division_assert
      initial begin
        $error("DEFAULT_DIVISION must be <= MAX_DIVISION");
      end
    end
  endgenerate

  typedef enum logic [1:0] {
    StIdle,  // Stop clock, load new config if available
    StFunc,  // Generate clock
    StWait   // Wait for current period to complete
  } state_e;

  state_e state_q, state_d;

  logic [CNT_WIDTH-1:0] cnt_q, cnt_d;
  logic [CNT_WIDTH-1:0] div_q, div_d;
  logic [CNT_WIDTH-1:0] div_norm;
  assign div_norm = (div_i == 0) ? 1 : div_i; // Normalize div_i

  logic toggle_en;
  logic icg_en;

  always_comb begin
    state_d = state_q;
    unique case (state_q)
      StIdle: begin
        if (en_i) begin
          state_d = StFunc;  // Idle -> Func: Generate clock when enabled
        end
      end
      StFunc: begin
        if (!en_i || (valid_i && (div_q != div_norm))) begin
          state_d = (cnt_q == 0) ? StIdle : StWait;  // Func -> Wait: Stop or wait for new config
        end
      end
      StWait: begin
        if (cnt_q == 0) begin
          state_d = StIdle;  // Wait -> Idle: Finish current period with clk_o low
        end
      end
      default: begin
        state_d = StIdle;
      end
    endcase
  end

  always_comb begin
    cnt_d     = cnt_q;
    div_d     = div_q;
    ready_o   = 1'b0;
    toggle_en = 1'b0;
    icg_en    = 1'b0;
    unique case (state_q)
      StIdle: begin
        // Keep clock stopped while loading a new configuration.
        cnt_d = '0;
        if (valid_i) begin
          ready_o = 1'b1;
          div_d = div_norm;
        end
      end
      StFunc: begin
        // Count one complete output period.
        cnt_d     = (cnt_q == (div_q - 1)) ? '0 : cnt_q + 1'b1;
        toggle_en = (div_q > 1);
        // Configuration is accepted when it matches the active division.
        ready_o = valid_i && (div_norm == div_q);
        // Keep the current period intact before stopping or reconfiguring.
        icg_en = ((!en_i || (valid_i && (div_q != div_norm))) && (cnt_q == 0)) ? 1'b0 : 1'b1;
      end
      StWait: begin
        // Complete the current period before stopping the clock.
        cnt_d     = (cnt_q == (div_q - 1)) ? '0 : cnt_q + 1'b1;
        toggle_en = (div_q > 1);
        // Disable clock gating after reaching a safe clock boundary.
        icg_en = (cnt_q == 0) ? 1'b0 : 1'b1;
      end
      default: begin
        cnt_d     = '0;
        div_d     = CNT_WIDTH'(DEFAULT_DIVISION);
        ready_o   = 1'b0;
        toggle_en = 1'b0;
        icg_en    = 1'b0;
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

  // Clock generation path.
  // This path generates the divided clock for even/odd division and
  // bypasses the divider for division values of 0 or 1.
  //
  // NOTE: This entire clock path is implementation-sensitive.
  // The AND, OR, XOR, and MUX logic in this path must be implemented
  // using appropriate clock-aware cells to preserve clock integrity,
  // duty cycle, and glitch-free operation.
  // Replace clk_gate with the technology-specific clock-gating cell.
  // DO NOT MODIFY this clock path during implementation.
  logic odd_clk;
  logic even_clk;
  logic div_clk;
  logic gen_clk;

  assign odd_clk  = toggle_p_q ^ toggle_n_q;
  assign even_clk = toggle_p_q;
  assign div_clk  = div_q[0] ? odd_clk : even_clk;
  assign gen_clk  = (div_q > 1) ? div_clk : clk_i;

  clk_gate u_clk_gate (
    .clk_i(gen_clk),
    .en_i(icg_en),
    .clk_o(clk_o)
  );
  
  endmodule
