// =============================================================================
// tb_pulse_sync.sv
// Self-checking testbench for pulse_sync
// =============================================================================

`timescale 1ns/1ps

module tb_pulse_sync;

  // ---------------------------------------------------------------------
  // Clock periods (real, so they can be changed between test phases to
  // cover TC06 - different clock ratios)
  // ---------------------------------------------------------------------
  real SRC_PERIOD = 10.0;   // default 100 MHz
  real DST_PERIOD = 10.0;   // default 100 MHz

  // ---------------------------------------------------------------------
  // DUT signals
  // ---------------------------------------------------------------------
  logic clk_src_i;
  logic rst_src_ni;
  logic pulse_i;
  logic ready_o;

  logic clk_dst_i;
  logic rst_dst_ni;
  logic pulse_o;

  // ---------------------------------------------------------------------
  // Clock generation (variable-period, driven by real vars above)
  // ---------------------------------------------------------------------
  initial begin
    clk_src_i = 1'b0;
    forever #(SRC_PERIOD/2.0) clk_src_i = ~clk_src_i;
  end

  initial begin
    clk_dst_i = 1'b0;
    forever #(DST_PERIOD/2.0) clk_dst_i = ~clk_dst_i;
  end

  // ---------------------------------------------------------------------
  // DUT instantiation
  // ---------------------------------------------------------------------
  pulse_sync dut (
    .clk_src_i  (clk_src_i),
    .rst_src_ni (rst_src_ni),
    .pulse_i    (pulse_i),
    .ready_o    (ready_o),
    .clk_dst_i  (clk_dst_i),
    .rst_dst_ni (rst_dst_ni),
    .pulse_o    (pulse_o)
  );

  // ---------------------------------------------------------------------
  // Bookkeeping / scoreboard
  // ---------------------------------------------------------------------
  int unsigned accepted_count = 0;
  int unsigned pulse_o_count  = 0;
  int unsigned error_count    = 0;
  int unsigned check_count    = 0;

  // Current test case marker
  string       tc_name_now  = "INIT";
  int unsigned tc_index_now = 0;

  // Per-TC statistics
  string       tc_name_l   [$];
  int unsigned tc_checks_l [$];
  int unsigned tc_errors_l [$];

  // ---------------------------------------------------------------------
  // Waveform dump (FST)
  // ---------------------------------------------------------------------
  initial begin
    $dumpfile("waveform.fst");
    $dumpvars(0, tb_pulse_sync);
  end

  // Count destination pulses
  always @(posedge clk_dst_i) begin
    if (pulse_o)
      pulse_o_count++;
  end

  // ---------------------------------------------------------------------
  // Helper tasks
  // ---------------------------------------------------------------------

  // Apply reset to both domains.
  //
  // Reset is intentionally kept short. The DUT is checked for returning
  // to the idle/ready state instead of adding a long fixed settle delay.
  task automatic apply_reset(input int cycles = 2);
    rst_src_ni = 1'b0;
    rst_dst_ni = 1'b0;
    pulse_i    = 1'b0;

    repeat (cycles) @(posedge clk_src_i);

    // Deassert both together, aligned to a source clock edge.
    @(negedge clk_src_i);
    rst_src_ni = 1'b1;
    rst_dst_ni = 1'b1;

    // Wait only until the source side is ready.
    wait_ready(100);
  endtask

  // Reset the DUT between test cases.
  //
  // No long post-TC settle period is used. If the source side is ready,
  // the previous handshake has already completed its round trip.
  task automatic quiesce_and_reset(input int reset_cycles = 2);
    pulse_i = 1'b0;

    wait_ready(100);
    apply_reset(reset_cycles);
  endtask

  // Drive a single-cycle pulse on pulse_i, aligned to clk_src_i.
  // Records whether it was accepted (ready_o == 1 at the driving edge).
  task automatic send_src_pulse(output bit was_accepted);
    @(negedge clk_src_i);

    was_accepted = ready_o;

    if (ready_o)
      accepted_count++;

    pulse_i = 1'b1;

    @(negedge clk_src_i);
    pulse_i = 1'b0;

    // Local confirmation that an accepted event made the source busy.
    if (was_accepted) begin
      check(ready_o == 1'b0,
            "send_src_pulse: ready_o deasserted (busy) right after an accepted event");
    end
  endtask

  // Wait until ready_o is high.
  task automatic wait_ready(input int timeout_cycles = 1000);
    int n;

    n = 0;

    while (!ready_o && n < timeout_cycles) begin
      @(posedge clk_src_i);
      n++;
    end

    if (n >= timeout_cycles) begin
      check_count++;
      error_count++;
      $display("[FAIL][TIMEOUT] ready_o did not go high within %0d src cycles",
               timeout_cycles);
    end
  endtask

  // Wait for a pulse_o event.
  task automatic wait_pulse_o(
    input  int timeout_cycles,
    output bit seen
  );
    int n;

    n    = 0;
    seen = 0;

    while (n < timeout_cycles) begin
      @(posedge clk_dst_i);

      if (pulse_o) begin
        seen = 1;

        // Allow the pulse counter process on the same posedge to complete.
        @(negedge clk_dst_i);
        break;
      end

      n++;
    end

    if (!seen) begin
      check_count++;
      error_count++;
      $display("[FAIL][TIMEOUT] pulse_o did not arrive within %0d dst cycles",
               timeout_cycles);
    end
  endtask

  // check() never stops simulation on failure.
  task automatic check(input bit cond, input string msg);
    check_count++;

    if (!cond) begin
      error_count++;
      $display("[FAIL] %s", msg);
    end
    else begin
      $display("[PASS] %s", msg);
    end
  endtask

  // ---------------------------------------------------------------------
  // TC01 - Reset
  // ---------------------------------------------------------------------
  task automatic tc01_reset();
    $display("\n===== TC01: Reset =====");

    SRC_PERIOD = 10.0;
    DST_PERIOD = 10.0;

    quiesce_and_reset();

    check(pulse_o == 1'b0,
          "TC01: pulse_o is 0 after reset");

    check(ready_o == 1'b1,
          "TC01: ready_o is 1 (idle, req==ack) after reset");
  endtask

  // ---------------------------------------------------------------------
  // TC02 - Single pulse
  // ---------------------------------------------------------------------
  task automatic tc02_single_pulse();
    bit accepted;
    bit seen;
    int unsigned base_count;

    $display("\n===== TC02: Single pulse =====");

    quiesce_and_reset();
    base_count = pulse_o_count;

    send_src_pulse(accepted);

    check(accepted,
          "TC02: event was accepted (ready_o was high)");

    wait_pulse_o(1000, seen);

    check(seen,
          "TC02: pulse_o observed after single accepted event");

    check((pulse_o_count - base_count) == 1,
          "TC02: exactly one pulse_o generated for one event");
  endtask

  // ---------------------------------------------------------------------
  // TC03 - Multiple pulses
  // ---------------------------------------------------------------------
  task automatic tc03_multiple_pulses();
    bit accepted;
    bit seen;
    int unsigned base_count;
    int N;

    $display("\n===== TC03: Multiple pulses =====");

    quiesce_and_reset();

    N = 5;
    base_count = pulse_o_count;

    for (int i = 0; i < N; i++) begin
      wait_ready();

      send_src_pulse(accepted);

      check(accepted,
            $sformatf("TC03: event %0d accepted", i));

      wait_pulse_o(1000, seen);

      check(seen,
            $sformatf("TC03: pulse_o seen for event %0d", i));
    end

    check((pulse_o_count - base_count) == N,
          $sformatf("TC03: %0d events -> %0d pulse_o (got %0d)",
                    N, N, pulse_o_count - base_count));
  endtask

  // ---------------------------------------------------------------------
  // TC04 - Busy
  // ---------------------------------------------------------------------
  task automatic tc04_busy();
    bit seen;
    int unsigned base_count;

    $display("\n===== TC04: Busy =====");

    quiesce_and_reset();
    base_count = pulse_o_count;

    // First event: accepted.
    @(negedge clk_src_i);

    check(ready_o == 1'b1,
          "TC04: ready_o high before first event");

    accepted_count++;

    pulse_i = 1'b1;

    @(negedge clk_src_i);
    pulse_i = 1'b0;

    // Second event while busy.
    @(negedge clk_src_i);

    check(ready_o == 1'b0,
          "TC04: ready_o low right after first event (busy)");

    if (ready_o == 1'b0) begin
      pulse_i = 1'b1;

      @(negedge clk_src_i);
      pulse_i = 1'b0;
    end

    wait_pulse_o(1000, seen);

    check(seen,
          "TC04: pulse_o seen for the first (accepted) event");

    // Only a short guard is needed because the handshake has completed
    // before wait_pulse_o() returns.
    repeat (10) @(posedge clk_dst_i);

    check((pulse_o_count - base_count) == 1,
          $sformatf(
            "TC04: only 1 pulse_o for 1 accepted event while busy (got %0d)",
            pulse_o_count - base_count
          ));
  endtask

  // ---------------------------------------------------------------------
  // TC05 - Back-to-back events
  // ---------------------------------------------------------------------
  task automatic tc05_back_to_back();
    bit accepted;
    bit seen;
    int unsigned base_count;
    int N;

    $display("\n===== TC05: Back-to-back events =====");

    quiesce_and_reset();

    N = 8;
    base_count = pulse_o_count;

    // ready_o returns only after the full round trip of the previous event.
    // Therefore pulse_o is observed immediately after each accepted event.
    for (int i = 0; i < N; i++) begin
      wait_ready();

      send_src_pulse(accepted);

      check(accepted,
            $sformatf("TC05: back-to-back event %0d accepted", i));

      wait_pulse_o(2000, seen);

      check(seen,
            $sformatf("TC05: pulse_o %0d observed (no loss)", i));
    end

    check((pulse_o_count - base_count) == N,
          $sformatf(
            "TC05: no lost/duplicated events (expected %0d, got %0d)",
            N, pulse_o_count - base_count
          ));
  endtask

  // ---------------------------------------------------------------------
  // TC06 - Different clock ratios
  // ---------------------------------------------------------------------
  task automatic run_n_events(input int N);
    bit accepted;
    bit seen;
    int unsigned base_count;

    base_count = pulse_o_count;

    for (int i = 0; i < N; i++) begin
      wait_ready();

      send_src_pulse(accepted);

      check(accepted,
            $sformatf(
              "TC06: event %0d accepted (src=%.1fns dst=%.1fns)",
              i, SRC_PERIOD, DST_PERIOD
            ));

      wait_pulse_o(5000, seen);

      check(seen,
            $sformatf(
              "TC06: pulse_o %0d seen (src=%.1fns dst=%.1fns)",
              i, SRC_PERIOD, DST_PERIOD
            ));
    end

    check((pulse_o_count - base_count) == N,
          $sformatf(
            "TC06: %0d/%0d transferred correctly (src=%.1fns dst=%.1fns)",
            pulse_o_count - base_count, N, SRC_PERIOD, DST_PERIOD
          ));
  endtask

  task automatic tc06_clock_ratios();
    $display("\n===== TC06: Different clock frequencies =====");

    // Case A: src fast, dst slow
    SRC_PERIOD = 4.0;
    DST_PERIOD = 17.0;

    quiesce_and_reset();
    run_n_events(4);

    // Case B: src slow, dst fast
    SRC_PERIOD = 23.0;
    DST_PERIOD = 6.0;

    quiesce_and_reset();
    run_n_events(4);

    // Case C: equal frequency, arbitrary phase
    SRC_PERIOD = 10.0;
    DST_PERIOD = 10.0;

    quiesce_and_reset();
    run_n_events(4);

    // Restore default.
    SRC_PERIOD = 10.0;
    DST_PERIOD = 10.0;
  endtask

  // ---------------------------------------------------------------------
  // TC07 - pulse_o width == exactly 1 clk_dst_i cycle
  // ---------------------------------------------------------------------
  task automatic tc07_pulse_width();
    bit accepted;
    time t_rise;
    time t_fall;
    int unsigned high_cycles;

    $display("\n===== TC07: Pulse width =====");

    SRC_PERIOD = 9.0;
    DST_PERIOD = 13.0;

    quiesce_and_reset();

    send_src_pulse(accepted);

    check(accepted,
          "TC07: event accepted");

    // Wait for pulse_o to rise.
    while (!pulse_o)
      @(posedge clk_dst_i);

    t_rise = $time;

    // Count consecutive destination cycles.
    high_cycles = 0;

    while (pulse_o) begin
      high_cycles++;
      @(posedge clk_dst_i);
    end

    t_fall = $time;

    check(high_cycles == 1,
          $sformatf(
            "TC07: pulse_o high for exactly 1 clk_dst_i cycle (got %0d, %0.1fns)",
            high_cycles, real'(t_fall - t_rise)
          ));

    SRC_PERIOD = 10.0;
    DST_PERIOD = 10.0;
  endtask

  // ---------------------------------------------------------------------
  // TC08 - Random stress
  // ---------------------------------------------------------------------
  task automatic tc08_random_stress();
    bit accepted;
    int unsigned base_accept;
    int unsigned base_pulse;
    int N;
    int gap;

    $display("\n===== TC08: Random stress =====");

    SRC_PERIOD = 3.0 + $urandom_range(0, 20);
    DST_PERIOD = 3.0 + $urandom_range(0, 20);

    quiesce_and_reset();

    base_accept = accepted_count;
    base_pulse  = pulse_o_count;

    N = 200;

    for (int i = 0; i < N; i++) begin
      // Random gap between events, including gaps too short to be ready.
      gap = $urandom_range(0, 15);

      repeat (gap)
        @(posedge clk_src_i);

      send_src_pulse(accepted);

      // Occasionally fire a second unsolicited pulse.
      if ($urandom_range(0, 3) == 0)
        send_src_pulse(accepted);
    end

    // Only drain after the final event burst.
    repeat (100) @(posedge clk_dst_i);

    check((accepted_count - base_accept) ==
          (pulse_o_count - base_pulse),
          $sformatf(
            "TC08: accepted events (%0d) == pulse_o count (%0d) [src=%.1fns dst=%.1fns]",
            accepted_count - base_accept,
            pulse_o_count - base_pulse,
            SRC_PERIOD,
            DST_PERIOD
          ));

    SRC_PERIOD = 10.0;
    DST_PERIOD = 10.0;
  endtask

  // ---------------------------------------------------------------------
  // Test-case bookkeeping
  // ---------------------------------------------------------------------
  task automatic run_tc(
    input string name,
    ref int e_before,
    ref int c_before
  );
    tc_name_l.push_back(name);
    tc_checks_l.push_back(check_count - c_before);
    tc_errors_l.push_back(error_count - e_before);
  endtask

  task automatic begin_tc(
    input string name,
    input int idx
  );
    tc_name_now  = name;
    tc_index_now = idx;

    $display("\n>>> Entering %s (index %0d) @ %0t",
             name, idx, $time);
  endtask

  // ---------------------------------------------------------------------
  // Main sequence - TC01..TC08
  // ---------------------------------------------------------------------
  initial begin
    int e0;
    int c0;

    rst_src_ni = 1'b1;
    rst_dst_ni = 1'b1;
    pulse_i    = 1'b0;

    tc_name_now  = "INIT";
    tc_index_now = 0;

    begin_tc("TC01 Reset", 1);
    e0 = error_count;
    c0 = check_count;
    tc01_reset();
    run_tc("TC01 Reset", e0, c0);

    begin_tc("TC02 Single pulse", 2);
    e0 = error_count;
    c0 = check_count;
    tc02_single_pulse();
    run_tc("TC02 Single pulse", e0, c0);

    begin_tc("TC03 Multiple pulses", 3);
    e0 = error_count;
    c0 = check_count;
    tc03_multiple_pulses();
    run_tc("TC03 Multiple pulses", e0, c0);

    begin_tc("TC04 Busy", 4);
    e0 = error_count;
    c0 = check_count;
    tc04_busy();
    run_tc("TC04 Busy", e0, c0);

    begin_tc("TC05 Back-to-back", 5);
    e0 = error_count;
    c0 = check_count;
    tc05_back_to_back();
    run_tc("TC05 Back-to-back", e0, c0);

    begin_tc("TC06 Clock ratios", 6);
    e0 = error_count;
    c0 = check_count;
    tc06_clock_ratios();
    run_tc("TC06 Clock ratios", e0, c0);

    begin_tc("TC07 Pulse width", 7);
    e0 = error_count;
    c0 = check_count;
    tc07_pulse_width();
    run_tc("TC07 Pulse width", e0, c0);

    begin_tc("TC08 Random stress", 8);
    e0 = error_count;
    c0 = check_count;
    tc08_random_stress();
    run_tc("TC08 Random stress", e0, c0);

    tc_name_now  = "DONE";
    tc_index_now = 9;

    // ---------------------------------------------------------------
    // Summary
    // ---------------------------------------------------------------
    $display("\n=====================================================================");
    $display("  TEST CASE SUMMARY");
    $display("=====================================================================");
    $display("  %-24s %10s %10s %10s",
             "Test Case", "Checks", "Fails", "Result");
    $display("  ---------------------------------------------------------------");

    for (int i = 0; i < tc_name_l.size(); i++) begin
      $display("  %-24s %10d %10d %10s",
               tc_name_l[i],
               tc_checks_l[i],
               tc_errors_l[i],
               (tc_errors_l[i] == 0) ? "PASS" : "FAIL");
    end

    $display("  ---------------------------------------------------------------");
    $display("  %-24s %10d %10d %10s",
             "TOTAL",
             check_count,
             error_count,
             (error_count == 0) ? "PASS" : "FAIL");
    $display("=====================================================================");

    if (error_count == 0) begin
      $display("  RESULT: ALL TESTS PASSED (TC01-TC08)");
    end
    else begin
      $display(
        "  RESULT: %0d FAILING CHECK(S) OUT OF %0d ACROSS %0d TEST CASE(S)",
        error_count,
        check_count,
        tc_name_l.size()
      );
    end

    $display("=====================================================================\n");

    $finish;
  end

  // ---------------------------------------------------------------------
  // Safety watchdog
  // ---------------------------------------------------------------------
  initial begin
    #2_000_000;

    $display("[FAIL][TIMEOUT] Global testbench watchdog expired - simulation hung");

    error_count++;
    $finish;
  end

endmodule
