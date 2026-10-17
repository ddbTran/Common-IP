// ============================================================================
// Module      : tb_rr_arbiter
// Description : Self-checking testbench for rr_arbiter (round-robin, pointer
//               update "method 2" from Weber, "Arbiters: Design Ideas and
//               Coding Styles", SNUG 2001, section 4).
//               Every cycle the DUT grant is compared with a reference model
//               and checked for: one-hot, grant only to a requester, no idle
//               grant, and the starvation bound (wait <= NUM_REQ-1 cycles).
//               Directed cases: reset, no request / pointer hold, single
//               requester, all requesting, skip inactive, wrap-around, the
//               paper's 7/9/10 fairness example, FIFO requesters, random.
// ============================================================================
`timescale 1ns/1ps

module tb_rr_arbiter #(
  parameter int unsigned NUM_REQ = 16  // paper sizes: 4, 16, 64
);

  localparam int CLK_PERIOD = 10;

  // ---------------------------------------------------------------------
  // DUT signals
  // ---------------------------------------------------------------------
  logic               clk_i;
  logic               rst_ni;
  logic [NUM_REQ-1:0] req_i;
  logic [NUM_REQ-1:0] grant_o;

  rr_arbiter #(
    .NUM_REQ (NUM_REQ)
  ) dut (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .req_i   (req_i),
    .grant_o (grant_o)
  );

  // ---------------------------------------------------------------------
  // Clock
  // ---------------------------------------------------------------------
  initial clk_i = 1'b0;
  always #(CLK_PERIOD/2) clk_i = ~clk_i;

  // ---------------------------------------------------------------------
  // Reference model
  // ptr = requester with the highest priority this cycle (paper 4.1).
  // Search starts at ptr and wraps; after a grant to g, ptr = g + 1
  // (method 2, paper 4.4.2); with no request, ptr holds (Listing 12).
  // Reset: ptr = 0, same as Listing 12's mask reset value of all 1s.
  // ---------------------------------------------------------------------
  int unsigned ref_ptr;

  function automatic logic [NUM_REQ-1:0] ref_grant(logic [NUM_REQ-1:0] req);
    int unsigned idx;
    begin
      for (int unsigned k = 0; k < NUM_REQ; k++) begin
        idx = (ref_ptr + k) % NUM_REQ;
        if (req[idx])
          return NUM_REQ'(1) << idx;
      end
      return '0;
    end
  endfunction

  function automatic void ref_apply(logic [NUM_REQ-1:0] grant);
    begin
      for (int unsigned i = 0; i < NUM_REQ; i++)
        if (grant[i])
          ref_ptr = (i + 1) % NUM_REQ;
    end
  endfunction

  // ---------------------------------------------------------------------
  // Bookkeeping
  // ---------------------------------------------------------------------
  int unsigned checks;
  int unsigned errors;
  int unsigned wait_cnt [NUM_REQ];  // cycles a requester has waited
  int unsigned max_wait;            // worst wait seen in the current test

  // Per-test result tracking for the summary table
  bit          verbose;             // print one line per cycle
  string       cur_test;
  int unsigned test_checks0, test_errors0;
  string       summary [$];
  int unsigned n_pass, n_fail, n_skip;

  task automatic report_fail(string msg);
    errors++;
    $display("    >>> FAIL @%0t: %s", $time, msg);
  endtask

  // Binary up to 16 requesters, hex above that so lines stay readable
  function automatic string fmt_vec(logic [NUM_REQ-1:0] v);
    return (NUM_REQ <= 16) ? $sformatf("%b", v) : $sformatf("0x%h", v);
  endfunction

  // Pads a column title to the width of fmt_vec() output
  function automatic string pad_col(string s);
    string r = s;
    while (r.len() < fmt_vec('0).len())
      r = {r, " "};
    return r;
  endfunction

  function automatic string fmt_idx(int idx);
    return (idx < 0) ? "-" : $sformatf("%0d", idx);
  endfunction

  task automatic begin_test(string name, bit per_cycle = 1'b1);
    begin
      cur_test     = name;
      verbose      = per_cycle;
      max_wait     = 0;
      test_checks0 = checks;
      test_errors0 = errors;
      $display("");
      $display("==== %s ====", name);
      if (verbose)
        $display("    %-22s | %s | %s | win | exp | result", "step", pad_col("req"), pad_col("grant"));
    end
  endtask

  task automatic end_test();
    int unsigned n_chk, n_err;
    begin
      n_chk = checks - test_checks0;
      n_err = errors - test_errors0;
      if (n_err == 0) begin
        n_pass++;
        $display("[PASS] %s : %0d checks, max wait %0d cycles (limit %0d)",
                 cur_test, n_chk, max_wait, NUM_REQ - 1);
        summary.push_back($sformatf("  %-24s PASS  (%0d checks)", cur_test, n_chk));
      end else begin
        n_fail++;
        $display("[FAIL] %s : %0d errors in %0d checks", cur_test, n_err, n_chk);
        summary.push_back($sformatf("  %-24s FAIL  (%0d errors in %0d checks)", cur_test, n_err, n_chk));
      end
      verbose = 1'b0;
    end
  endtask

  task automatic skip_test(string reason);
    begin
      n_skip++;
      $display("[SKIP] %s : %s", cur_test, reason);
      summary.push_back($sformatf("  %-24s SKIP  (%s)", cur_test, reason));
      verbose = 1'b0;
    end
  endtask

  function automatic int grant_idx(logic [NUM_REQ-1:0] grant);
    for (int i = 0; i < NUM_REQ; i++)
      if (grant[i])
        return i;
    return -1;
  endfunction

  // Checks the DUT grant for the current req_i before the posedge latches.
  task automatic check_outputs(string tag);
    logic [NUM_REQ-1:0] exp_grant;
    begin
      exp_grant = ref_grant(req_i);
      checks++;

      if (!$onehot0(grant_o))
        report_fail($sformatf("[%s] grant_o not one-hot: %b", tag, grant_o));

      if ((grant_o & ~req_i) != '0)
        report_fail($sformatf("[%s] grant to non-requester: req=%b grant=%b",
                               tag, req_i, grant_o));

      if (req_i != '0 && grant_o == '0)
        report_fail($sformatf("[%s] no grant while requesting: req=%b", tag, req_i));

      if (grant_o !== exp_grant)
        report_fail($sformatf("[%s] grant_o: exp=%b got=%b (req=%b ptr=%0d)",
                               tag, exp_grant, grant_o, req_i, ref_ptr));

      // Starvation bound (paper 4.1): wait is limited by the number of requesters
      for (int unsigned i = 0; i < NUM_REQ; i++) begin
        if (!req_i[i] || grant_o[i])
          wait_cnt[i] = 0;
        else if (++wait_cnt[i] > NUM_REQ - 1)
          report_fail($sformatf("[%s] req %0d starved for %0d cycles", tag, i, wait_cnt[i]));
        if (wait_cnt[i] > max_wait)
          max_wait = wait_cnt[i];
      end
    end
  endtask

  // Drives one cycle: set req_i at negedge, check, then update the model
  // to match the upcoming posedge. exp_idx >= -1 also checks the winner
  // (-1 = nobody); the default -2 means "reference model only".
  task automatic cycle(logic [NUM_REQ-1:0] req, string tag = "cycle", int exp_idx = -2);
    int unsigned errors0;
    string       status;
    begin
      @(negedge clk_i);
      req_i = req;
      #1;
      errors0 = errors;
      check_outputs(tag);
      if (exp_idx >= -1 && grant_idx(grant_o) != exp_idx)
        report_fail($sformatf("[%s] expected requester %s to win, got %s",
                               tag, fmt_idx(exp_idx), fmt_idx(grant_idx(grant_o))));
      if (verbose) begin
        status = "OK";
        if (errors != errors0)
          status = "MISMATCH";
        $display("    %-22s | %s | %s | %3s | %3s | %s", tag, fmt_vec(req_i), fmt_vec(grant_o),
                 fmt_idx(grant_idx(grant_o)),
                 fmt_idx(exp_idx >= -1 ? exp_idx : grant_idx(ref_grant(req_i))), status);
      end
      ref_apply(grant_o);
    end
  endtask

  // Same as cycle(), plus checks that requester exp_idx wins.
  task automatic expect_grant(logic [NUM_REQ-1:0] req, int exp_idx, string tag);
    cycle(req, tag, exp_idx);
  endtask

  // ---------------------------------------------------------------------
  // Reset sequence
  // ---------------------------------------------------------------------
  task automatic do_reset();
    begin
      rst_ni  = 1'b0;
      req_i   = '0;
      ref_ptr = 0;
      foreach (wait_cnt[i]) wait_cnt[i] = 0;

      repeat (3) @(negedge clk_i);
      rst_ni = 1'b1;
      @(negedge clk_i);
      #1;
      check_outputs("post_reset");
    end
  endtask

  // ---------------------------------------------------------------------
  // Test sequences
  // ---------------------------------------------------------------------

  // Reset value: every requester allowed, so the lowest active one wins.
  // Asserting reset mid-run must also return the pointer to its reset value.
  task automatic test_reset();
    begin
      begin_test("test_reset");
      if (NUM_REQ < 4) begin
        skip_test("needs NUM_REQ >= 4");
        return;
      end
      expect_grant('1, 0, "reset_all_req");
      expect_grant({NUM_REQ{1'b1}} << 3, 3, "reset_lowest_active");
      do_reset();
      expect_grant({NUM_REQ{1'b1}} << 2, 2, "rereset_lowest_active");
      do_reset();
      end_test();
    end
  endtask

  // No request: no grant, and the pointer must hold (Listing 12).
  task automatic test_no_request();
    begin
      begin_test("test_no_request");
      if (NUM_REQ < 4) begin
        skip_test("needs NUM_REQ >= 4");
        return;
      end
      expect_grant(NUM_REQ'(1) << 1, 1, "noreq_set_ptr");
      repeat (5) cycle('0, "noreq_idle");
      // Pointer still at 2, so 2 wins over 0 and 1
      expect_grant('1, 2, "noreq_ptr_held");
      end_test();
    end
  endtask

  // A single active requester gets back-to-back grants (paper 4.1:
  // "if not, the next active requester gets the grant").
  task automatic test_single_requester();
    begin
      begin_test("test_single_requester");
      for (int unsigned i = 0; i < NUM_REQ; i += (NUM_REQ > 4 ? NUM_REQ / 4 : 1))
        repeat (3) expect_grant(NUM_REQ'(1) << i, i, $sformatf("single_%0d", i));
      end_test();
    end
  endtask

  // All requesting: strict rotation, each requester once per NUM_REQ cycles.
  task automatic test_all_requesting();
    int start;
    begin
      begin_test("test_all_requesting");
      cycle('1, "all_sync");
      start = grant_idx(grant_o);
      for (int unsigned k = 1; k <= 2 * NUM_REQ; k++)
        expect_grant('1, (start + k) % NUM_REQ, $sformatf("all_%0d", k));
      end_test();
    end
  endtask

  // Inactive requesters are skipped with no wasted cycle
  // (generalised version of req = 1011 -> 0, 1, 3, 0, ...).
  task automatic test_skip_inactive();
    logic [NUM_REQ-1:0] req;
    begin
      begin_test("test_skip_inactive");
      if (NUM_REQ < 4) begin
        skip_test("needs NUM_REQ >= 4");
        return;
      end
      do_reset();
      req = '0;
      req[0] = 1'b1;
      req[1] = 1'b1;
      req[NUM_REQ-1] = 1'b1;
      repeat (2) begin
        expect_grant(req, 0, "skip_0");
        expect_grant(req, 1, "skip_1");
        expect_grant(req, NUM_REQ - 1, "skip_top");
      end
      end_test();
    end
  endtask

  // Top requester wins, then the search wraps back to the bottom.
  task automatic test_wrap_around();
    logic [NUM_REQ-1:0] req;
    begin
      begin_test("test_wrap_around");
      expect_grant(NUM_REQ'(1) << (NUM_REQ - 2), NUM_REQ - 2, "wrap_set_ptr");
      req = '0;
      req[NUM_REQ-1] = 1'b1;
      req[0] = 1'b1;
      expect_grant(req, NUM_REQ - 1, "wrap_top");
      expect_grant(req, 0, "wrap_bottom");
      expect_grant(req, NUM_REQ - 1, "wrap_top_again");
      end_test();
    end
  endtask

  // Paper 4.4.2 example: pointer at 2, requesters 7, 9, 10 active.
  // Method 1 would give 7 six grants in a row; method 2 rotates 7, 9, 10.
  // Then 8 becomes active right after 7 wins: method 2 grants 8 next.
  task automatic test_paper_example();
    logic [NUM_REQ-1:0] req;
    begin
      begin_test("test_paper_example");
      if (NUM_REQ < 11) begin
        skip_test("needs NUM_REQ >= 11");
        return;
      end
      expect_grant(NUM_REQ'(1) << 1, 1, "paper_ptr_to_2");
      // Shifts instead of req[7] etc. so small NUM_REQ still elaborates cleanly
      req = (NUM_REQ'(1) << 7) | (NUM_REQ'(1) << 9) | (NUM_REQ'(1) << 10);
      expect_grant(req, 7, "paper_7");
      expect_grant(req, 9, "paper_9");
      expect_grant(req, 10, "paper_10");
      expect_grant(req, 7, "paper_7_again");
      req |= NUM_REQ'(1) << 8;
      expect_grant(req, 8, "paper_8_immediate");
      expect_grant(req, 9, "paper_9_after_8");
      end_test();
    end
  endtask

  // FIFO requesters (paper 2.1.2 / 2.2.1): req = ~fifo_empty, grant pops.
  // Every pushed entry must be granted exactly once and never more.
  task automatic test_fifo_requesters(int unsigned n_cycles);
    int unsigned fifo_cnt [NUM_REQ];
    int unsigned pushes, grants;
    logic [NUM_REQ-1:0] req;
    begin
      begin_test("test_fifo_requesters", 1'b0);
      pushes = 0;
      grants = 0;
      foreach (fifo_cnt[i]) fifo_cnt[i] = 0;
      // Push phase, then drain until every FIFO is empty (bounded)
      for (int unsigned c = 0; c < n_cycles || (pushes != grants && c < 4 * n_cycles); c++) begin
        for (int unsigned i = 0; i < NUM_REQ; i++) begin
          // ~90% total load: busy, but the arbiter (1 grant/cycle) keeps up
          if (c < n_cycles && $urandom_range(0, 999) < 900 / NUM_REQ) begin
            fifo_cnt[i]++;
            pushes++;
          end
          req[i] = (fifo_cnt[i] != 0);
        end
        cycle(req, $sformatf("fifo_%0d", c));
        for (int unsigned i = 0; i < NUM_REQ; i++)
          if (grant_o[i]) begin
            fifo_cnt[i]--;  // a grant to an empty FIFO is already caught by check_outputs
            grants++;
          end
      end
      $display("    pushed %0d entries, granted %0d", pushes, grants);
      if (grants != pushes)
        report_fail($sformatf("[fifo] pushes=%0d grants=%0d", pushes, grants));
      end_test();
    end
  endtask

  // Random requests, checked against the reference model every cycle.
  task automatic test_random(int unsigned n_cycles);
    logic [NUM_REQ-1:0] req;
    int unsigned        grant_cnt [NUM_REQ];
    begin
      begin_test("test_random", 1'b0);
      foreach (grant_cnt[i]) grant_cnt[i] = 0;
      for (int unsigned c = 0; c < n_cycles; c++) begin
        for (int unsigned i = 0; i < NUM_REQ; i++)
          req[i] = ($urandom_range(0, 99) < (c % 3 == 0 ? 20 : 70));
        cycle(req, $sformatf("rand_%0d", c));
        if (grant_idx(grant_o) >= 0)
          grant_cnt[grant_idx(grant_o)]++;
      end
      $display("    %0d cycles, grants per requester (should be roughly equal):", n_cycles);
      for (int unsigned i = 0; i < NUM_REQ; i++)
        $display("      req %2d : %0d", i, grant_cnt[i]);
      end_test();
    end
  endtask

  // ---------------------------------------------------------------------
  // Main
  // ---------------------------------------------------------------------
  initial begin
    checks  = 0;
    errors  = 0;
    verbose = 1'b0;
    n_pass  = 0;
    n_fail  = 0;
    n_skip  = 0;

    do_reset();

    test_reset();
    test_no_request();
    test_single_requester();
    test_all_requesting();
    test_skip_inactive();
    test_wrap_around();
    test_paper_example();
    test_fifo_requesters(1000);
    test_random(3000);

    $display("");
    $display("================= SUMMARY (NUM_REQ=%0d) =================", NUM_REQ);
    foreach (summary[i])
      $display("%s", summary[i]);
    $display("  %0d passed, %0d failed, %0d skipped", n_pass, n_fail, n_skip);
    $display("=========================================================");

    if (errors == 0) begin
      $display("TB_RR_ARBITER: PASS (NUM_REQ=%0d, %0d checks, 0 errors)", NUM_REQ, checks);
      $finish;
    end else begin
      $display("TB_RR_ARBITER: FAIL (NUM_REQ=%0d, %0d checks, %0d errors)", NUM_REQ, checks, errors);
      $fatal(1, "rr_arbiter testbench failed");
    end
  end

  initial begin
    $dumpfile("rr_arbiter.fst");
    $dumpvars(0, tb_rr_arbiter);
  end

endmodule
