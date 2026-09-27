`timescale 1ns/1ps
//=============================================================================
// tb_wdt.sv
//
// Self-checking testbench for the `wdt` module, implementing TC01..TC18 from
// the WDT Testbench Specification. The testbench drives and observes only
// the module's external ports (no internal probing), per the spec's
// requirement that behavior be verified without depending on the internal
// implementation.
//
// IMPORTANT ASSUMPTIONS (tune to match the actual DUT if needed):
//   - SYNC_LATENCY_REF / SYNC_LATENCY_SRC bound the CDC synchronization
//     latency (in destination-domain cycles) that the testbench allows for
//     enable/kick/timeout to cross clock domains. If the real DUT uses a
//     deeper synchronizer, increase these margins.
//   - `timer_default_i`, `timer_threshold_i`, `kick_key_i` are treated as
//     quasi-static configuration, established before `timer_enable_i` is
//     asserted, per section 5 of the spec.
//   - COUNT DIRECTION: the spec is implementation-agnostic about whether the
//     timer counts up from default to threshold or down from default to
//     threshold. This testbench assumes DEFAULT_VAL < THRESHOLD_VAL, i.e. an
//     UP-counting timer that starts at DEFAULT_VAL and times out on reaching
//     THRESHOLD_VAL. If the real DUT counts DOWN (starts at default, times
//     out at/below threshold), swap DEFAULT_VAL/THRESHOLD_VAL so that
//     DEFAULT_VAL > THRESHOLD_VAL; INTERVAL is computed as an absolute
//     difference below so the rest of the testbench does not need to change.
//=============================================================================

module tb_wdt;

  //==========================================================
  // Parameters
  //==========================================================
  localparam int unsigned TIMER_WIDTH = 16;
  localparam int unsigned KICK_WIDTH  = 8;

  // Default clock periods (equal-frequency default test configuration).
  // TC16 temporarily overrides these to sweep clock ratios/phases.
  time SRC_CLK_PERIOD = 5ns;
  time REF_CLK_PERIOD = 100ns;

  // CDC synchronization latency margins (destination-domain cycles).
  // NOTE: tune to the real DUT's synchronizer depth.
  localparam int SYNC_LATENCY_REF = 2;
  localparam int SYNC_LATENCY_SRC = 2;

  // Common small values used across most tests (kept small for fast sim).
  // See the COUNT DIRECTION note above: this testbench assumes an
  // up-counting timer (DEFAULT_VAL < THRESHOLD_VAL). Swap the two constants
  // if the DUT counts down instead.
  localparam logic [TIMER_WIDTH-1:0] DEFAULT_VAL   = 16'h0000;
  localparam logic [TIMER_WIDTH-1:0] THRESHOLD_VAL = 16'h0020;
  localparam logic [KICK_WIDTH-1:0]  KEY_VAL       = 8'hA5;

  // Interval computed once as an explicit 32-bit int so it can be used
  // directly in int-typed task arguments (wait_ref_cycles/wait_for_timeout)
  // without Verilator WIDTHEXPAND warnings from implicit 16->32 bit growth.
  // Computed as an absolute difference so the testbench body is agnostic to
  // whether DEFAULT_VAL is below or above THRESHOLD_VAL.
  localparam int INTERVAL = (int'(THRESHOLD_VAL) >= int'(DEFAULT_VAL)) ?
                             (int'(THRESHOLD_VAL) - int'(DEFAULT_VAL)) :
                             (int'(DEFAULT_VAL) - int'(THRESHOLD_VAL));

  //==========================================================
  // DUT signals
  //==========================================================
  logic [TIMER_WIDTH-1:0] timer_default_i;
  logic [TIMER_WIDTH-1:0] timer_threshold_i;
  logic                   timer_enable_i;
  logic [KICK_WIDTH-1:0]  kick_key_i;

  logic                   clk_src_i;
  logic                   rst_src_ni;
  logic [KICK_WIDTH-1:0]  kick_i;

  logic                   timeout_irq_o;

  logic                   clk_ref_i;
  logic                   rst_ref_ni;

  //==========================================================
  // Scoreboard
  //==========================================================
  int    num_tests       = 0;
  int    num_checks      = 0;
  int    num_check_pass  = 0;
  int    num_check_fail  = 0;
  int    num_assert_fail = 0;
  int    num_func_fail   = 0;
  string current_tc      = "NONE";

  // Waveform-friendly test-case marker. `current_tc` (string) is convenient
  // for $display, but many VCD viewers show SystemVerilog strings poorly or
  // not at all. `tc_id_active` is a plain enum/int signal that shows up as
  // a numeric (or, on FST + tools that decode SV enums, a named) trace so
  // you can scrub the waveform and immediately see which TC was running at
  // any given time.
  //
  // NOTE: values are assigned in the exact order TC01..TC18 are called in
  // the `initial` test-sequence block below. start_tc() derives tc_id_active
  // from num_tests (its call count), so if you reorder/add/remove calls in
  // the test sequence, this enum's declaration order must be kept in sync.
  typedef enum int unsigned {
    TC_IDLE = 0,
    TC01_RESET,
    TC02_ENABLE,
    TC03_DISABLED_STATE,
    TC04_TIMER_COUNTING,
    TC05_KICK_RELOAD,
    TC06_INVALID_KICK,
    TC07_KICK_BETWEEN_SAMPLES,
    TC08_KICK_ASSERT_DEASSERT,
    TC09_KICK_HELD_ACTIVE,
    TC10_TIMEOUT,
    TC11_TIMEOUT_PERSISTENCE,
    TC12_TIMEOUT_PRIORITY_OVER_KICK,
    TC13_TIMEOUT_CLEAR_BY_DISABLE,
    TC14_RESTART_AFTER_TIMEOUT,
    TC15_ENABLE_DISABLE_TRANSITION,
    TC16_CLOCK_RATIO,
    TC17_RESET_DURING_NORMAL_OPERATION,
    TC18_RESET_DURING_TIMEOUT,
    TC19_RANDOM_TEST,
    TC_DONE
  } tc_id_e;

  tc_id_e tc_id_active = TC_IDLE;

  //==========================================================
  // DUT instantiation
  //==========================================================
  wdt #(
    .TIMER_WIDTH (TIMER_WIDTH),
    .KICK_WIDTH  (KICK_WIDTH)
  ) dut (
    .timer_default_i   (timer_default_i),
    .timer_threshold_i (timer_threshold_i),
    .timer_enable_i    (timer_enable_i),
    .kick_key_i        (kick_key_i),

    .clk_src_i         (clk_src_i),
    .rst_src_ni        (rst_src_ni),
    .kick_i            (kick_i),

    .timeout_irq_o     (timeout_irq_o),

    .clk_ref_i         (clk_ref_i),
    .rst_ref_ni        (rst_ref_ni)
  );

  //==========================================================
  // Clock generation
  //==========================================================
  initial begin
    clk_src_i = 1'b0;
    forever begin
      #(SRC_CLK_PERIOD/2);
      clk_src_i = ~clk_src_i;
    end
  end

  initial begin
    clk_ref_i = 1'b0;
    forever begin
      #(REF_CLK_PERIOD/2);
      clk_ref_i = ~clk_ref_i;
    end
  end

  //==========================================================
  // Reset tasks
  //==========================================================
  task automatic assert_src_reset();   rst_src_ni = 1'b0; endtask
  task automatic deassert_src_reset(); rst_src_ni = 1'b1; endtask
  task automatic assert_ref_reset();   rst_ref_ni = 1'b0; endtask
  task automatic deassert_ref_reset(); rst_ref_ni = 1'b1; endtask

  task automatic pulse_reset_both(int src_cycles = 4, int ref_cycles = 4);
    // NOTE: assert_src_reset()/assert_ref_reset() change rst_*_ni
    // combinationally (not aligned to a clock edge) before the first
    // @(posedge clk_*_i) below. This is fine on Verilator with the current
    // sequential `initial` flow, but if this TB is ever driven from
    // multiple concurrent processes, or ported to a simulator/RTL more
    // sensitive to same-timestep races, align these assignments to a
    // clock edge (e.g. via @(negedge clk_src_i)) before asserting reset.
    assert_src_reset();
    assert_ref_reset();
    repeat (src_cycles) @(posedge clk_src_i);
    repeat (ref_cycles) @(posedge clk_ref_i);
    deassert_src_reset();
    deassert_ref_reset();
    repeat (2) @(posedge clk_ref_i);
  endtask

  //==========================================================
  // Wait helpers
  //==========================================================
  task automatic wait_src_cycles(int n); repeat (n) @(posedge clk_src_i); endtask
  task automatic wait_ref_cycles(int n); repeat (n) @(posedge clk_ref_i); endtask

  //==========================================================
  // Configuration / control tasks
  //==========================================================
  task automatic configure_wdt(
      input logic [TIMER_WIDTH-1:0] def_val,
      input logic [TIMER_WIDTH-1:0] thr_val,
      input logic [KICK_WIDTH-1:0]  key_val
  );
    #0.1; timer_default_i   = def_val;
    #0.1; timer_threshold_i = thr_val;
    #0.1; kick_key_i        = key_val;
    wait_ref_cycles(1);
  endtask

  task automatic enable_wdt();  #0.1; timer_enable_i = 1'b1; endtask
  task automatic disable_wdt(); #0.1; timer_enable_i = 1'b0; endtask

  task automatic apply_kick_pulse(
      input logic [KICK_WIDTH-1:0] key_val,
      input int src_cycles_active
  );
    #0.1; kick_i = key_val;
    #0.1; wait_src_cycles(src_cycles_active);
    #0.1; kick_i = key_val ^ {KICK_WIDTH{1'b1}};
  endtask

  task automatic drive_invalid_kick(int src_cycles_active);
    logic [KICK_WIDTH-1:0] bad_key;
    logic [KICK_WIDTH-1:0] idle_key;

    // Bitwise complement is guaranteed != kick_key_i for any key value
    // (a value can never equal its own complement), unlike a fixed XOR
    // pattern that would only happen to differ for a specific KEY_VAL.
    #0.1; bad_key = ~kick_key_i;
    #0.1; kick_i  = bad_key;
    #0.1; wait_src_cycles(src_cycles_active);

    // Idle value after the pulse must also stay non-matching. XOR with any
    // nonzero constant is guaranteed to differ from kick_key_i, regardless
    // of KEY_VAL's specific bit pattern.
    #0.1; idle_key = kick_key_i ^ 8'h3C;
    #0.1; kick_i   = idle_key;
  endtask

  //==========================================================
  // Check / report helpers
  //==========================================================
  task automatic check(input bit cond, input string msg);
    num_checks++;
    if (cond) begin
      num_check_pass++;
      $display("[%0t] CHECK PASS (%s): %s", $time, current_tc, msg);
    end else begin
      num_check_fail++;
      num_func_fail++;
      $display("[%0t] CHECK FAIL (%s): %s", $time, current_tc, msg);
    end
  endtask

  task automatic start_tc(input string name);
    current_tc = name;
    num_tests++;
    // num_tests counts 1..18 in the same order TC01..TC18 are invoked, which
    // matches the enum declaration order above, so a direct cast gives the
    // correct marker without touching every start_tc() call site.
    if (num_tests <= int'(TC_DONE) - 1)
      tc_id_active = tc_id_e'(num_tests);
    $display("\n===== Starting %s =====", name);
  endtask

  task automatic end_tc();
    $display("===== Finished %s =====", current_tc);
  endtask

  // Waits up to max_ref_cycles ref-clock cycles for timeout_irq_o to assert.
  task automatic wait_for_timeout(input int max_ref_cycles, output bit got_timeout);
    int i;
    got_timeout = 1'b0;
    for (i = 0; i < max_ref_cycles; i++) begin
      @(posedge clk_ref_i);
      if (timeout_irq_o) begin
        got_timeout = 1'b1;
        break;
      end
    end
  endtask

  //==========================================================
  // Concurrent assertions (external-signal only)
  //==========================================================

  // Once timeout is asserted while enabled and not in reset, it must remain
  // asserted (latched) until disable or reset (TC11/TC12).
  //
  // Per spec section 8/11, timeout_irq_o is generated in the SOURCE domain
  // and is only cleared by disable or rst_src_ni (not rst_ref_ni). All three
  // properties below are therefore sampled on clk_src_i and gated by
  // rst_src_ni, so they stay correct even for a test that resets one domain
  // without the other (this TB currently always resets both together via
  // pulse_reset_both(), but the properties should not silently depend on
  // that).
  property p_timeout_persistent;
    @(posedge clk_src_i) disable iff (!rst_src_ni)
      (timeout_irq_o && timer_enable_i) |=> timeout_irq_o;
  endproperty
  ASSERT_TIMEOUT_PERSISTENT: assert property (p_timeout_persistent)
    else begin num_assert_fail++; $display("[%0t] ASSERT FAIL: timeout not persistent", $time); end

  // timeout_irq_o must be deasserted at the first src-clock sample after
  // rst_src_ni deassertion (TC17/TC18).
  property p_reset_clears_timeout;
    @(posedge clk_src_i) $rose(rst_src_ni) |-> !timeout_irq_o;
  endproperty
  ASSERT_RESET_CLEARS_TIMEOUT: assert property (p_reset_clears_timeout)
    else begin num_assert_fail++; $display("[%0t] ASSERT FAIL: timeout not clear after reset", $time); end

  // timeout_irq_o must be low while source-domain reset is asserted.
  property p_timeout_low_in_reset;
    @(posedge clk_src_i) (!rst_src_ni) |-> !timeout_irq_o;
  endproperty
  ASSERT_TIMEOUT_LOW_IN_RESET: assert property (p_timeout_low_in_reset)
    else begin num_assert_fail++; $display("[%0t] ASSERT FAIL: timeout asserted during reset", $time); end

  //==========================================================
  // Functional coverage
  //==========================================================
  // Sampling is gated by the relevant domain's reset so bins are not
  // polluted by meaningless values captured while that domain is in reset.
  covergroup cg_enable @(posedge clk_ref_i iff rst_ref_ni);
    option.per_instance = 1;
    cp_enable:  coverpoint timer_enable_i { bins disabled = {0}; bins enabled = {1}; }
    cp_timeout: coverpoint timeout_irq_o  { bins no_timeout = {0}; bins timeout = {1}; }
  endgroup

  covergroup cg_kick @(posedge clk_src_i iff rst_src_ni);
    option.per_instance = 1;
    cp_kick_match: coverpoint (kick_i == kick_key_i) { bins valid_kick = {1}; bins invalid_kick = {0}; }
  endgroup

  cg_enable cg_enable_i;
  cg_kick   cg_kick_i;

  initial begin
    cg_enable_i = new();
    cg_kick_i   = new();
  end

  //==========================================================
  // Waveform dump (level 0 = dump this scope and all sub-scopes/instances)
  //==========================================================
  initial begin
    $dumpfile("tb_wdt.fst");
    $dumpvars(0, tb_wdt);
  end

  //==========================================================
  // Test sequence
  //==========================================================
  initial begin
    timer_default_i   = DEFAULT_VAL;
    timer_threshold_i = THRESHOLD_VAL;
    timer_enable_i    = 1'b0;
    kick_key_i        = KEY_VAL;
    kick_i            = KEY_VAL ^ 8'hFF;
    rst_src_ni        = 1'b0;
    rst_ref_ni        = 1'b0;

    wait_ref_cycles(2);

    tc01_reset();
    tc02_enable();
    tc03_disabled_state();
    tc04_timer_counting();
    tc05_kick_reload();
    tc06_invalid_kick();
    tc07_kick_between_samples();
    tc08_kick_assert_deassert();
    tc09_kick_held_active();
    tc10_timeout();
    tc11_timeout_persistence();
    tc12_timeout_priority_over_kick();
    tc13_timeout_clear_by_disable();
    tc14_restart_after_timeout();
    tc15_enable_disable_transition();
    tc16_clock_ratio();
    tc17_reset_during_normal_operation();
    tc18_reset_during_timeout();
    tc19_random_test();

    tc_id_active = TC_DONE;
    final_report();
    $finish;
  end

  //----------------------------------------------------------
  // TC01 — Reset
  //----------------------------------------------------------
  task automatic tc01_reset();
    start_tc("TC01_Reset");
    timer_enable_i = 1'b0;
    kick_i         = kick_key_i ^ 8'hFF;
    pulse_reset_both(4, 4);

    check(!timeout_irq_o, "Timeout inactive after reset");
    wait_ref_cycles(5);
    check(!timeout_irq_o, "No spurious timeout after reset while disabled");
    end_tc();
  endtask

  //----------------------------------------------------------
  // TC02 — Enable
  //----------------------------------------------------------
  task automatic tc02_enable();
    bit got_timeout;
    start_tc("TC02_Enable");

    pulse_reset_both();
    configure_wdt(DEFAULT_VAL, THRESHOLD_VAL, KEY_VAL);
    timer_enable_i = 1'b0;
    wait_ref_cycles(5);
    check(!timeout_irq_o, "Timer inactive before enable");

    enable_wdt();
    wait_ref_cycles(SYNC_LATENCY_REF);
    check(!timeout_irq_o, "No immediate timeout right after enable");

    wait_for_timeout(INTERVAL + SYNC_LATENCY_REF + 10, got_timeout);
    check(got_timeout, "Timer counts up to threshold after enable");

    disable_wdt();
    wait_ref_cycles(SYNC_LATENCY_REF);
    end_tc();
  endtask

  //----------------------------------------------------------
  // TC03 — Disabled State
  //----------------------------------------------------------
  task automatic tc03_disabled_state();
    bit any_timeout_seen;
    int i;
    start_tc("TC03_Disabled_State");

    pulse_reset_both();
    configure_wdt(DEFAULT_VAL, THRESHOLD_VAL, KEY_VAL);
    disable_wdt();

    any_timeout_seen = 1'b0;
    for (i = 0; i < 50; i++) begin
      @(posedge clk_ref_i);
      if (timeout_irq_o) any_timeout_seen = 1'b1;
    end
    check(!any_timeout_seen, "Timeout remains inactive while disabled");
    end_tc();
  endtask

  //----------------------------------------------------------
  // TC04 — Timer Counting
  //----------------------------------------------------------
  task automatic tc04_timer_counting();
    bit got_timeout;
    start_tc("TC04_Timer_Counting");

    pulse_reset_both();
    configure_wdt(DEFAULT_VAL, THRESHOLD_VAL, KEY_VAL);
    enable_wdt();

    wait_ref_cycles((INTERVAL) / 2);
    check(!timeout_irq_o, "No premature timeout before threshold reached");

    wait_for_timeout(INTERVAL + SYNC_LATENCY_REF + 10, got_timeout);
    check(got_timeout, "Timer eventually reaches threshold and times out");

    disable_wdt();
    wait_ref_cycles(SYNC_LATENCY_REF);
    end_tc();
  endtask

  //----------------------------------------------------------
  // TC05 — Kick Reload
  //----------------------------------------------------------
  task automatic tc05_kick_reload();
    bit got_timeout;
    start_tc("TC05_Kick_Reload");

    pulse_reset_both();
    configure_wdt(DEFAULT_VAL, THRESHOLD_VAL, KEY_VAL);
    enable_wdt();

    wait_ref_cycles((INTERVAL) / 2);
    apply_kick_pulse(KEY_VAL, 3);
    wait_ref_cycles(SYNC_LATENCY_REF);

    wait_for_timeout((INTERVAL) / 2, got_timeout);
    check(!got_timeout, "No timeout shortly after kick (timer reloaded)");

    wait_for_timeout(INTERVAL + SYNC_LATENCY_REF + 10, got_timeout);
    check(got_timeout, "Timer reaches timeout a full interval after reload");

    disable_wdt();
    wait_ref_cycles(SYNC_LATENCY_REF);
    end_tc();
  endtask

  //----------------------------------------------------------
  // TC06 — Invalid Kick
  //----------------------------------------------------------
  task automatic tc06_invalid_kick();
    bit got_timeout;
    start_tc("TC06_Invalid_Kick");

    pulse_reset_both();
    configure_wdt(DEFAULT_VAL, THRESHOLD_VAL, KEY_VAL);
    enable_wdt();

    wait_ref_cycles((INTERVAL) / 2);
    drive_invalid_kick(3);
    wait_ref_cycles(SYNC_LATENCY_REF);

    wait_for_timeout((INTERVAL) / 2 + SYNC_LATENCY_REF + 10, got_timeout);
    check(got_timeout, "Timeout still occurs on original schedule (no reload from invalid kick)");

    disable_wdt();
    wait_ref_cycles(SYNC_LATENCY_REF);
    end_tc();
  endtask

  //----------------------------------------------------------
  // TC07 — Kick Between Reference-Clock Samples
  //----------------------------------------------------------
  task automatic tc07_kick_between_samples();
    bit got_timeout;
    int phase_shift;
    start_tc("TC07_Kick_Between_Ref_Samples");

    pulse_reset_both();
    configure_wdt(DEFAULT_VAL, THRESHOLD_VAL, KEY_VAL);
    enable_wdt();

    for (phase_shift = 0; phase_shift < 2; phase_shift++) begin
      wait_ref_cycles((INTERVAL) / 3);
      @(posedge clk_ref_i);
      if (phase_shift == 0)
        #(REF_CLK_PERIOD/4);
      else
        #(REF_CLK_PERIOD*3/4);

      apply_kick_pulse(KEY_VAL, 2);
      wait_ref_cycles(SYNC_LATENCY_REF);

      wait_for_timeout((INTERVAL) / 3, got_timeout);
      check(!got_timeout, $sformatf("Kick near ref edge (phase %0d) not lost; no premature timeout", phase_shift));
    end

    disable_wdt();
    wait_ref_cycles(SYNC_LATENCY_REF);
    end_tc();
  endtask

  //----------------------------------------------------------
  // TC08 — Kick Assertion and Deassertion
  //----------------------------------------------------------
  task automatic tc08_kick_assert_deassert();
    bit got_timeout;
    int durations[3];
    int i;
    start_tc("TC08_Kick_Assert_Deassert");

    durations[0] = 1;
    durations[1] = 5;
    durations[2] = 20;

    pulse_reset_both();
    configure_wdt(DEFAULT_VAL, THRESHOLD_VAL, KEY_VAL);
    enable_wdt();

    for (i = 0; i < 3; i++) begin
      wait_ref_cycles((INTERVAL) / 4);
      apply_kick_pulse(KEY_VAL, durations[i]);
      wait_ref_cycles(SYNC_LATENCY_REF);
      wait_for_timeout((INTERVAL) / 4, got_timeout);
      check(!got_timeout, $sformatf("No spurious/extra timeout after kick of duration %0d src cycles", durations[i]));
    end

    disable_wdt();
    wait_ref_cycles(SYNC_LATENCY_REF);
    end_tc();
  endtask

  //----------------------------------------------------------
  // TC09 — Kick Held Active
  //----------------------------------------------------------
  task automatic tc09_kick_held_active();
    bit got_timeout;
    start_tc("TC09_Kick_Held_Active");

    pulse_reset_both();
    configure_wdt(DEFAULT_VAL, THRESHOLD_VAL, KEY_VAL);
    enable_wdt();

    wait_ref_cycles((INTERVAL) / 3);
    kick_i = KEY_VAL;
    wait_src_cycles(30);
    kick_i = KEY_VAL ^ 8'hFF;
    wait_ref_cycles(SYNC_LATENCY_REF);

    wait_for_timeout((INTERVAL) / 3, got_timeout);
    check(!got_timeout, "No unintended timeout immediately after long-held kick released");

    disable_wdt();
    wait_ref_cycles(SYNC_LATENCY_REF);
    end_tc();
  endtask

  //----------------------------------------------------------
  // TC10 — Timeout
  //----------------------------------------------------------
  task automatic tc10_timeout();
    bit got_timeout;
    start_tc("TC10_Timeout");

    pulse_reset_both();
    configure_wdt(DEFAULT_VAL, THRESHOLD_VAL, KEY_VAL);
    enable_wdt();
    kick_i = KEY_VAL ^ 8'hFF;

    wait_for_timeout(INTERVAL + SYNC_LATENCY_REF + 10, got_timeout);
    check(got_timeout, "Timeout detected when threshold reached");
    check(timeout_irq_o, "timeout_irq_o asserted after expected synchronization latency");

    disable_wdt();
    wait_ref_cycles(SYNC_LATENCY_REF);
    end_tc();
  endtask

  //----------------------------------------------------------
  // TC11 — Timeout Persistence
  //----------------------------------------------------------
  task automatic tc11_timeout_persistence();
    bit got_timeout;
    start_tc("TC11_Timeout_Persistence");

    pulse_reset_both();
    configure_wdt(DEFAULT_VAL, THRESHOLD_VAL, KEY_VAL);
    enable_wdt();
    kick_i = KEY_VAL ^ 8'hFF;

    wait_for_timeout(INTERVAL + SYNC_LATENCY_REF + 10, got_timeout);
    check(got_timeout, "Timeout occurs");

    apply_kick_pulse(KEY_VAL, 3);
    wait_ref_cycles(SYNC_LATENCY_REF);
    check(timeout_irq_o, "Timeout remains asserted after valid kick post-timeout");

    drive_invalid_kick(3);
    wait_ref_cycles(SYNC_LATENCY_REF);
    check(timeout_irq_o, "Timeout remains asserted after invalid kick post-timeout");

    wait_ref_cycles(10);
    check(timeout_irq_o, "Timeout still asserted after additional idle cycles");

    disable_wdt();
    wait_ref_cycles(SYNC_LATENCY_REF);
    end_tc();
  endtask

  //----------------------------------------------------------
  // TC12 — Timeout Priority Over Kick
  //----------------------------------------------------------
  task automatic tc12_timeout_priority_over_kick();
    bit got_timeout;
    start_tc("TC12_Timeout_Priority_Over_Kick");

    pulse_reset_both();
    configure_wdt(DEFAULT_VAL, THRESHOLD_VAL, KEY_VAL);
    enable_wdt();

    wait_ref_cycles(INTERVAL + SYNC_LATENCY_REF);
    fork
      begin
        apply_kick_pulse(KEY_VAL, 2);
      end
      begin
        wait_for_timeout(10 + SYNC_LATENCY_REF, got_timeout);
      end
    join

    wait_ref_cycles(SYNC_LATENCY_REF);
    check(timeout_irq_o, "Timeout wins over a simultaneous/near kick");

    apply_kick_pulse(KEY_VAL, 3);
    wait_ref_cycles(SYNC_LATENCY_REF);
    check(timeout_irq_o, "Kick after simultaneous race does not clear timeout");

    disable_wdt();
    wait_ref_cycles(SYNC_LATENCY_REF);
    end_tc();
  endtask

  //----------------------------------------------------------
  // TC13 — Timeout Clear by Disable
  //----------------------------------------------------------
  task automatic tc13_timeout_clear_by_disable();
    bit got_timeout;
    start_tc("TC13_Timeout_Clear_By_Disable");

    pulse_reset_both();
    configure_wdt(DEFAULT_VAL, THRESHOLD_VAL, KEY_VAL);
    enable_wdt();
    kick_i = KEY_VAL ^ 8'hFF;

    wait_for_timeout(INTERVAL + SYNC_LATENCY_REF + 10, got_timeout);
    check(got_timeout, "Timeout occurs prior to disable test");

    disable_wdt();
    wait_ref_cycles(SYNC_LATENCY_REF + 2);
    wait_src_cycles(SYNC_LATENCY_SRC);
    #0.1;
    check(!timeout_irq_o, "Timeout cleared after disable is recognized");

    wait_ref_cycles(10);
    check(!timeout_irq_o, "Timer stops changing / stays cleared while disabled");
    end_tc();
  endtask

  //----------------------------------------------------------
  // TC14 — Restart After Timeout
  //----------------------------------------------------------
  task automatic tc14_restart_after_timeout();
    bit got_timeout;
    start_tc("TC14_Restart_After_Timeout");

    pulse_reset_both();
    configure_wdt(DEFAULT_VAL, THRESHOLD_VAL, KEY_VAL);
    enable_wdt();
    kick_i = KEY_VAL ^ 8'hFF;

    wait_for_timeout(INTERVAL + SYNC_LATENCY_REF + 10, got_timeout);
    check(got_timeout, "Timeout occurs prior to restart test");

    disable_wdt();
    wait_ref_cycles(SYNC_LATENCY_REF + 2);
    wait_src_cycles(SYNC_LATENCY_SRC);
    #0.1;
    check(!timeout_irq_o, "Timeout cleared while disabled");

    enable_wdt();
    wait_ref_cycles(SYNC_LATENCY_REF);
    check(!timeout_irq_o, "No immediate timeout on restart (reloaded from default)");

    wait_for_timeout(INTERVAL + SYNC_LATENCY_REF + 10, got_timeout);
    check(got_timeout, "Restarted timer resumes normal operation and reaches timeout again");

    disable_wdt();
    wait_ref_cycles(SYNC_LATENCY_REF);
    end_tc();
  endtask

  //----------------------------------------------------------
  // TC15 — Enable/Disable Transition
  //----------------------------------------------------------
  task automatic tc15_enable_disable_transition();
    bit got_timeout;
    int cyc;
    start_tc("TC15_Enable_Disable_Transition");

    pulse_reset_both();
    configure_wdt(DEFAULT_VAL, THRESHOLD_VAL, KEY_VAL);

    for (cyc = 0; cyc < 3; cyc++) begin
      disable_wdt();
      wait_ref_cycles(2 + cyc);
      enable_wdt();
      wait_ref_cycles((INTERVAL) / 4);
      check(!timeout_irq_o, $sformatf("No premature timeout shortly after enable cycle %0d", cyc));
      disable_wdt();
      wait_ref_cycles(SYNC_LATENCY_REF);
      check(!timeout_irq_o, $sformatf("Timer stopped/cleared after disable cycle %0d", cyc));
    end

    enable_wdt();
    wait_for_timeout(INTERVAL + SYNC_LATENCY_REF + 10, got_timeout);
    check(got_timeout, "Fresh full interval after multiple enable/disable cycles reaches timeout");

    disable_wdt();
    wait_ref_cycles(SYNC_LATENCY_REF);
    end_tc();
  endtask

  //----------------------------------------------------------
  // TC16 — Source/Reference Clock Ratio
  //----------------------------------------------------------
  task automatic run_one_ratio_case(input time src_period, input time ref_period, input string label);
    bit got_timeout;
    SRC_CLK_PERIOD = src_period;
    REF_CLK_PERIOD = ref_period;

    pulse_reset_both();
    configure_wdt(DEFAULT_VAL, THRESHOLD_VAL, KEY_VAL);
    enable_wdt();

    wait_ref_cycles((INTERVAL) / 2);
    apply_kick_pulse(KEY_VAL, 3);
    wait_ref_cycles(SYNC_LATENCY_REF);
    wait_for_timeout((INTERVAL) / 2, got_timeout);
    check(!got_timeout, {label, ": kick reload works correctly"});

    kick_i = KEY_VAL ^ 8'hFF;
    wait_for_timeout(INTERVAL + SYNC_LATENCY_REF + 20, got_timeout);
    check(got_timeout, {label, ": timeout behavior correct"});

    disable_wdt();
    wait_ref_cycles(SYNC_LATENCY_REF);
  endtask

  task automatic tc16_clock_ratio();
    start_tc("TC16_Clock_Ratio");

    run_one_ratio_case(10ns, 10ns, "Equal frequency");
    run_one_ratio_case(5ns,  20ns, "Src faster than ref");
    run_one_ratio_case(20ns, 5ns,  "Ref faster than src");
    run_one_ratio_case(7ns,  13ns, "Non-integer frequency ratio");

    // Restore default periods for subsequent tests.
    SRC_CLK_PERIOD = 10ns;
    REF_CLK_PERIOD = 10ns;
    end_tc();
  endtask

  //----------------------------------------------------------
  // TC17 — Reset During Normal Operation
  //----------------------------------------------------------
  task automatic tc17_reset_during_normal_operation();
    bit got_timeout;
    start_tc("TC17_Reset_During_Normal_Operation");

    pulse_reset_both();
    configure_wdt(DEFAULT_VAL, THRESHOLD_VAL, KEY_VAL);
    enable_wdt();

    wait_ref_cycles((INTERVAL) / 2);
    pulse_reset_both(4, 4);

    check(!timeout_irq_o, "No stale timeout after reset during normal operation");

  timer_enable_i = 1'b0;
    kick_i = KEY_VAL ^ 8'hFF;
    wait_ref_cycles(5);
    check(!timeout_irq_o, "No stale kick-driven behavior after reset (disabled)");

    enable_wdt();
    wait_for_timeout(INTERVAL + SYNC_LATENCY_REF + 10, got_timeout);
    check(got_timeout, "WDT can be started again after reset and reaches timeout normally");

    disable_wdt();
    wait_ref_cycles(SYNC_LATENCY_REF);
    end_tc();
  endtask

  //----------------------------------------------------------
  // TC18 — Reset Durg Timeout
  //----------------------------------------------------------
  task automatic tc18_reset_during_timeout();
    bit got_timeout;
    start_tc("TC18_Reset_During_Timeout");

    pulse_reset_both();
    configure_wdt(DEFAULT_VAL, THRESHOLD_VAL, KEY_VAL);
    enable_wdt();
    kick_i = KEY_VAL ^ 8'hFF;

    wait_for_timeout(INTERVAL + SYNC_LATENCY_REF + 10, got_timeout);
    check(got_timeout, "Timeout occurs prior to reset-during-timeout test");

    pulse_reset_both(4, 4);
    check(!timeout_irq_o, "Timeout cleared by reset");

    timer_enable_i = 1'b0;
    wait_ref_cycles(2);
    enable_wdt();
    wait_for_timeout(INTERVAL + SYNC_LATENCY_REF + 10, got_timeout);
    check(got_timeout, "Subsequent enable starts a fresh interval and reaches timeout");

    disable_wdt();
    wait_ref_cycles(SYNC_LATENCY_REF);
    end_tc();
  endtask

  //----------------------------------------------------------
  // TC19 — Random Test (broader clock-ratio coverage)
  //----------------------------------------------------------
  // TC16 exercises a hanul of hand-picked src/ref clock-period pairs.
  // TC19 complements that with a randomized sweep across many more
  // src/ref period combinations (integer and non-integer ratios, src
  // faster/slower/equal to ref) crossed with randomized kick-or-not
  // behavior, to shake out corner cases that a fixed set of ratios could
  // miss. The seed is printed so a failing run can be reproduced with
  // +SEED=<n>.
  task automatic tc19_random_test();
    localparam int NUM_ITER = 100;
    int  seed;
    int  src_ns, ref_ns;
    int  half_interval;
    int  kick_choice;
    bit  got_timeout;
    start_tc("TC19_Random_Test");

    if (!$value$plusargs("SEED=%d", seed)) seed = 32'hC0FFEE;
    $display("[%0t] TC19: random seed = %0d (rerun with +SEED=%0d to reproduce)",
              $time, seed, seed);
    void'($urandom(seed));

    for (int iter = 0; iter < NUM_ITER; iter++) begin
      // Randomize src/ref clock periods (in ns) over a wide range so both
      // integer ratios (e.g. 2x, 4x) and non-integer ratios get exercised,
      // in both src-faster-than-ref and ref-faster-than-src directions.
      src_ns = $urandom_range(2, 40);
      ref_ns = $urandom_range(2, 150);
      
      SRC_CLK_PERIOD = time'(src_ns);
      REF_CLK_PERIOD = time'(ref_ns);

      pulse_reset_both();
      configure_wdt(DEFAULT_VAL, THRESHOLD_VAL, KEY_VAL);
      enable_wdt();

      half_interval = (INTERVAL >= 2) ? (INTERVAL / 2) : 1;
      kick_choice   = $urandom_range(0, 1);

      if (kick_choice == 0) begin
        // Kick partway through the interval: must NOT time out early, but
        // must still time out later once kicking stops.
        wait_ref_cycles($urandom_range(1, half_interval));
        apply_kick_pulse(KEY_VAL, $urandom_range(1, 4));
        wait_ref_cycles(SYNC_LATENCY_REF);
        wait_for_timeout(half_interval, got_timeout);
        check(!got_timeout,
              $sformatf("TC19 iter %0d (src=%0dns ref=%0dns): kick reload prevents early timeout",
                         iter, src_ns, ref_ns));

        kick_i = KEY_VAL ^ 8'hFF;
        wait_for_timeout(INTERVAL + SYNC_LATENCY_REF + 20, got_timeout);
        check(got_timeout,
              $sformatf("TC19 iter %0d (src=%0dns ref=%0dns): timeout eventually occurs after reload",
                         iter, src_ns, ref_ns));
      end else begin
        // No kick: timer must run to completion within one full interval.
        kick_i = KEY_VAL ^ 8'hFF;
        wait_for_timeout(INTERVAL + SYNC_LATENCY_REF + 20, got_timeout);
        check(got_timeout,
              $sformatf("TC19 iter %0d (src=%0dns ref=%0dns): timeout occurs with no kick",
                         iter, src_ns, ref_ns));
      end

      disable_wdt();
      wait_ref_cycles(SYNC_LATENCY_REF + 1);
      wait_src_cycles(SYNC_LATENCY_SRC);
      #0.1;
      check(!timeout_irq_o,
            $sformatf("TC19 iter %0d (src=%0dns ref=%0dns): timeout cleared after disable",
                       iter, src_ns, ref_ns));
    end

    // Restore default clock periods for cleanliness (TC19 is currently the
    // last test, but keep this in case tests are appended after it later).
    SRC_CLK_PERIOD = 5ns;
    REF_CLK_PERIOD = 100ns;
    end_tc();
  endtask

  //----------------------------------------------------------
  // Final report
  //----------------------------------------------------------
  task automatic final_report();
    $display("\n=================================================");
    $display(" WDT TESTBENCH SUMMARY");
    $display("=================================================");
    $display(" Tests executed        : %0d", num_tests);
    $display(" Checks performed      : %0d", num_checks);
    $display(" Checks passed         : %0d", num_check_pass);
    $display(" Checks failed         : %0d", num_check_fail);
    $display(" Assertion failures    : %0d", num_assert_fail);
    $display(" Functional failures   : %0d", num_func_fail);
    $display(" Coverage (enable)     : %0.2f%%", cg_enable_i.get_coverage());
    $display(" Coverage (kick)       : %0.2f%%", cg_kick_i.get_coverage());
    if (num_check_fail == 0 && num_assert_fail == 0)
      $display(" OVERALL RESULT        : PASS");
    else
      $display(" OVERALL RESULT        : FAIL");
    $display("=================================================\n");
  endtask

endmodule
