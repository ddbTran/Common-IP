`timescale 1ns/1ps

module tb_async_apb_bridge;

  localparam int ADDR_WIDTH = 32;
  localparam int DATA_WIDTH = 32;
  localparam int STRB_WIDTH = DATA_WIDTH/8;

  // -----------------------------------------------------------------------
  // Clock / reset generation.
  // Periods/phases are plain variables that the test sequence rewrites
  // between configurations (see run_config). Each clock process parks
  // (clk low, *_parked=1) while clk_en=0 and re-applies its phase offset
  // every time clk_en rises, so both clocks restart from a common t0.
  // -----------------------------------------------------------------------
  logic clk_m_i, clk_s_i;
  logic rst_m_ni, rst_s_ni;

  real clk_m_period_ns = 10.0;
  real clk_s_period_ns = 10.0;
  real clk_m_phase_ns  = 0.0;
  real clk_s_phase_ns  = 0.0;

  bit  clk_en       = 1'b0;
  bit  clk_m_parked = 1'b1;
  bit  clk_s_parked = 1'b1;

  initial begin
    clk_m_i = 1'b0;
    forever begin
      wait (clk_en);
      clk_m_parked = 1'b0;
      #(clk_m_phase_ns);
      while (clk_en) #(clk_m_period_ns/2.0) clk_m_i = ~clk_m_i;
      clk_m_i = 1'b0;
      clk_m_parked = 1'b1;
    end
  end

  initial begin
    clk_s_i = 1'b0;
    forever begin
      wait (clk_en);
      clk_s_parked = 1'b0;
      #(clk_s_phase_ns);
      while (clk_en) #(clk_s_period_ns/2.0) clk_s_i = ~clk_s_i;
      clk_s_i = 1'b0;
      clk_s_parked = 1'b1;
    end
  end

  task automatic tick_m();
    @(posedge clk_m_i);
    #1;
  endtask

  task automatic tick_s();
    @(posedge clk_s_i);
    #1;
  endtask

  // -----------------------------------------------------------------------
  // DUT interconnect
  // -----------------------------------------------------------------------
  logic [ADDR_WIDTH-1:0] s_paddr_i;
  logic [2:0]            s_pprot_i;
  logic                  s_psel_i;
  logic                  s_penable_i;
  logic                  s_pwrite_i;
  logic [DATA_WIDTH-1:0] s_pwdata_i;
  logic [STRB_WIDTH-1:0] s_pstrb_i;
  logic                  s_pready_o;
  logic [DATA_WIDTH-1:0] s_prdata_o;
  logic                  s_pslverr_o;

  logic [ADDR_WIDTH-1:0] m_paddr_o;
  logic [2:0]            m_pprot_o;
  logic                  m_psel_o;
  logic                  m_penable_o;
  logic                  m_pwrite_o;
  logic [DATA_WIDTH-1:0] m_pwdata_o;
  logic [STRB_WIDTH-1:0] m_pstrb_o;
  logic                  m_pready_i;
  logic [DATA_WIDTH-1:0] m_prdata_i;
  logic                  m_pslverr_i;

  async_apb_bridge #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH)
  ) dut (
    .clk_m_i     (clk_m_i),
    .rst_m_ni    (rst_m_ni),
    .clk_s_i     (clk_s_i),
    .rst_s_ni    (rst_s_ni),

    .m_paddr_o   (m_paddr_o),
    .m_pprot_o   (m_pprot_o),
    .m_psel_o    (m_psel_o),
    .m_penable_o (m_penable_o),
    .m_pwrite_o  (m_pwrite_o),
    .m_pwdata_o  (m_pwdata_o),
    .m_pstrb_o   (m_pstrb_o),
    .m_pready_i  (m_pready_i),
    .m_prdata_i  (m_prdata_i),
    .m_pslverr_i (m_pslverr_i),

    .s_paddr_i   (s_paddr_i),
    .s_pprot_i   (s_pprot_i),
    .s_psel_i    (s_psel_i),
    .s_penable_i (s_penable_i),
    .s_pwrite_i  (s_pwrite_i),
    .s_pwdata_i  (s_pwdata_i),
    .s_pstrb_i   (s_pstrb_i),
    .s_pready_o  (s_pready_o),
    .s_prdata_o  (s_prdata_o),
    .s_pslverr_o (s_pslverr_o)
  );

  // -----------------------------------------------------------------------
  // Bookkeeping
  // -----------------------------------------------------------------------
  int error_count = 0;
  int test_count  = 0;

  task automatic check(input bit cond, input string msg);
    if (!cond) begin
      error_count++;
      $error("%s", msg);
    end
  endtask

  // Per-testcase reporting. Directed testcases are always printed;
  // random transactions (TC80) are printed only with +VERBOSE.
  bit print_txn = 1'b1;
  bit verbose   = 1'b0;

  task automatic tc_report(input string name, input int err_before);
    if (error_count == err_before) $display("    [PASS] %s", name);
    else                           $display("    [FAIL] %s (%0d errors)", name, error_count - err_before);
  endtask

  // -----------------------------------------------------------------------
  // Reset control
  // -----------------------------------------------------------------------
  task automatic drive_idle_inputs();
    s_paddr_i   = '0;
    s_pprot_i   = '0;
    s_psel_i    = 1'b0;
    s_penable_i = 1'b0;
    s_pwrite_i  = 1'b0;
    s_pwdata_i  = '0;
    s_pstrb_i   = '0;
    m_pready_i  = 1'b0;
    m_prdata_i  = '0;
    m_pslverr_i = 1'b0;
  endtask

  // rst_m_ni/rst_s_ni assert and release together, as guaranteed by spec.
  task automatic apply_reset();
    real settle;
    settle = 5.0 * ((clk_m_period_ns > clk_s_period_ns) ? clk_m_period_ns : clk_s_period_ns);
    rst_m_ni = 1'b0;
    rst_s_ni = 1'b0;
    drive_idle_inputs();
    #(settle);
    rst_m_ni = 1'b1;
    rst_s_ni = 1'b1;
    #(settle);
  endtask

  // -----------------------------------------------------------------------
  // Downstream (APB master interface of the DUT) responder: models the
  // downstream APB slave. Runs continuously in the background; each
  // transaction to respond to is configured by pushing a cfg into resp_mbx.
  // -----------------------------------------------------------------------
  typedef struct {
    bit [ADDR_WIDTH-1:0] exp_addr;
    bit [2:0]            exp_prot;
    bit                  exp_write;
    bit [DATA_WIDTH-1:0] exp_wdata;
    bit [STRB_WIDTH-1:0] exp_strb;
    bit [DATA_WIDTH-1:0] rdata;
    bit                  err;
    int                  wait_cycles;
    string               label;
  } xfer_cfg_t;

  mailbox #(xfer_cfg_t) resp_mbx = new();

  logic m_penable_prev = 1'b0;

  task automatic responder_body();
    xfer_cfg_t cfg;
    if (m_psel_o && m_penable_o && !m_penable_prev) begin
      resp_mbx.get(cfg);
      check(m_paddr_o  === cfg.exp_addr,  $sformatf("[%s] m_paddr_o mismatch: exp=%0h got=%0h", cfg.label, cfg.exp_addr, m_paddr_o));
      check(m_pprot_o  === cfg.exp_prot,  $sformatf("[%s] m_pprot_o mismatch: exp=%0h got=%0h", cfg.label, cfg.exp_prot, m_pprot_o));
      check(m_pwrite_o === cfg.exp_write, $sformatf("[%s] m_pwrite_o mismatch: exp=%0b got=%0b", cfg.label, cfg.exp_write, m_pwrite_o));
      if (cfg.exp_write) begin
        check(m_pwdata_o === cfg.exp_wdata, $sformatf("[%s] m_pwdata_o mismatch: exp=%0h got=%0h", cfg.label, cfg.exp_wdata, m_pwdata_o));
        check(m_pstrb_o  === cfg.exp_strb,  $sformatf("[%s] m_pstrb_o mismatch: exp=%0h got=%0h", cfg.label, cfg.exp_strb, m_pstrb_o));
      end
      // Reset-aware wait: if reset hits mid-wait, abandon this response
      // entirely instead of holding the whole responder hostage for the
      // remainder of cfg.wait_cycles (which could stall every later test).
      for (int i = 0; i < cfg.wait_cycles; i++) begin
        tick_m();
        if (!rst_m_ni) begin
          m_pready_i = 1'b0; m_prdata_i = '0; m_pslverr_i = 1'b0;
          return;
        end
      end
      if (!rst_m_ni) return;
      m_pready_i  = 1'b1;
      m_prdata_i  = cfg.rdata;
      m_pslverr_i = cfg.err;
      tick_m();
      m_pready_i  = 1'b0;
      m_prdata_i  = '0;
      m_pslverr_i = 1'b0;
    end
    m_penable_prev = m_penable_o;
  endtask

  // Discard a leftover mailbox entry that a reset aborted before the
  // responder ever picked it up (kept the request/response queues balanced
  // for the next, unrelated transaction).
  /* verilator lint_off UNUSEDSIGNAL */
  task automatic drain_stale_cfg();
    xfer_cfg_t dummy;
    if (resp_mbx.num() > 0) resp_mbx.get(dummy);
  endtask
  /* verilator lint_on UNUSEDSIGNAL */

  initial begin
    forever begin
      tick_m();
      responder_body();
    end
  end

  // -----------------------------------------------------------------------
  // Upstream (APB slave interface of the DUT) driver: models the upstream
  // APB master issuing one transaction at a time.
  // -----------------------------------------------------------------------
  task automatic do_transaction(
    input  bit                  is_write,
    input  bit [ADDR_WIDTH-1:0] addr,
    input  bit [2:0]            prot,
    input  bit [DATA_WIDTH-1:0] wdata,
    input  bit [STRB_WIDTH-1:0] strb,
    input  int                  wait_cycles,
    input  bit                  force_err,
    input  bit [DATA_WIDTH-1:0] rdata_to_return,
    input  string               label
  );
    xfer_cfg_t cfg;
    int        err_before;
    err_before = error_count;
    cfg.exp_addr    = addr;
    cfg.exp_prot    = prot;
    cfg.exp_write   = is_write;
    cfg.exp_wdata   = wdata;
    cfg.exp_strb    = strb;
    cfg.rdata       = rdata_to_return;
    cfg.err         = force_err;
    cfg.wait_cycles = wait_cycles;
    cfg.label       = label;
    resp_mbx.put(cfg);

    test_count++;

    // SETUP phase
    tick_s();
    s_paddr_i   = addr;
    s_pprot_i   = prot;
    s_pwrite_i  = is_write;
    s_pwdata_i  = wdata;
    s_pstrb_i   = strb;
    s_psel_i    = 1'b1;
    s_penable_i = 1'b0;

    // ACCESS phase
    tick_s();
    s_penable_i = 1'b1;

    do begin
      tick_s();
    end while (!s_pready_o);

    if (!is_write) begin
      check(s_prdata_o === rdata_to_return, $sformatf("[%s] s_prdata_o mismatch: exp=%0h got=%0h", label, rdata_to_return, s_prdata_o));
    end
    check(s_pslverr_o === force_err, $sformatf("[%s] s_pslverr_o mismatch: exp=%0b got=%0b", label, force_err, s_pslverr_o));

    record_coverage(is_write, force_err, strb, prot, wait_cycles);

    if (print_txn) begin
      if (error_count == err_before)
        $display("    [PASS] %-26s %s addr=%08h wait=%0d err=%0b", label, is_write ? "WR" : "RD", addr, wait_cycles, force_err);
      else
        $display("    [FAIL] %-26s %s addr=%08h wait=%0d err=%0b (%0d errors)", label, is_write ? "WR" : "RD", addr, wait_cycles, force_err, error_count - err_before);
    end

    tick_s();
    s_psel_i    = 1'b0;
    s_penable_i = 1'b0;
  endtask

  // -----------------------------------------------------------------------
  // Manual functional coverage tracking (bin hit tables), reported at the
  // end of the run. Kept as plain arrays rather than a native covergroup to
  // keep the whole testbench dependency-free and Verilator-warning-clean.
  // -----------------------------------------------------------------------
  bit cov_op        [2];      // 0=write,1=read
  bit cov_err       [2];      // 0,1
  bit cov_strb      [16];     // all 4 strobe bit combinations
  bit cov_pprot     [8];      // all PPROT[2:0] combinations
  bit cov_wait_bin  [3];      // 0=immediate,1=short(1-3),2=long(>3)

  task automatic record_coverage(
    input bit is_write, input bit err, input bit [STRB_WIDTH-1:0] strb,
    input bit [2:0] prot, input int wait_cycles
  );
    logic [1:0] wbin;
    cov_op[is_write ? 0 : 1]  = 1'b1;
    cov_err[err]              = 1'b1;
    cov_strb[strb]            = 1'b1;
    cov_pprot[prot]           = 1'b1;
    if (wait_cycles == 0)      wbin = 0;
    else if (wait_cycles <= 3) wbin = 1;
    else                       wbin = 2;
    cov_wait_bin[wbin] = 1'b1;
  endtask

  // -----------------------------------------------------------------------
  // Section 1 - Reset tests (TC01-TC05)
  // -----------------------------------------------------------------------
  task automatic check_bridge_idle(input string label);
    check(!m_psel_o && !m_penable_o, $sformatf("[%s] master outputs not idle after reset", label));
    check(!s_pready_o, $sformatf("[%s] s_pready_o asserted spuriously after reset", label));
  endtask

  task automatic t01_reset_idle();
    apply_reset();
    check_bridge_idle("TC01");
  endtask

  task automatic t02_reset_during_request();
    xfer_cfg_t cfg;
    cfg.exp_addr = 32'h0000_00A0; cfg.exp_prot = 3'b000; cfg.exp_write = 1'b1;
    cfg.exp_wdata = 32'hDEAD_0002; cfg.exp_strb = 4'hF; cfg.rdata = '0; cfg.err = 1'b0;
    cfg.wait_cycles = 100; cfg.label = "TC02(discarded)";
    resp_mbx.put(cfg);
    tick_s();
    s_paddr_i = 32'h0000_00A0; s_pprot_i = 3'b000; s_pwrite_i = 1'b1;
    s_pwdata_i = 32'hDEAD_0002; s_pstrb_i = 4'hF; s_psel_i = 1'b1; s_penable_i = 1'b0;
    tick_s();
    s_penable_i = 1'b1;
    tick_s(); // one ACCESS cycle elapsed; request may or may not have crossed yet
    apply_reset();
    check_bridge_idle("TC02");
    drain_stale_cfg();
    s_psel_i = 1'b0; s_penable_i = 1'b0;
    do_transaction(1'b1, 32'h1000_0002, 3'b000, 32'hCAFE_0002, 4'hF, 1, 1'b0, '0, "TC02-replay-check");
  endtask

  task automatic t03_reset_during_access();
    xfer_cfg_t cfg;
    cfg.exp_addr = 32'h0000_00B0; cfg.exp_prot = 3'b000; cfg.exp_write = 1'b0;
    cfg.exp_wdata = '0; cfg.exp_strb = 4'h0; cfg.rdata = 32'hBEEF_0003; cfg.err = 1'b0;
    cfg.wait_cycles = 1000; cfg.label = "TC03(discarded)";
    resp_mbx.put(cfg);
    tick_s();
    s_paddr_i = 32'h0000_00B0; s_pprot_i = 3'b000; s_pwrite_i = 1'b0;
    s_pwdata_i = '0; s_pstrb_i = 4'h0; s_psel_i = 1'b1; s_penable_i = 1'b0;
    tick_s();
    s_penable_i = 1'b1;
    // Wait until the transaction has definitely crossed into ACCESS downstream.
    do begin
      tick_m();
    end while (!(m_psel_o && m_penable_o));
    apply_reset();
    check_bridge_idle("TC03");
    drain_stale_cfg();
    s_psel_i = 1'b0; s_penable_i = 1'b0;
    do_transaction(1'b0, 32'h1000_0003, 3'b000, '0, 4'h0, 1, 1'b0, 32'hCAFE_0003, "TC03-replay-check");
  endtask

  task automatic t04_reset_during_ack();
    bit m_psel_prev;
    xfer_cfg_t cfg;
    cfg.exp_addr = 32'h0000_00C0; cfg.exp_prot = 3'b000; cfg.exp_write = 1'b1;
    cfg.exp_wdata = 32'hFACE_0004; cfg.exp_strb = 4'hF; cfg.rdata = '0; cfg.err = 1'b0;
    cfg.wait_cycles = 0; cfg.label = "TC04(discarded)";
    resp_mbx.put(cfg);
    tick_s();
    s_paddr_i = 32'h0000_00C0; s_pprot_i = 3'b000; s_pwrite_i = 1'b1;
    s_pwdata_i = 32'hFACE_0004; s_pstrb_i = 4'hF; s_psel_i = 1'b1; s_penable_i = 1'b0;
    tick_s();
    s_penable_i = 1'b1;
    m_psel_prev = m_psel_o;
    forever begin
      tick_m();
      if (m_psel_prev && !m_psel_o) break;
      m_psel_prev = m_psel_o;
    end
    // ACCESS just completed downstream; the response is now in flight back
    // to the slave domain (ack phase) but has not reached s_pready_o yet.
    apply_reset();
    check_bridge_idle("TC04");
    drain_stale_cfg();
    s_psel_i = 1'b0; s_penable_i = 1'b0;
    do_transaction(1'b1, 32'h1000_0004, 3'b000, 32'hCAFE_0004, 4'hF, 1, 1'b0, '0, "TC04-replay-check");
  endtask

  // -----------------------------------------------------------------------
  // Section 2 - Basic APB transaction (TC10-TC13)
  // -----------------------------------------------------------------------
  task automatic t10_13_basic();
    do_transaction(1'b1, 32'h0000_1000, 3'b010, 32'hA5A5_5A5A, 4'hF, 1, 1'b0, '0,          "TC10-write");
    do_transaction(1'b0, 32'h0000_1004, 3'b011, '0,          4'h0, 1, 1'b0, 32'h1234_5678, "TC11-read");
    do_transaction(1'b1, 32'h0000_1008, 3'b000, 32'h0000_0001, 4'h1, 1, 1'b1, '0,          "TC12-write-error");
    do_transaction(1'b0, 32'h0000_100C, 3'b000, '0,          4'h0, 1, 1'b1, 32'hFFFF_FFFF, "TC13-read-error");
  endtask

  // -----------------------------------------------------------------------
  // Section 3 - APB wait-state timing (TC22, TC24)
  // -----------------------------------------------------------------------
  task automatic t2x_wait_states();
    do_transaction(1'b1, 32'h0000_2000, 3'b000, 32'h1111_1111, 4'hF, 0, 1'b0, '0, "TC24-pready-immediate");
    do_transaction(1'b0, 32'h0000_2004, 3'b000, '0,          4'h0, 5, 1'b0, 32'h2222_2222, "TC22-access-wait-5");
    do_transaction(1'b1, 32'h0000_2008, 3'b000, 32'h3333_3333, 4'hF, 12, 1'b0, '0, "TC22-access-wait-12");
  endtask

  // -----------------------------------------------------------------------
  // Section 4 - Data integrity: address/data patterns, PSTRB, PPROT (TC30-TC35)
  // -----------------------------------------------------------------------
  task automatic t3x_data_integrity();
    bit [31:0] addr_patterns [4] = '{32'h0000_0000, 32'hFFFF_FFFC, 32'hAAAA_AAA8, 32'h5555_5554};
    bit [31:0] data_patterns [4] = '{32'h0000_0000, 32'hFFFF_FFFF, 32'hAAAA_AAAA, 32'h5555_5555};

    foreach (addr_patterns[i]) begin
      do_transaction(1'b1, addr_patterns[i], 3'b000, data_patterns[i], 4'hF, 1, 1'b0, '0,
                      $sformatf("TC30-31-write-pattern-%0d", i));
      do_transaction(1'b0, addr_patterns[i], 3'b000, '0, 4'h0, 1, 1'b0, data_patterns[i],
                      $sformatf("TC34-read-pattern-%0d", i));
    end

    for (int strb = 0; strb < 16; strb++) begin
      do_transaction(1'b1, 32'h0000_3000 + strb*4, 3'b000, 32'hC0DE_0000 | strb, strb[3:0], 1, 1'b0, '0,
                      $sformatf("TC32-pstrb-%0d", strb));
    end

    for (int prot = 0; prot < 8; prot++) begin
      do_transaction(1'b0, 32'h0000_4000 + prot*4, prot[2:0], '0, 4'h0, 1, 1'b0, 32'hD00D_0000 | prot,
                      $sformatf("TC33-pprot-%0d", prot));
    end
  endtask

  // -----------------------------------------------------------------------
  // Section 7 - Back-to-back transactions (TC60-TC63)
  // -----------------------------------------------------------------------
  task automatic t6x_back_to_back();
    do_transaction(1'b1, 32'h0000_5000, 3'b000, 32'h0000_0001, 4'hF, 0, 1'b0, '0, "TC60-write-1");
    do_transaction(1'b1, 32'h0000_5004, 3'b000, 32'h0000_0002, 4'hF, 0, 1'b0, '0, "TC60-write-2");

    do_transaction(1'b0, 32'h0000_5010, 3'b000, '0, 4'h0, 0, 1'b0, 32'hAAAA_0001, "TC61-read-1");
    do_transaction(1'b0, 32'h0000_5014, 3'b000, '0, 4'h0, 0, 1'b0, 32'hAAAA_0002, "TC61-read-2");

    do_transaction(1'b1, 32'h0000_5020, 3'b000, 32'h0000_0003, 4'hF, 0, 1'b0, '0, "TC62-write");
    do_transaction(1'b0, 32'h0000_5024, 3'b000, '0, 4'h0, 0, 1'b0, 32'hAAAA_0003, "TC62-read");

    do_transaction(1'b0, 32'h0000_5030, 3'b000, '0, 4'h0, 0, 1'b0, 32'hAAAA_0004, "TC63-read");
    do_transaction(1'b1, 32'h0000_5034, 3'b000, 32'h0000_0004, 4'hF, 0, 1'b0, '0, "TC63-write");
  endtask

  // -----------------------------------------------------------------------
  // Section 9 - Random test (TC80)
  // -----------------------------------------------------------------------
  task automatic t80_random(input int num_iters);
    bit                  is_write;
    bit [ADDR_WIDTH-1:0] addr;
    bit [2:0]            prot;
    bit [DATA_WIDTH-1:0] wdata;
    bit [STRB_WIDTH-1:0] strb;
    bit [DATA_WIDTH-1:0] rdata;
    bit                  err;
    int                  wait_cycles;

    print_txn = verbose;
    for (int i = 0; i < num_iters; i++) begin
      is_write    = bit'($urandom_range(0, 1));
      addr        = $urandom() & 32'hFFFF_FFFC;
      prot        = 3'($urandom_range(0, 7));
      wdata       = $urandom();
      strb        = 4'($urandom_range(0, 15));
      rdata       = $urandom();
      err         = $urandom_range(0, 3) == 0; // ~25% error rate
      wait_cycles = $urandom_range(0, 8);
      do_transaction(is_write, addr, prot, wdata, strb, wait_cycles, err, rdata,
                      $sformatf("TC80-random-%0d", i));
    end
    print_txn = 1'b1;
  endtask

  function automatic void report_coverage();
    int hit, total;
    hit = 0; total = 0;
    foreach (cov_op[i])       begin total++; if (cov_op[i])       hit++; end
    foreach (cov_err[i])      begin total++; if (cov_err[i])      hit++; end
    foreach (cov_strb[i])     begin total++; if (cov_strb[i])     hit++; end
    foreach (cov_pprot[i])    begin total++; if (cov_pprot[i])    hit++; end
    foreach (cov_wait_bin[i]) begin total++; if (cov_wait_bin[i]) hit++; end
    $display("COVERAGE: %0d/%0d bins hit (%0.1f%%)", hit, total, 100.0*hit/total);
  endfunction

  // -----------------------------------------------------------------------
  // Clock-configuration regression table (replaces run_regression.sh)
  // -----------------------------------------------------------------------
  localparam int NUM_CFGS = 12;

  // {name, clk_m period, clk_s period, clk_m phase, clk_s phase}  (ns)
  function automatic string cfg_name(input int i);
    case (i)
      0:  return "TC40 same-freq";
      1:  return "TC41 slave-faster";
      2:  return "TC42 master-faster";
      3:  return "TC43 large-ratio-m";
      4:  return "TC43 large-ratio-s";
      5:  return "TC44 non-integer";
      6:  return "TC44 non-integer-2";
      7:  return "TC45 phase-2-3";
      8:  return "TC45 phase-7-1";
      9:  return "TC46 phase-sweep-1";
      10: return "TC46 phase-sweep-2";
      default: return "TC46 phase-sweep-3";
    endcase
  endfunction

  function automatic real cfg_m_per(input int i);
    case (i)
      0: return 10; 1: return 20; 2: return 10; 3: return 50; 4: return 10;
      5: return 17; 6: return 10; 7: return 10; 8: return 10; 9: return 13;
      10: return 17; default: return 10;
    endcase
  endfunction

  function automatic real cfg_s_per(input int i);
    case (i)
      0: return 10; 1: return 10; 2: return 20; 3: return 10; 4: return 50;
      5: return 10; 6: return 17; 7: return 10; 8: return 10; 9: return 17;
      10: return 13; default: return 33;
    endcase
  endfunction

  function automatic real cfg_m_ph(input int i);
    case (i)
      7: return 2; 8: return 7; 9: return 4; 10: return 11;
      default: return 0;
    endcase
  endfunction

  function automatic real cfg_s_ph(input int i);
    case (i)
      7: return 3; 8: return 1; 9: return 9; 10: return 2; 11: return 16;
      default: return 0;
    endcase
  endfunction

  // Per-configuration watchdog: restarted by run_config, polled here.
  real cfg_start_ns = 0.0;
  real watchdog_ns  = 5_000_000.0;
  bit  all_done     = 1'b0;

  // Stop the clocks, apply the new period/phase, restart. The DUT is held in
  // reset and all inputs idle while the clocks are parked so no state leaks
  // from one configuration into the next.
  task automatic set_clock_config(input real m_per, input real s_per,
                                  input real m_ph,  input real s_ph);
    rst_m_ni = 1'b0;
    rst_s_ni = 1'b0;
    drive_idle_inputs();
    clk_en = 1'b0;
    wait (clk_m_parked && clk_s_parked);
    while (resp_mbx.num() > 0) drain_stale_cfg();
    m_penable_prev   = 1'b0;
    clk_m_period_ns  = m_per;
    clk_s_period_ns  = s_per;
    clk_m_phase_ns   = m_ph;
    clk_s_phase_ns   = s_ph;
    clk_en = 1'b1;
  endtask

  // One full pass of the whole test list at the currently-set clocks.
  task automatic run_test_list(input int rand_iters);
    int e;

    e = error_count; t01_reset_idle();            tc_report("TC01 reset-idle",           e);
    e = error_count; t02_reset_during_request();  tc_report("TC02 reset-during-request", e);
    e = error_count; t03_reset_during_access();   tc_report("TC03 reset-during-access",  e);
    e = error_count; t04_reset_during_ack();      tc_report("TC04 reset-during-ack",     e);

    t10_13_basic();
    t2x_wait_states();
    t3x_data_integrity();
    t6x_back_to_back();

    e = error_count; t80_random(rand_iters);
    tc_report($sformatf("TC80 random (%0d transactions)", rand_iters), e);
  endtask

  int cfg_fail_count = 0;

  task automatic run_config(input string name,
                            input real m_per, input real s_per,
                            input real m_ph,  input real s_ph,
                            input int rand_iters);
    int err0, tc0;
    err0 = error_count;
    tc0  = test_count;
    $display("=== %s: clk_m=%0.2fns clk_s=%0.2fns phase_m=%0.2fns phase_s=%0.2fns ===",
             name, m_per, s_per, m_ph, s_ph);
    set_clock_config(m_per, s_per, m_ph, s_ph);
    cfg_start_ns = $realtime;
    run_test_list(rand_iters);
    if (error_count == err0) begin
      $display("CONFIG PASS: %s (%0d transactions, 0 errors)", name, test_count - tc0);
    end else begin
      cfg_fail_count++;
      $display("CONFIG FAIL: %s (%0d transactions, %0d errors)", name, test_count - tc0, error_count - err0);
    end
  endtask

  // -----------------------------------------------------------------------
  // Top-level test sequence
  //   default            : sweep all NUM_CFGS clock configurations
  //   +CLK_*_NS given    : run ONE custom configuration (debug / repro)
  //   +RAND_ITERS=N      : random transactions per configuration (default 150)
  //   +WATCHDOG_NS=T     : per-configuration timeout (default 5 ms)
  //   +VERBOSE           : also print every random (TC80) transaction
  // -----------------------------------------------------------------------
  initial begin
    int       rand_iters;
    bit       custom;
    real      m_per, s_per, m_ph, s_ph;

    rand_iters = 150;
    void'($value$plusargs("RAND_ITERS=%d",  rand_iters));
    verbose = $test$plusargs("VERBOSE");
    void'($value$plusargs("WATCHDOG_NS=%f", watchdog_ns));

    drive_idle_inputs();
    rst_m_ni = 1'b0;
    rst_s_ni = 1'b0;

    custom = $test$plusargs("CLK_M_PERIOD_NS") || $test$plusargs("CLK_S_PERIOD_NS") ||
             $test$plusargs("CLK_M_PHASE_NS")  || $test$plusargs("CLK_S_PHASE_NS");

    if (custom) begin
      m_per = 10.0; s_per = 10.0; m_ph = 0.0; s_ph = 0.0;
      void'($value$plusargs("CLK_M_PERIOD_NS=%f", m_per));
      void'($value$plusargs("CLK_S_PERIOD_NS=%f", s_per));
      void'($value$plusargs("CLK_M_PHASE_NS=%f",  m_ph));
      void'($value$plusargs("CLK_S_PHASE_NS=%f",  s_ph));
      run_config("custom", m_per, s_per, m_ph, s_ph, rand_iters);
    end else begin
      for (int i = 0; i < NUM_CFGS; i++) begin
        run_config(cfg_name(i), cfg_m_per(i), cfg_s_per(i), cfg_m_ph(i), cfg_s_ph(i), rand_iters);
      end
    end

    all_done = 1'b1;
    report_coverage();

    if (error_count == 0)
      $display("TESTBENCH PASS: %0d configs, %0d transactions, 0 errors",
               custom ? 1 : NUM_CFGS, test_count);
    else
      $display("TESTBENCH FAIL: %0d config(s) failed, %0d transactions, %0d errors",
               cfg_fail_count, test_count, error_count);

    $finish;
  end

  // Watchdog: fail loudly instead of hanging if a configuration stalls.
  initial begin
    forever begin
      #1000;
      if (!all_done && (($realtime - cfg_start_ns) > watchdog_ns)) begin
        $error("WATCHDOG TIMEOUT: configuration did not finish within %0.0f ns", watchdog_ns);
        $display("TESTBENCH FAIL: watchdog timeout");
        $finish;
      end
    end
  end

endmodule
