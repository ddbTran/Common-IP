// ============================================================================
// Module      : tb_async_ring_fifo
// Description : Black-box, self-checking asynchronous ring FIFO testbench.
// ============================================================================
`timescale 1ns/1ps

module tb_async_ring_fifo #(
    parameter int WIDTH           = 32,
    parameter int DEPTH           = 8,
    parameter int WR_HALF_PERIOD  = 5,
    parameter int RD_HALF_PERIOD  = 7,
    parameter int RD_PHASE        = 3
);
    localparam int OP_TIMEOUT_CYCLES = (DEPTH * 128) + 512;
    localparam int GLOBAL_TIMEOUT_NS = 20_000_000;

    logic clk_wr_i, rst_wr_ni;
    logic clk_rd_i, rst_rd_ni;
    logic [WIDTH-1:0] wr_data_i, rd_data_o;
    logic wren_i, rden_i, full_o, ready_o, empty_o, valid_o;

    bit run_wr_clk = 1;
    bit run_rd_clk = 1;

    async_ring_fifo #(
        .WIDTH (WIDTH),
        .DEPTH (DEPTH)
    ) dut (
        .clk_wr_i  (clk_wr_i),
        .rst_wr_ni (rst_wr_ni),
        .clk_rd_i  (clk_rd_i),
        .rst_rd_ni (rst_rd_ni),
        .wr_data_i (wr_data_i),
        .wren_i    (wren_i),
        .full_o    (full_o),
        .ready_o   (ready_o),
        .rd_data_o (rd_data_o),
        .rden_i    (rden_i),
        .empty_o   (empty_o),
        .valid_o   (valid_o)
    );

    // Clock phases deliberately avoid coincident rising edges. Change half
    // periods (odd values) to repeat the regression at other clock ratios.
    initial begin
        clk_wr_i = 1'b0;
        forever begin
            #(WR_HALF_PERIOD);
            if (run_wr_clk) clk_wr_i = ~clk_wr_i;
            else            clk_wr_i = 1'b0;
        end
    end
    initial begin
        clk_rd_i = 1'b0;
        #(RD_PHASE);
        forever begin
            #(RD_HALF_PERIOD);
            if (run_rd_clk) clk_rd_i = ~clk_rd_i;
            else            clk_rd_i = 1'b0;
        end
    end

    logic [WIDTH-1:0] ref_q[$];
    longint unsigned wr_accepted, rd_accepted;
    longint unsigned wr_blocked, rd_blocked;
    longint unsigned comparisons, full_samples, empty_samples;
    longint unsigned errors;
    string active_test = "startup";

    task automatic fail(input string reason);
        errors++;
        $error("FAIL [%s] @%0t: %s", active_test, $time, reason);
        $fatal(1, "async_ring_fifo test failed");
    endtask

    // All write transactions are recorded at the write-domain clock edge.
    // The queue is an independent *data-order* reference model, not an image
    // of the CDC-delayed full/empty state.
    always @(posedge clk_wr_i) begin
        if (rst_wr_ni && rst_rd_ni) begin
            if ((ready_o !== 1'b0) && (ready_o !== 1'b1))
                fail("ready_o is X/Z");
            if ((full_o !== 1'b0) && (full_o !== 1'b1))
                fail("full_o is X/Z");
            if (full_o === 1'b1) full_samples++;
            if (full_o === 1'b1 && ready_o === 1'b1)
                fail("full_o and ready_o asserted together");
            if (wren_i) begin
                if (ready_o === 1'b1) begin
                    ref_q.push_back(wr_data_i);
                    wr_accepted++;
                    if (ref_q.size() > DEPTH)
                        fail($sformatf("accepted occupancy exceeds DEPTH: %0d > %0d",
                                       ref_q.size(), DEPTH));
                end else begin
                    wr_blocked++;
                end
            end
        end
    end

    // rd_data_o is compared only when the read handshake is accepted.
    always @(posedge clk_rd_i) begin : read_monitor
        logic [WIDTH-1:0] expected;
        if (rst_wr_ni && rst_rd_ni) begin
            if ((valid_o !== 1'b0) && (valid_o !== 1'b1))
                fail("valid_o is X/Z");
            if ((empty_o !== 1'b0) && (empty_o !== 1'b1))
                fail("empty_o is X/Z");
            if (empty_o === 1'b1) empty_samples++;
            if (empty_o === 1'b1 && valid_o === 1'b1)
                fail("empty_o and valid_o asserted together");
            if (rden_i) begin
                if (valid_o === 1'b1) begin
                    if (ref_q.size() == 0)
                        fail("read accepted with empty reference model");
                    expected = ref_q.pop_front();
                    rd_accepted++;
                    comparisons++;
                    if (rd_data_o !== expected)
                        fail($sformatf("data mismatch: expected=%0h got=%0h read=%0d",
                                       expected, rd_data_o, rd_accepted));
                end else begin
                    rd_blocked++;
                end
            end
        end
    end

    // Different words even with WIDTH > 32; deterministic for any WIDTH.
    function automatic logic [WIDTH-1:0] word(input int unsigned index);
        logic [WIDTH-1:0] result;
        logic [31:0] x;
        for (int b = 0; b < WIDTH; b++) begin
            x = (index + 32'h9e37_79b9) ^ (32'h7f4a_7c15 * ((b/32) + 1));
            x ^= (x << 13);
            x ^= (x >> 17);
            x ^= (x << 5);
            result[b] = x[b % 32];
        end
        return result;
    endfunction

    function automatic logic [WIDTH-1:0] random_word();
        logic [WIDTH-1:0] result;
        logic [31:0] chunk;
        for (int b = 0; b < WIDTH; b++) begin
            if ((b % 32) == 0) chunk = $urandom();
            result[b] = chunk[b % 32];
        end
        return result;
    endfunction

    task automatic send_word(input logic [WIDTH-1:0] data, input int gap = 0);
        for (int k = 0; k < gap; k++) @(negedge clk_wr_i);
        @(negedge clk_wr_i);
        wr_data_i = data;
        wren_i = 1'b1;
        for (int k = 0; k < OP_TIMEOUT_CYCLES; k++) begin
            @(posedge clk_wr_i);
            if (ready_o === 1'b1) begin
                @(negedge clk_wr_i);
                wren_i = 1'b0;
                return;
            end
        end
        fail("timeout waiting for a write transfer");
    endtask

    task automatic recv_word(input int gap = 0);
        for (int k = 0; k < gap; k++) @(negedge clk_rd_i);
        @(negedge clk_rd_i);
        rden_i = 1'b1;
        for (int k = 0; k < OP_TIMEOUT_CYCLES; k++) begin
            @(posedge clk_rd_i);
            if (valid_o === 1'b1) begin
                @(negedge clk_rd_i);
                rden_i = 1'b0;
                return;
            end
        end
        fail("timeout waiting for a read transfer");
    endtask

    task automatic wait_full();
        for (int k = 0; k < OP_TIMEOUT_CYCLES; k++) begin
            @(negedge clk_wr_i);
            if (full_o === 1'b1) return;
        end
        fail("full_o did not assert after filling DEPTH slots");
    endtask

    task automatic wait_empty();
        for (int k = 0; k < OP_TIMEOUT_CYCLES; k++) begin
            @(negedge clk_rd_i);
            if (empty_o === 1'b1) return;
        end
        fail("empty_o did not assert after complete drain");
    endtask

    task automatic assert_empty(input string where);
        wait_empty();
        if (ref_q.size() != 0)
            fail($sformatf("%s: expected empty ref_q, got %0d", where, ref_q.size()));
        if (wr_accepted != rd_accepted)
            fail($sformatf("%s: transfer imbalance wr=%0d rd=%0d",
                           where, wr_accepted, rd_accepted));
    endtask

    task automatic do_reset();
        // Both reset domains are treated as a single FIFO reset contract.
        // Keep all active traffic quiescent while asserting reset.
        @(negedge clk_wr_i);
        #1;
        wren_i = 1'b0;
        rden_i = 1'b0;
        wr_data_i = '0;
        rst_wr_ni = 1'b0;
        rst_rd_ni = 1'b0;
        ref_q.delete();
        // Counters count transfers since the LAST reset (used by balancing).
        wr_accepted = 0;
        rd_accepted = 0;
        repeat (5) @(negedge clk_wr_i);
        repeat (5) @(negedge clk_rd_i);
        #1;
        rst_wr_ni = 1'b1;
        rst_rd_ni = 1'b1;
        repeat (8) @(negedge clk_wr_i);
        repeat (8) @(negedge clk_rd_i);
        wait_empty();
        if (full_o === 1'b1)
            fail("full_o stuck high after reset");
    endtask

    task automatic test_basic();
        active_test = "basic + data patterns";
        $display("-- %s --", active_test);
        send_word('0);
        recv_word();
        send_word('1);
        recv_word();
        for (int b = 0; b < WIDTH; b++) begin
            logic [WIDTH-1:0] walk;
            walk = '0;
            walk[b] = 1'b1;
            send_word(walk);
            recv_word();
            send_word(~walk);
            recv_word();
        end
        assert_empty(active_test);
    endtask

    task automatic test_partial_fill_and_idle();
        active_test = "partial fill + long idle + readback";
        $display("-- %s --", active_test);
        for (int i = 0; i < (DEPTH + 1) / 2; i++)
            send_word(word(50 + i));
        repeat (DEPTH * 10 + 20) @(negedge clk_wr_i);
        repeat (DEPTH * 10 + 20) @(negedge clk_rd_i);
        for (int i = 0; i < (DEPTH + 1) / 2; i++) recv_word();
        assert_empty(active_test);
    endtask

    task automatic test_fill_overflow_drain();
        longint unsigned writes_before, reads_before;
        active_test = "fill + blocked writes + drain + blocked reads";
        $display("-- %s --", active_test);
        for (int i = 0; i < DEPTH; i++) send_word(word(100 + i));
        if (ref_q.size() != DEPTH)
            fail($sformatf("expected %0d accepted writes, got %0d", DEPTH, ref_q.size()));
        wait_full();
        writes_before = wr_accepted;
        @(negedge clk_wr_i);
        wren_i = 1'b1;
        wr_data_i = '1;
        repeat (DEPTH + 12) @(posedge clk_wr_i);
        @(negedge clk_wr_i);
        wren_i = 1'b0;
        if (wr_accepted != writes_before)
            fail("unexpected write accepted while full");
        for (int i = 0; i < DEPTH; i++) recv_word();
        assert_empty(active_test);
        reads_before = rd_accepted;
        @(negedge clk_rd_i);
        rden_i = 1'b1;
        repeat (DEPTH + 12) @(posedge clk_rd_i);
        @(negedge clk_rd_i);
        rden_i = 1'b0;
        if (rd_accepted != reads_before)
            fail("unexpected read accepted while empty");
    endtask

    task automatic test_wrap();
        active_test = "wrap-around / slot reuse";
        $display("-- %s --", active_test);
        for (int i = 0; i < DEPTH * 5 + 3; i++) begin
            send_word(word(1000 + i));
            recv_word();
        end
        assert_empty(active_test);
    endtask

    task automatic test_concurrent(input int n, input bit random_gaps);
        active_test = random_gaps ? "concurrent randomized stress" : "concurrent back-to-back";
        $display("-- %s: %0d transfers --", active_test, n);
        fork
            begin
                for (int i = 0; i < n; i++)
                    send_word(random_gaps ? random_word() : word(2000 + i),
                              random_gaps ? $urandom_range(0, 5) : 0);
            end
            begin
                for (int i = 0; i < n; i++)
                    recv_word(random_gaps ? $urandom_range(0, 7) : 0);
            end
        join
        assert_empty(active_test);
    endtask

    task automatic test_full_recovery();
        active_test = "full -> simultaneous producer/consumer recovery";
        $display("-- %s --", active_test);
        for (int i = 0; i < DEPTH; i++) send_word(word(5000 + i));
        wait_full();
        fork
            begin
                for (int i = 0; i < DEPTH * 3; i++) send_word(word(6000 + i));
            end
            begin
                for (int i = 0; i < DEPTH * 4; i++) recv_word();
            end
        join
        assert_empty(active_test);
    endtask

    task automatic test_clock_stops();
        longint unsigned count_before;
        active_test = "paused read clock -> full -> recovery";
        $display("-- %s --", active_test);
        @(negedge clk_rd_i);
        run_rd_clk = 1'b0;
        for (int i = 0; i < DEPTH; i++) send_word(word(8000 + i));
        wait_full();
        count_before = wr_accepted;
        @(negedge clk_wr_i);
        wr_data_i = '1;
        wren_i = 1'b1;
        repeat (DEPTH + 8) @(posedge clk_wr_i);
        @(negedge clk_wr_i);
        wren_i = 1'b0;
        if (wr_accepted != count_before)
            fail("write accepted after full while read clock stopped");
        run_rd_clk = 1'b1;
        for (int i = 0; i < DEPTH; i++) recv_word();
        assert_empty(active_test);

        active_test = "paused write clock -> drain -> recovery";
        $display("-- %s --", active_test);
        for (int i = 0; i < DEPTH; i++) send_word(word(9000 + i));
        @(negedge clk_wr_i);
        run_wr_clk = 1'b0;
        for (int i = 0; i < DEPTH; i++) recv_word();
        assert_empty(active_test);
        run_wr_clk = 1'b1;
        send_word(word(10000));
        recv_word();
        assert_empty(active_test);
    endtask

    task automatic test_reset_with_pending_data();
        active_test = "reset with pending data / fresh traffic";
        $display("-- %s --", active_test);
        for (int i = 0; i < (DEPTH + 1) / 2; i++) send_word(word(11000 + i));
        // Both sides reset together; partial independent-domain reset is NOT
        // assumed safe unless explicitly supported by the DUT specification.
        do_reset();
        for (int i = 0; i < DEPTH * 2; i++) begin
            send_word(word(12000 + i));
            recv_word();
        end
        assert_empty(active_test);
    endtask

    initial begin : test_main
        int unsigned seed;
        int unsigned original_seed;
        if (WIDTH < 1 || DEPTH < 1) $fatal(1, "WIDTH and DEPTH must be positive");
        if ((WR_HALF_PERIOD % 2) != 1 ||
            (RD_HALF_PERIOD % 2) != 1 ||
            (RD_PHASE % 2) != 1)
            $fatal(1, "Use odd WR/RD half periods and odd RD_PHASE to avoid simultaneous rising edges");
        if (!$value$plusargs("SEED=%d", seed)) seed = 1;
        original_seed = seed;
        void'($urandom(seed));
        wr_accepted = 0;
        rd_accepted = 0;
        wr_blocked = 0;
        rd_blocked = 0;
        comparisons = 0;
        full_samples = 0;
        empty_samples = 0;
        errors = 0;
        rst_wr_ni = 1'b0;
        rst_rd_ni = 1'b0;
        wren_i = 1'b0;
        rden_i = 1'b0;
        wr_data_i = '0;

        $display("TB_ASYNC_RING_FIFO: WIDTH=%0d DEPTH=%0d WR_T=%0d RD_T=%0d RD_PHASE=%0d SEED=%0d",
                 WIDTH, DEPTH, 2*WR_HALF_PERIOD, 2*RD_HALF_PERIOD, RD_PHASE, original_seed);
        do_reset();
        test_basic();
        test_partial_fill_and_idle();
        test_fill_overflow_drain();
        test_wrap();
        test_concurrent(DEPTH * 12, 1'b0);
        test_full_recovery();
        test_concurrent(2000, 1'b1);
        test_clock_stops();
        test_reset_with_pending_data();

        if (full_samples == 0 || empty_samples == 0 ||
            wr_blocked == 0 || rd_blocked == 0 || comparisons == 0)
            fail("incomplete basic functional coverage");
        if (errors != 0) $fatal(1, "FAIL: %0d errors", errors);
        $display("TB_ASYNC_RING_FIFO: PASS writes=%0d reads=%0d compared=%0d blocked_wr=%0d blocked_rd=%0d",
                 wr_accepted, rd_accepted, comparisons, wr_blocked, rd_blocked);
        $finish;
    end

    initial begin
        #(GLOBAL_TIMEOUT_NS);
        $fatal(1, "TB_ASYNC_RING_FIFO: global watchdog timeout");
    end

    initial begin
        $dumpfile("async_ring_fifo.fst");
        $dumpvars(0, tb_async_ring_fifo);
    end
endmodule

