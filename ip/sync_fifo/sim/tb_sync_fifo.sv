// ============================================================================
// Module      : tb_sync_fifo
// Description : Self-checking testbench for sync_fifo.
//               Directed cases (reset, basic push/pop, full, empty, wrap,
//               simultaneous push+pop, flush) + random stress, checked
//               against a queue-based reference (scoreboard) model that
//               mirrors the DUT's exact push_en/pop_en semantics.
// ============================================================================
`timescale 1ns/1ps

module tb_sync_fifo;

  // ---------------------------------------------------------------------
  // Parameters (match DUT instantiation)
  // ---------------------------------------------------------------------
  localparam int unsigned DATA_WIDTH = 32;
  localparam int unsigned DEPTH      = 8;
  localparam int unsigned USG_WIDTH  = $clog2(DEPTH+1);

  localparam int CLK_PERIOD = 10;

  // ---------------------------------------------------------------------
  // DUT signals
  // ---------------------------------------------------------------------
  logic                  clk_i;
  logic                  rst_ni;
  logic                  push_i;
  logic [DATA_WIDTH-1:0] data_i;
  logic                  pop_i;
  logic [DATA_WIDTH-1:0] data_o;
  logic                  flush_i;
  logic                  full_o;
  logic                  empty_o;
  logic [USG_WIDTH-1:0]  usage_o;

  sync_fifo #(
    .DATA_WIDTH (DATA_WIDTH),
    .DEPTH      (DEPTH)
  ) dut (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .push_i  (push_i),
    .data_i  (data_i),
    .pop_i   (pop_i),
    .data_o  (data_o),
    .flush_i (flush_i),
    .full_o  (full_o),
    .empty_o (empty_o),
    .usage_o (usage_o)
  );

  // ---------------------------------------------------------------------
  // Clock
  // ---------------------------------------------------------------------
  initial clk_i = 1'b0;
  always #(CLK_PERIOD/2) clk_i = ~clk_i;

  // ---------------------------------------------------------------------
  // Reference model (scoreboard) — mirrors DUT semantics exactly,
  // including push_en/pop_en both being computed from the OLD
  // (pre-cycle) full/empty state. This intentionally reproduces the
  // DUT's documented corner case: a push is dropped when full even if
  // a simultaneous pop frees a slot in the same cycle.
  // ---------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] ref_q[$];

  function automatic bit ref_full();
    return (ref_q.size() == DEPTH);
  endfunction

  function automatic bit ref_empty();
    return (ref_q.size() == 0);
  endfunction

  // Applies one cycle's worth of push/pop/flush to the reference model.
  // Must be called once per rising edge, with the same push_i/pop_i/
  // data_i/flush_i values that were driven to the DUT for that edge.
  function automatic void ref_apply(
    bit                     p_push,
    logic [DATA_WIDTH-1:0]  p_data,
    bit                     p_pop,
    bit                     p_flush
  );
    bit push_en_ref;
    bit pop_en_ref;
    begin
      if (p_flush) begin
        ref_q.delete();
        return;
      end
      push_en_ref = p_push && !ref_full();
      pop_en_ref  = p_pop  && !ref_empty();
      if (push_en_ref && pop_en_ref) begin
        void'(ref_q.pop_front());
        ref_q.push_back(p_data);
      end else if (push_en_ref) begin
        ref_q.push_back(p_data);
      end else if (pop_en_ref) begin
        void'(ref_q.pop_front());
      end
    end
  endfunction

  // ---------------------------------------------------------------------
  // Bookkeeping
  // ---------------------------------------------------------------------
  int unsigned checks;
  int unsigned errors;

  task automatic report_fail(string msg);
    errors++;
    $display("FAIL @%0t: %s", $time, msg);
  endtask

  // Checks DUT outputs against the reference model's CURRENT (pre-edge)
  // state. Call after driving inputs and letting combinational logic
  // settle, but before the next posedge is latched.
  task automatic check_outputs(string tag);
    bit exp_full;
    bit exp_empty;
    int unsigned exp_usage;
    begin
      exp_full  = ref_full();
      exp_empty = ref_empty();
      exp_usage = ref_q.size();
      checks++;

      if (full_o !== exp_full)
        report_fail($sformatf("[%s] full_o: exp=%0b got=%0b (usage=%0d)",
                               tag, exp_full, full_o, exp_usage));

      if (empty_o !== exp_empty)
        report_fail($sformatf("[%s] empty_o: exp=%0b got=%0b (usage=%0d)",
                               tag, exp_empty, empty_o, exp_usage));

      if (usage_o !== USG_WIDTH'(exp_usage))
        report_fail($sformatf("[%s] usage_o: exp=%0d got=%0d",
                               tag, exp_usage, usage_o));

      // data_o is only meaningful when the reference model is non-empty;
      // when empty the DUT shows whatever is at mem_q[read_ptr_q] (stale).
      if (!exp_empty) begin
        if (data_o !== ref_q[0])
          report_fail($sformatf("[%s] data_o: exp=%0h got=%0h",
                                 tag, ref_q[0], data_o));
      end
    end
  endtask

  // Drives one cycle: set inputs at negedge, check pre-edge state,
  // then update the reference model to match the upcoming posedge.
  task automatic cycle(
    bit                     p_push,
    logic [DATA_WIDTH-1:0]  p_data,
    bit                     p_pop,
    bit                     p_flush,
    string                  tag = "cycle"
  );
    begin
      @(negedge clk_i);
      push_i  = p_push;
      data_i  = p_data;
      pop_i   = p_pop;
      flush_i = p_flush;
      #1; // allow combinational logic to settle
      check_outputs(tag);
      ref_apply(p_push, p_data, p_pop, p_flush);
    end
  endtask

  task automatic idle_cycle(string tag = "idle");
    cycle(1'b0, '0, 1'b0, 1'b0, tag);
  endtask

  // ---------------------------------------------------------------------
  // Reset sequence
  // ---------------------------------------------------------------------
  task automatic do_reset();
    begin
      rst_ni  = 1'b0;
      push_i  = 1'b0;
      pop_i   = 1'b0;
      data_i  = '0;
      flush_i = 1'b0;
      ref_q.delete();

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

  task automatic test_basic_push_pop();
    begin
      $display("-- test_basic_push_pop --");
      cycle(1'b1, 32'hAAAA_0001, 1'b0, 1'b0, "push1");
      idle_cycle("after_push1");
      cycle(1'b0, '0, 1'b1, 1'b0, "pop1");
      idle_cycle("after_pop1");
    end
  endtask

  task automatic test_fill_to_full();
    begin
      $display("-- test_fill_to_full --");
      for (int i = 0; i < DEPTH; i++) begin
        cycle(1'b1, 32'hB000_0000 + i, 1'b0, 1'b0, $sformatf("fill_%0d", i));
      end
      idle_cycle("after_fill");
    end
  endtask

  task automatic test_push_while_full();
    begin
      $display("-- test_push_while_full --");
      // FIFO is expected to be full at this point (called right after
      // test_fill_to_full). Attempted push must be dropped.
      cycle(1'b1, 32'hDEAD_BEEF, 1'b0, 1'b0, "push_while_full");
      idle_cycle("after_push_while_full");
    end
  endtask

  task automatic test_drain_to_empty();
    begin
      $display("-- test_drain_to_empty --");
      for (int i = 0; i < DEPTH; i++) begin
        cycle(1'b0, '0, 1'b1, 1'b0, $sformatf("drain_%0d", i));
      end
      idle_cycle("after_drain");
    end
  endtask

  task automatic test_pop_while_empty();
    begin
      $display("-- test_pop_while_empty --");
      cycle(1'b0, '0, 1'b1, 1'b0, "pop_while_empty");
      idle_cycle("after_pop_while_empty");
    end
  endtask

  task automatic test_simultaneous_at_full();
    begin
      $display("-- test_simultaneous_at_full (push dropped, pop proceeds — documented DUT behavior) --");
      for (int i = 0; i < DEPTH; i++)
        cycle(1'b1, 32'hC000_0000 + i, 1'b0, 1'b0, $sformatf("refill_%0d", i));

      for (int i = 0; i < 3; i++)
        cycle(1'b1, 32'hFFFF_0000 + i, 1'b1, 1'b0, $sformatf("simul_full_%0d", i));

      // drain whatever remains so the FIFO state is clean afterwards
      while (!ref_empty())
        cycle(1'b0, '0, 1'b1, 1'b0, "simul_full_drain");
      idle_cycle("after_simul_full");
    end
  endtask

  task automatic test_simultaneous_at_empty();
    begin
      $display("-- test_simultaneous_at_empty (push succeeds, pop is a no-op) --");
      for (int i = 0; i < 3; i++)
        cycle(1'b1, 32'hE000_0000 + i, 1'b1, 1'b0, $sformatf("simul_empty_%0d", i));

      while (!ref_empty())
        cycle(1'b0, '0, 1'b1, 1'b0, "simul_empty_drain");
      idle_cycle("after_simul_empty");
    end
  endtask

  task automatic test_pointer_wrap();
    begin
      $display("-- test_pointer_wrap --");
      // Alternate push/pop over several multiples of DEPTH to force the
      // write/read pointers to wrap around multiple times.
      for (int i = 0; i < DEPTH * 4; i++) begin
        cycle(1'b1, 32'hD000_0000 + i, (i >= 2), 1'b0, $sformatf("wrap_%0d", i));
      end
      while (!ref_empty())
        cycle(1'b0, '0, 1'b1, 1'b0, "wrap_drain");
      idle_cycle("after_wrap");
    end
  endtask

  task automatic test_flush();
    begin
      $display("-- test_flush --");
      for (int i = 0; i < 3; i++)
        cycle(1'b1, 32'hF000_0000 + i, 1'b0, 1'b0, $sformatf("prefill_%0d", i));

      cycle(1'b0, '0, 1'b0, 1'b1, "flush");
      idle_cycle("after_flush");
    end
  endtask

  task automatic test_random(int unsigned n_cycles);
    bit                    p, q, f;
    logic [DATA_WIDTH-1:0] d;
    begin
      $display("-- test_random (%0d cycles) --", n_cycles);
      for (int unsigned i = 0; i < n_cycles; i++) begin
        p = ($urandom_range(0, 99) < 60); // 60% push attempt rate
        q = ($urandom_range(0, 99) < 60); // 60% pop attempt rate
        f = ($urandom_range(0, 999) < 2); // rare flush
        d = $urandom();
        cycle(p, d, q, f, $sformatf("rand_%0d", i));
      end
      while (!ref_empty())
        cycle(1'b0, '0, 1'b1, 1'b0, "rand_drain");
      idle_cycle("after_random");
    end
  endtask

  // ---------------------------------------------------------------------
  // Main
  // ---------------------------------------------------------------------
  initial begin
    checks = 0;
    errors = 0;

    do_reset();

    test_basic_push_pop();
    test_fill_to_full();
    test_push_while_full();
    test_drain_to_empty();
    test_pop_while_empty();
    test_simultaneous_at_full();
    test_simultaneous_at_empty();
    test_pointer_wrap();
    test_flush();
    test_random(2000);

    if (errors == 0) begin
      $display("TB_SYNC_FIFO: PASS (%0d checks, 0 errors)", checks);
      $finish;
    end else begin
      $display("TB_SYNC_FIFO: FAIL (%0d checks, %0d errors)", checks, errors);
      $fatal(1, "sync_fifo testbench failed");
    end
  end

endmodule
