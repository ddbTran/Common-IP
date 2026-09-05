`timescale 1ns/1ps

module tb_clk_div;

  localparam int unsigned MAX_DIVISION     = 16;
  localparam int unsigned DEFAULT_DIVISION = 2;
  localparam int unsigned CNT_WIDTH        = $clog2(MAX_DIVISION + 1);

  localparam time CLK_PERIOD    = 10ns;
  localparam time TEST_TIMEOUT  = 100us;
  localparam time RESET_SETTLE  = 1;

  localparam int unsigned REQUEST_TIMEOUT_CYCLES = (2 * MAX_DIVISION) + 8;
  localparam int unsigned STOP_TIMEOUT_CYCLES    = (2 * MAX_DIVISION) + 8;
  localparam int unsigned RANDOM_ITERATIONS      = 50;

  logic                 clk_i;
  logic                 rst_ni;
  logic                 en_i;
  logic [CNT_WIDTH-1:0] div_i;
  logic                 valid_i;
  logic                 ready_o;
  logic                 clk_o;

  int unsigned error_count;
  int unsigned timeout_count;
  int unsigned total_handshake_count;
  int unsigned clk_o_edge_count;
  int unsigned clk_o_posedge_count;

  int unsigned tc_debug;

  bit  quality_monitor_en;
  bit  clk_o_edge_valid;
  time last_clk_i_edge_time;
  time last_clk_o_edge_time;


  // DUT

  clk_div #(
    .MAX_DIVISION     (MAX_DIVISION),
    .DEFAULT_DIVISION (DEFAULT_DIVISION)
  ) dut (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .en_i    (en_i),
    .div_i   (div_i),
    .valid_i (valid_i),
    .ready_o (ready_o),
    .clk_o   (clk_o)
  );


  // Input clock

  initial begin
    clk_i = 1'b0;
    forever #(CLK_PERIOD / 2) clk_i = ~clk_i;
  end


  // Common reporting

  task automatic report_error(input string message);
    $display("[FAIL][%0t] %s", $time, message);
    error_count++;
  endtask


  task automatic report_pass(input string message);
    $display("[PASS][%0t] %s", $time, message);
  endtask


  // Black-box monitors

  always @(posedge clk_i or negedge clk_i) begin
    last_clk_i_edge_time = $time;
  end


  always @(posedge clk_i) begin
    if (rst_ni && valid_i && ready_o) begin
      total_handshake_count++;
    end
  end


  always @(posedge clk_o) begin
    clk_o_posedge_count++;
  end


  always @(clk_o) begin
    if (!$isunknown(clk_o)) begin
      clk_o_edge_count++;
    end

    if (!quality_monitor_en || !rst_ni || $isunknown(clk_o)) begin
      clk_o_edge_valid = 1'b0;
    end else begin
      #0;

      if ($time != last_clk_i_edge_time) begin
        report_error($sformatf(
          "clk_o edge is not aligned to a clk_i edge: last clk_i edge=%0t",
          last_clk_i_edge_time
        ));
      end

      if (clk_o_edge_valid && (($time - last_clk_o_edge_time) < (CLK_PERIOD / 2))) begin
        report_error($sformatf(
          "runt/double edge detected: pulse width=%0t minimum=%0t",
          $time - last_clk_o_edge_time,
          CLK_PERIOD / 2
        ));
      end

      last_clk_o_edge_time = $time;
      clk_o_edge_valid     = 1'b1;
    end
  end


  always @(posedge clk_i) begin
    if (quality_monitor_en && rst_ni) begin
      if ($isunknown(ready_o)) begin
        report_error("ready_o is unknown after reset release");
      end

      if ($isunknown(clk_o)) begin
        report_error("clk_o is unknown after reset release");
      end
    end
  end


  // Driver and checker tasks

  task automatic reset_dut;
    quality_monitor_en = 1'b0;
    clk_o_edge_valid   = 1'b0;

    rst_ni  = 1'b0;
    en_i    = 1'b0;
    valid_i = 1'b0;
    div_i   = CNT_WIDTH'(DEFAULT_DIVISION);

    repeat (4) @(posedge clk_i);

    @(negedge clk_i);
    rst_ni = 1'b1;

    repeat (2) @(posedge clk_i);
    #RESET_SETTLE;

    quality_monitor_en = 1'b1;
    clk_o_edge_valid   = 1'b0;

    if (clk_o !== 1'b0) begin
      report_error($sformatf("clk_o=%0b after reset, expected 0", clk_o));
    end

    if (ready_o !== 1'b1) begin
      report_error($sformatf("ready_o=%0b while disabled, expected 1", ready_o));
    end
  endtask


  task automatic set_enable(input logic value);
    @(negedge clk_i);
    en_i = value;
    $display("[%0t] en_i=%0b", $time, value);
  endtask


  task automatic wait_for_handshake(
    input  int unsigned max_cycles,
    output bit          accepted,
    output int unsigned wait_cycles
  );
    accepted    = 1'b0;
    wait_cycles = 0;

    for (int unsigned cycle = 0; cycle < max_cycles; cycle++) begin
      @(posedge clk_i);

      if (ready_o === 1'b1) begin
        accepted = 1'b1;
        break;
      end

      wait_cycles++;
    end
  endtask


  task automatic request_div(
    input  int unsigned division,
    input  int unsigned max_wait_cycles,
    output bit          accepted,
    output int unsigned wait_cycles
  );
    if ((division < 1) || (division > MAX_DIVISION)) begin
      accepted    = 1'b0;
      wait_cycles = 0;
      report_error($sformatf(
        "testbench attempted illegal divisor %0d; legal range is 1..%0d",
        division,
        MAX_DIVISION
      ));
    end else begin
      @(negedge clk_i);
      div_i   = CNT_WIDTH'(division);
      valid_i = 1'b1;

      wait_for_handshake(max_wait_cycles, accepted, wait_cycles);

      if (!accepted) begin
        report_error($sformatf(
          "DIV=%0d request did not handshake within %0d cycles",
          division,
          max_wait_cycles
        ));
      end else begin
        $display(
          "[%0t] HANDSHAKE: DIV=%0d wait_cycles=%0d",
          $time,
          division,
          wait_cycles
        );
      end

      @(negedge clk_i);
      valid_i = 1'b0;
    end
  endtask


  task automatic request_div_or_fail(input int unsigned division);
    bit          accepted;
    int unsigned wait_cycles;

    request_div(
      division,
      REQUEST_TIMEOUT_CYCLES,
      accepted,
      wait_cycles
    );
  endtask


  task automatic request_div_hold_after_ready(
    input int unsigned division,
    input int unsigned hold_cycles
  );
    bit          accepted;
    int unsigned wait_cycles;

    @(negedge clk_i);
    div_i   = CNT_WIDTH'(division);
    valid_i = 1'b1;

    wait_for_handshake(
      REQUEST_TIMEOUT_CYCLES,
      accepted,
      wait_cycles
    );

    if (!accepted) begin
      report_error($sformatf(
        "DIV=%0d held-valid request did not handshake",
        division
      ));
    end else begin
      $display(
        "[%0t] HANDSHAKE: DIV=%0d, holding valid_i for %0d more cycles",
        $time,
        division,
        hold_cycles
      );
    end

    repeat (hold_cycles) @(posedge clk_i);

    @(negedge clk_i);
    valid_i = 1'b0;
  endtask


  task automatic check_period(
    input int unsigned division,
    input int unsigned samples
  );
    time         previous_edge;
    time         current_edge;
    time         measured_period;
    time         expected_period;
    int unsigned errors_before;

    expected_period = CLK_PERIOD * division;
    errors_before   = error_count;

    @(posedge clk_o);
    previous_edge = $time;

    repeat (samples) begin
      @(posedge clk_o);
      current_edge    = $time;
      measured_period = current_edge - previous_edge;

      if (measured_period != expected_period) begin
        report_error($sformatf(
          "DIV=%0d period=%0t expected=%0t",
          division,
          measured_period,
          expected_period
        ));
      end

      previous_edge = current_edge;
    end

    if (error_count == errors_before) begin
      report_pass($sformatf(
        "DIV=%0d period=%0t for %0d samples",
        division,
        expected_period,
        samples
      ));
    end
  endtask


  task automatic check_duty_cycle(
    input int unsigned division,
    input int unsigned samples
  );
    time         rise_time;
    time         fall_time;
    time         next_rise_time;
    time         high_time;
    time         low_time;
    time         expected_half_period;
    int unsigned errors_before;

    expected_half_period = (CLK_PERIOD * division) / 2;
    errors_before        = error_count;

    @(posedge clk_o);
    rise_time = $time;

    repeat (samples) begin
      @(negedge clk_o);
      fall_time = $time;

      @(posedge clk_o);
      next_rise_time = $time;

      high_time = fall_time - rise_time;
      low_time  = next_rise_time - fall_time;

      if (high_time != expected_half_period) begin
        report_error($sformatf(
          "DIV=%0d high time=%0t expected=%0t",
          division,
          high_time,
          expected_half_period
        ));
      end

      if (low_time != expected_half_period) begin
        report_error($sformatf(
          "DIV=%0d low time=%0t expected=%0t",
          division,
          low_time,
          expected_half_period
        ));
      end

      rise_time = next_rise_time;
    end

    if (error_count == errors_before) begin
      report_pass($sformatf(
        "DIV=%0d duty cycle is 50%% for %0d samples",
        division,
        samples
      ));
    end
  endtask


  task automatic check_ready(input logic expected, input string context_t);
    @(negedge clk_i);

    if (ready_o !== expected) begin
      report_error($sformatf(
        "%s: ready_o=%0b expected=%0b",
        context_t,
        ready_o,
        expected
      ));
    end else begin
      report_pass($sformatf(
        "%s: ready_o=%0b",
        context_t,
        ready_o
      ));
    end
  endtask


  task automatic wait_for_stop(input int unsigned max_cycles);
    bit          stopped;
    int unsigned stable_cycles;
    int unsigned edge_snapshot;

    stopped       = 1'b0;
    stable_cycles = 0;

    for (int unsigned cycle = 0; cycle < max_cycles; cycle++) begin
      @(posedge clk_i);
      #RESET_SETTLE;

      if ((ready_o === 1'b1) && (clk_o === 1'b0)) begin
        stable_cycles++;
      end else begin
        stable_cycles = 0;
      end

      if (stable_cycles >= 2) begin
        stopped = 1'b1;
        break;
      end
    end

    if (!stopped) begin
      report_error($sformatf(
        "clock did not stop low within %0d cycles",
        max_cycles
      ));
    end else begin
      edge_snapshot = clk_o_edge_count;

      repeat (3) @(posedge clk_i);
      #RESET_SETTLE;

      if (clk_o !== 1'b0) begin
        report_error($sformatf(
          "clk_o=%0b after disable completion, expected 0",
          clk_o
        ));
      end

      if (clk_o_edge_count != edge_snapshot) begin
        report_error("clk_o toggled after disable completion");
      end

      if (ready_o !== 1'b1) begin
        report_error($sformatf(
          "ready_o=%0b after disable completion, expected 1",
          ready_o
        ));
      end
    end
  endtask


  task automatic enable_and_check(input int unsigned division);
    set_enable(1'b1);
    check_ready(1'b0, "Running without a pending request");
    check_period(division, 3);
    check_duty_cycle(division, 2);
  endtask


  task automatic disable_and_wait;
    set_enable(1'b0);
    wait_for_stop(STOP_TIMEOUT_CYCLES);
  endtask


  task automatic reconfigure_mid_period(
    input int unsigned old_division,
    input int unsigned new_division,
    input int unsigned request_delay_cycles
  );
    bit          accepted;
    int unsigned wait_cycles;
    int unsigned errors_before;
    time         old_rise_time;
    time         next_rise_time;
    time         expected_old_period;

    expected_old_period = CLK_PERIOD * old_division;
    errors_before       = error_count;

    @(posedge clk_o);
    old_rise_time = $time;

    repeat (request_delay_cycles) @(posedge clk_i);

    fork
      begin : request_thread
        request_div(
          new_division,
          REQUEST_TIMEOUT_CYCLES,
          accepted,
          wait_cycles
        );
      end

      begin : old_period_thread
        @(posedge clk_o);
        next_rise_time = $time;

        if ((next_rise_time - old_rise_time) < expected_old_period) begin
          report_error($sformatf(
            "DIV change %0d->%0d truncated current period: measured=%0t expected=%0t",
            old_division,
            new_division,
            next_rise_time - old_rise_time,
            expected_old_period
          ));
        end
      end
    join

    if (accepted) begin
      @(posedge clk_o);

      if (($time - next_rise_time) != (CLK_PERIOD * new_division)) begin
        report_error($sformatf(
          "DIV change %0d->%0d first new period=%0t expected=%0t",
          old_division,
          new_division,
          $time - next_rise_time,
          CLK_PERIOD * new_division
        ));
      end

      check_period(new_division, 2);
      check_duty_cycle(new_division, 1);
    end

    if (error_count == errors_before) begin
      report_pass($sformatf(
        "safe reconfiguration %0d -> %0d",
        old_division,
        new_division
      ));
    end
  endtask


  task automatic disable_during_high(input int unsigned division);
    int unsigned posedge_snapshot;
    time         rise_time;
    time         fall_time;
    time         expected_high_time;

    expected_high_time = (CLK_PERIOD * division) / 2;

    @(posedge clk_o);
    rise_time = $time;

    @(negedge clk_i);

    if (clk_o !== 1'b1) begin
      report_error($sformatf(
        "DIV=%0d disable-high stimulus missed the high phase",
        division
      ));
    end

    posedge_snapshot = clk_o_posedge_count;
    en_i              = 1'b0;

    @(negedge clk_o);
    fall_time = $time;

    if ((fall_time - rise_time) != expected_high_time) begin
      report_error($sformatf(
        "DIV=%0d high pulse truncated on disable: measured=%0t expected=%0t",
        division,
        fall_time - rise_time,
        expected_high_time
      ));
    end

    wait_for_stop(STOP_TIMEOUT_CYCLES);

    if (clk_o_posedge_count != posedge_snapshot) begin
      report_error($sformatf(
        "DIV=%0d produced an extra rising edge after disable request",
        division
      ));
    end
  endtask


  task automatic disable_during_low(input int unsigned division);
    int unsigned posedge_snapshot;

    @(negedge clk_o);
    @(negedge clk_i);

    if (clk_o !== 1'b0) begin
      report_error($sformatf(
        "DIV=%0d disable-low stimulus missed the low phase",
        division
      ));
    end

    posedge_snapshot = clk_o_posedge_count;
    en_i              = 1'b0;

    wait_for_stop(STOP_TIMEOUT_CYCLES);

    if (clk_o_posedge_count != posedge_snapshot) begin
      report_error($sformatf(
        "DIV=%0d produced an extra rising edge after low-phase disable",
        division
      ));
    end
  endtask


  // Testcases

  task automatic tc_default_after_reset;
    check_ready(1'b1, "Idle after reset");
    enable_and_check(DEFAULT_DIVISION);
    disable_and_wait();
  endtask


  task automatic tc_all_legal_divisors;
    for (int unsigned division = 1; division <= MAX_DIVISION; division++) begin
      $display("Testing legal DIV=%0d", division);

      request_div_or_fail(division);
      enable_and_check(division);
      disable_and_wait();
    end
  endtask


  task automatic tc_latest_write_wins_while_disabled;
    request_div_or_fail(3);
    request_div_or_fail(7);
    request_div_or_fail(4);

    enable_and_check(4);
    disable_and_wait();
  endtask


  task automatic tc_config_and_enable_same_cycle;
    bit          accepted;
    int unsigned wait_cycles;

    @(negedge clk_i);
    div_i   = CNT_WIDTH'(5);
    valid_i = 1'b1;
    en_i    = 1'b1;

    wait_for_handshake(2, accepted, wait_cycles);

    if (!accepted) begin
      report_error("simultaneous idle configuration and enable was not accepted");
    end

    @(negedge clk_i);
    valid_i = 1'b0;

    check_period(5, 3);
    check_duty_cycle(5, 1);
    disable_and_wait();
  endtask


  task automatic tc_even_to_even;
    request_div_or_fail(6);
    set_enable(1'b1);
    check_period(6, 2);
    reconfigure_mid_period(6, 4, 1);
    disable_and_wait();
  endtask


  task automatic tc_even_to_odd;
    request_div_or_fail(4);
    set_enable(1'b1);
    check_period(4, 2);
    reconfigure_mid_period(4, 5, 1);
    disable_and_wait();
  endtask


  task automatic tc_odd_to_even;
    request_div_or_fail(5);
    set_enable(1'b1);
    check_period(5, 2);
    reconfigure_mid_period(5, 6, 1);
    disable_and_wait();
  endtask


  task automatic tc_odd_to_odd;
    request_div_or_fail(5);
    set_enable(1'b1);
    check_period(5, 2);
    reconfigure_mid_period(5, 3, 1);
    disable_and_wait();
  endtask


  task automatic tc_same_divisor_request;
    bit          accepted;
    int unsigned wait_cycles;

    request_div_or_fail(5);
    set_enable(1'b1);
    check_period(5, 2);

    request_div(
      5,
      REQUEST_TIMEOUT_CYCLES,
      accepted,
      wait_cycles
    );

    if (accepted) begin
      check_period(5, 3);
    end

    disable_and_wait();
  endtask


  task automatic tc_valid_held_after_ready;
    request_div_or_fail(4);
    set_enable(1'b1);
    check_period(4, 2);

    request_div_hold_after_ready(5, 3);
    check_period(5, 3);
    check_duty_cycle(5, 1);

    disable_and_wait();
  endtask


  task automatic tc_rapid_reconfiguration;
    request_div_or_fail(2);
    set_enable(1'b1);
    check_period(2, 2);

    request_div_or_fail(5);
    check_period(5, 1);

    request_div_or_fail(4);
    check_period(4, 1);

    request_div_or_fail(3);
    check_period(3, 3);

    disable_and_wait();
  endtask


  task automatic tc_disable_even_high;
    request_div_or_fail(6);
    set_enable(1'b1);
    check_period(6, 2);
    disable_during_high(6);
  endtask


  task automatic tc_disable_odd_high;
    request_div_or_fail(5);
    set_enable(1'b1);
    check_period(5, 2);
    disable_during_high(5);
  endtask


  task automatic tc_disable_odd_low;
    request_div_or_fail(5);
    set_enable(1'b1);
    check_period(5, 2);
    disable_during_low(5);
  endtask


  task automatic tc_reenable_retains_divisor;
    request_div_or_fail(7);
    set_enable(1'b1);
    check_period(7, 2);
    disable_and_wait();

    set_enable(1'b1);
    check_period(7, 3);
    check_duty_cycle(7, 1);
    disable_and_wait();
  endtask


  task automatic tc_disable_and_reconfigure_same_cycle;
    bit          accepted;
    int unsigned wait_cycles;

    request_div_or_fail(6);
    set_enable(1'b1);
    check_period(6, 2);

    @(posedge clk_o);
    @(negedge clk_i);

    en_i    = 1'b0;
    div_i   = CNT_WIDTH'(3);
    valid_i = 1'b1;

    wait_for_handshake(
      REQUEST_TIMEOUT_CYCLES,
      accepted,
      wait_cycles
    );

    if (!accepted) begin
      report_error("simultaneous disable and reconfiguration did not handshake");
    end

    @(negedge clk_i);
    valid_i = 1'b0;

    wait_for_stop(STOP_TIMEOUT_CYCLES);

    set_enable(1'b1);
    check_period(3, 3);
    check_duty_cycle(3, 1);
    disable_and_wait();
  endtask


  task automatic tc_enable_again_while_waiting;
    bit          accepted;
    int unsigned wait_cycles;
    time         old_rise_time;
    time         next_rise_time;

    request_div_or_fail(6);
    set_enable(1'b1);
    check_period(6, 2);

    @(posedge clk_o);
    old_rise_time = $time;

    @(negedge clk_i);
    en_i = 1'b0;

    @(negedge clk_i);
    en_i    = 1'b1;
    div_i   = CNT_WIDTH'(3);
    valid_i = 1'b1;

    fork
      begin : pending_handshake_thread
        wait_for_handshake(
          REQUEST_TIMEOUT_CYCLES,
          accepted,
          wait_cycles
        );
      end

      begin : complete_old_period_thread
        @(posedge clk_o);
        next_rise_time = $time;

        if ((next_rise_time - old_rise_time) < (CLK_PERIOD * 6)) begin
          report_error("enable recovery or pending DIV request truncated old period");
        end
      end
    join

    if (!accepted) begin
      report_error("pending DIV request did not handshake after en_i reassertion");
    end

    @(negedge clk_i);
    valid_i = 1'b0;

    check_period(3, 3);
    disable_and_wait();
  endtask


  task automatic tc_reset_while_running;
    request_div_or_fail(5);
    set_enable(1'b1);
    check_period(5, 2);

    @(posedge clk_o);
    @(negedge clk_i);

    quality_monitor_en = 1'b0;
    clk_o_edge_valid   = 1'b0;
    rst_ni             = 1'b0;

    @(posedge clk_i);

    if (clk_o !== 1'b0) begin
      report_error($sformatf(
        "clk_o=%0b during reset, expected 0",
        clk_o
      ));
    end

    repeat (3) @(posedge clk_i);

    @(negedge clk_i);
    rst_ni = 1'b1;

    repeat (2) @(posedge clk_i);
    quality_monitor_en = 1'b1;
    clk_o_edge_valid   = 1'b0;

    check_period(DEFAULT_DIVISION, 3);
    disable_and_wait();
  endtask


  task automatic tc_reset_during_pending_request;
    request_div_or_fail(7);
    set_enable(1'b1);
    check_period(7, 2);

    @(posedge clk_o);
    @(negedge clk_i);

    div_i   = CNT_WIDTH'(3);
    valid_i = 1'b1;

    @(posedge clk_i);
    @(negedge clk_i);

    quality_monitor_en = 1'b0;
    clk_o_edge_valid   = 1'b0;
    rst_ni             = 1'b0;
    en_i               = 1'b0;
    valid_i            = 1'b0;

    repeat (3) @(posedge clk_i);

    @(negedge clk_i);
    rst_ni = 1'b1;

    repeat (2) @(posedge clk_i);
    #RESET_SETTLE;

    quality_monitor_en = 1'b1;
    clk_o_edge_valid   = 1'b0;

    if (ready_o !== 1'b1) begin
      report_error("ready_o did not return high after reset canceled pending request");
    end

    if (clk_o !== 1'b0) begin
      report_error("clk_o did not return low after reset canceled pending request");
    end

    set_enable(1'b1);
    check_period(DEFAULT_DIVISION, 3);
    disable_and_wait();
  endtask


  task automatic tc_random_stress;
    bit          accepted;
    int unsigned wait_cycles;
    int unsigned current_division;
    int unsigned next_division;
    int unsigned operation;

    current_division = $urandom_range(MAX_DIVISION, 1);

    request_div_or_fail(current_division);
    set_enable(1'b1);
    check_period(current_division, 2);

    repeat (RANDOM_ITERATIONS) begin
      operation = $urandom_range(3, 0);

      unique case (operation)
        0: begin
          next_division = $urandom_range(MAX_DIVISION, 1);

          request_div(
            next_division,
            REQUEST_TIMEOUT_CYCLES,
            accepted,
            wait_cycles
          );

          if (accepted) begin
            current_division = next_division;
            check_period(current_division, 1);
          end
        end

        1: begin
          disable_and_wait();

          if ($urandom_range(1, 0) == 1) begin
            current_division = $urandom_range(MAX_DIVISION, 1);
            request_div_or_fail(current_division);
          end

          set_enable(1'b1);
          check_period(current_division, 1);
        end

        2: begin
          request_div(
            current_division,
            REQUEST_TIMEOUT_CYCLES,
            accepted,
            wait_cycles
          );

          if (accepted) begin
            check_period(current_division, 1);
          end
        end

        default: begin
          check_period(current_division, 1);
        end
      endcase
    end

    disable_and_wait();
  endtask


  // Per-test timeout runner

  task automatic run_test(
    input int unsigned test_id,
    input string       test_name
  );
    bit          test_done;
    int unsigned errors_before;

    test_done     = 1'b0;
    errors_before = error_count;

    $display("");
    $display("============================================================");
    $display("START: %s", test_name);
    $display("============================================================");

    reset_dut();

    fork
      begin : test_body
        unique case (test_id)
          1:  tc_default_after_reset();
          2:  tc_all_legal_divisors();
          3:  tc_latest_write_wins_while_disabled();
          4:  tc_config_and_enable_same_cycle();
          5:  tc_even_to_even();
          6:  tc_even_to_odd();
          7:  tc_odd_to_even();
          8:  tc_odd_to_odd();
          9:  tc_same_divisor_request();
          10: tc_valid_held_after_ready();
          11: tc_rapid_reconfiguration();
          12: tc_disable_even_high();
          13: tc_disable_odd_high();
          14: tc_disable_odd_low();
          15: tc_reenable_retains_divisor();
          16: tc_disable_and_reconfigure_same_cycle();
          17: tc_enable_again_while_waiting();
          18: tc_reset_while_running();
          19: tc_reset_during_pending_request();
          20: tc_random_stress();

          default: begin
            report_error($sformatf("invalid test_id=%0d", test_id));
          end
        endcase

        test_done = 1'b1;
      end

      begin : watchdog
        #(TEST_TIMEOUT);
      end
    join_any

    disable fork;

    if (!test_done) begin
      $display("[TIMEOUT][%0t] %s", $time, test_name);
      error_count++;
      timeout_count++;
      reset_dut();
    end

    if (test_done && (error_count == errors_before)) begin
      $display("[TEST PASS] %s", test_name);
    end else if (!test_done) begin
      $display("[TEST FAIL] %s - TIMEOUT", test_name);
    end else begin
      $display("[TEST FAIL] %s", test_name);
    end

    $display("============================================================");
    $display("END: %s", test_name);
    $display("============================================================");
  endtask


  // Main

  initial begin
    rst_ni             = 1'b0;
    en_i               = 1'b0;
    div_i              = CNT_WIDTH'(DEFAULT_DIVISION);
    valid_i            = 1'b0;
    error_count        = 0;
    timeout_count      = 0;
    total_handshake_count = 0;
    clk_o_edge_count   = 0;
    clk_o_posedge_count = 0;
    quality_monitor_en = 1'b0;
    clk_o_edge_valid   = 1'b0;
    last_clk_i_edge_time = 0;
    last_clk_o_edge_time = 0;

    if (MAX_DIVISION < 1) begin
      $fatal(1, "MAX_DIVISION must be at least 1");
    end

    if ((DEFAULT_DIVISION < 1) || (DEFAULT_DIVISION > MAX_DIVISION)) begin
      $fatal(
        1,
        "DEFAULT_DIVISION=%0d must be within 1..MAX_DIVISION=%0d",
        DEFAULT_DIVISION,
        MAX_DIVISION
      );
    end
    tc_debug = 1;
    run_test(1,  "Default divisor after reset"); tc_debug = 2;
    run_test(2,  "All legal divisors"); tc_debug = 3;
    run_test(3,  "Latest disabled write wins"); tc_debug = 4;
    run_test(4,  "Configure and enable in same cycle"); tc_debug = 5;
    run_test(5,  "Even to even reconfiguration"); tc_debug = 6;
    run_test(6,  "Even to odd reconfiguration"); tc_debug = 7;
    run_test(7,  "Odd to even reconfiguration"); tc_debug = 8;
    run_test(8,  "Odd to odd reconfiguration"); tc_debug = 9;
    run_test(9,  "Same-divisor request handshakes"); tc_debug = 10;
    run_test(10, "valid_i held after ready_o"); tc_debug = 11;
    run_test(11, "Rapid reconfiguration"); tc_debug = 12;
    run_test(12, "Disable even divider during high phase"); tc_debug = 13;
    run_test(13, "Disable odd divider during high phase"); tc_debug = 14;
    run_test(14, "Disable odd divider during low phase"); tc_debug = 15;
    run_test(15, "Re-enable retains divisor"); tc_debug = 16;
    run_test(16, "Disable and reconfigure in same cycle"); tc_debug = 17;
    run_test(17, "Re-enable while stop/reconfigure is pending"); tc_debug = 18;
    run_test(18, "Reset while running"); tc_debug = 19;
    run_test(19, "Reset during pending request"); tc_debug = 20;
    run_test(20, "Random stress");

    $display("");
    $display("============================================================");
    $display("                    TEST SUMMARY");
    $display("============================================================");
    $display("Total errors     : %0d", error_count);
    $display("Total timeouts   : %0d", timeout_count);
    $display("Total handshakes : %0d", total_handshake_count);

    if (error_count == 0) begin
      $display("RESULT           : PASS");
    end else begin
      $display("RESULT           : FAIL");
    end

    $display("============================================================");
    $display("");

    $finish;
  end


  // Waveform

  initial begin
    $dumpfile("tb_clk_div.fst");
    $dumpvars(0, tb_clk_div);
  end

endmodule

