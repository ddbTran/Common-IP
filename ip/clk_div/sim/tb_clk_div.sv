// ============================================================================
// Module      : tb_clk_div
// Description : Port-only, self-checking testbench for clk_div
// Notes       : Zero-delay RTL simulation; no DUT hierarchy is referenced.
//               Requests are sampled on posedge clk_i.
// ============================================================================
`timescale 1ps/1ps

module tb_clk_div #(
    // DUT configuration.
    parameter int unsigned CNT_WIDTH            = 5,
    parameter int unsigned DEFAULT_DIVISION     = 2,

    // Simulation configuration.
    parameter time         CLK_PERIOD           = 10ns,
    parameter int unsigned TIMEOUT_CYCLES       = 4 * MAX_DIVISION + 16,
    parameter time         WATCHDOG_TIME         = 100ms,

    // Verification configuration.
    parameter int unsigned CHECK_PERIODS        = 4,
    parameter bit          CHECK_50_PERCENT_DUTY = 1'b0,
    parameter bit          CHECK_STARTUP_LATENCY = 1'b0
);

    localparam int unsigned MAX_DIVISION   = 2**CNT_WIDTH - 1;
    localparam time         HALF_PERIOD = CLK_PERIOD / 2;
    localparam time         DRIVE_SKEW  = 1ps;

    logic                 clk_i   = 1'b0;
    logic                 rst_ni  = 1'b0;
    logic                 en_i    = 1'b0;
    logic [CNT_WIDTH-1:0] div_i   = '0;
    logic                 valid_i = 1'b0;
    wire                  ready_o;
    wire                  clk_o;

    clk_div #(
        .CNT_WIDTH(CNT_WIDTH),        
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

    always #(HALF_PERIOD) clk_i = ~clk_i;

    int unsigned errors = 0;
    int unsigned checks = 0;
    int unsigned transactions = 0;
    int unsigned stalled_cycles = 0;
    int unsigned random_tests = 64;
    int unsigned rng_state = 32'h1234_5678;
    int unsigned model_div = (DEFAULT_DIVISION <= 1) ? 1 : DEFAULT_DIVISION;
    int unsigned model_raw = DEFAULT_DIVISION;
    int unsigned accepted [0:MAX_DIVISION];
    int unsigned measured [0:MAX_DIVISION];
    int unsigned transitions [0:MAX_DIVISION][0:MAX_DIVISION];

    bit ref_valid [1:MAX_DIVISION];
    time high_ref [1:MAX_DIVISION];
    time low_ref  [1:MAX_DIVISION];
    bit phase_valid [0:1][1:MAX_DIVISION];
    time phase_ref  [0:1][1:MAX_DIVISION];
    time latency_ref[0:1][1:MAX_DIVISION];

    bit negative_mode = 0;
    bit reset_settled = 0;
    bit expect_quiet = 1;
    bit pending_request = 0;
    logic [CNT_WIDTH-1:0] held_div;
    bit gap_allowed = 1;
    bit stop_pending = 0;
    int unsigned stop_rises_left = 0;
    bit startup_pending = 0;
    int unsigned startup_kind = 0;  // 0: enable; 1: active reconfiguration
    int unsigned startup_div = 1;
    time startup_anchor = 0;

    bit have_rise = 0;
    bit have_fall = 0;
    bit high_open = 0;
    time last_rise = 0;
    time last_fall = 0;
    int unsigned rise_div = 1;
    int unsigned fall_div = 1;
    logic previous_output = 1'bx;

    // next_rise()/next_fall() are always called sequentially (never concurrently),
    // so a single shared variable is safe and avoids writing to a task's output
    // argument after a timing control, which IEEE 1800-2023 13.2.2 disallows.
    time g_edge_time;

    function automatic int unsigned effective(input int unsigned raw);
        return (raw <= 1) ? 1 : raw;
    endfunction

    function automatic int unsigned random_below(input int unsigned limit);
        rng_state = 32'd1664525 * rng_state + 32'd1013904223;
        return (limit == 0) ? 0 : rng_state % limit;
    endfunction

    task automatic check(input bit condition, input string message);
        checks++;
        if (!condition) begin
            errors++;
            $error("[TB_FAIL] t=%0t %s", $time, message);
            if (errors >= 20)
                $fatal(1, "[TB_FAIL] Stopping after %0d errors", errors);
        end
    endtask

    task automatic cycles(input int unsigned count);
        repeat (count) @(negedge clk_i);
        #DRIVE_SKEW;
    endtask

    // No driver changes occur on the DUT's rising-edge sampling event.
    task automatic drive_slot;
        @(negedge clk_i);
        #DRIVE_SKEW;
    endtask

    task automatic next_rise();
        bit seen;
        seen = 0;
        fork
            begin
                @(posedge clk_o);
                g_edge_time = $time;
                seen = 1;
            end
            begin
                #(TIMEOUT_CYCLES * CLK_PERIOD);
            end
        join_any
        disable fork;
        if (!seen)
            $fatal(1, "[TB_TIMEOUT] No clk_o rising edge, div=%0d", model_div);
        #DRIVE_SKEW;
    endtask

    task automatic next_fall();
        bit seen;
        seen = 0;
        fork
            begin
                @(negedge clk_o);
                g_edge_time = $time;
                seen = 1;
            end
            begin
                #(TIMEOUT_CYCLES * CLK_PERIOD);
            end
        join_any
        disable fork;
        if (!seen)
            $fatal(1, "[TB_TIMEOUT] No clk_o falling edge, div=%0d", model_div);
        #DRIVE_SKEW;
    endtask

    // Reset aborts a transaction and exempts the interrupted pulse from checks.
    always @(posedge clk_i or negedge rst_ni) begin : configuration_monitor
        int unsigned requested;
        bit changed;
        if (!rst_ni) begin
            model_div       = effective(DEFAULT_DIVISION);
            model_raw       = DEFAULT_DIVISION;
            pending_request = 0;
            gap_allowed     = 1;
            startup_pending = 0;
            stop_pending    = 0;
        end else begin
            check((ready_o === 1'b0) || (ready_o === 1'b1), "ready_o is X/Z");
            if (pending_request)
                check((valid_i === 1'b1) && (div_i === held_div),
                      "TB protocol violation: request changed before acceptance");

            if (!en_i)
                gap_allowed = 1;
            if (valid_i === 1'b1) begin
                check(!$isunknown(div_i), "div_i is X/Z during a request");
                requested = int'(div_i);
                if (!negative_mode)
                    check(requested <= MAX_DIVISION, "TB drove an illegal division");
                if (effective(requested) != model_div)
                    gap_allowed = 1;

                if ((ready_o === 1'b1) && (requested <= MAX_DIVISION)) begin
                    changed = (effective(requested) != model_div);
                    if (changed)
                        check(clk_o === 1'b0,
                              "Changed configuration accepted while clk_o is high/X/Z");
                    accepted[requested]++;
                    transitions[model_raw][requested]++;
                    transactions++;
                    model_raw = requested;
                    model_div = effective(requested);
                    if (changed && en_i) begin
                        startup_pending = 1;
                        startup_kind    = 1;
                        startup_div     = model_div;
                        startup_anchor  = $time;
                    end
                end
            end
            pending_request = (valid_i === 1'b1) && (ready_o !== 1'b1);
            held_div = div_i;
            if (pending_request)
                stalled_cycles++;
        end
    end

    always @(negedge rst_ni) begin
        have_rise = 0;
        have_fall = 0;
        high_open = 0;
    end

    // Check every transition, including transitions during stop/reconfiguration.
    always @(clk_o) begin : output_monitor
        time width;
        time expected_period;
        time minimum_low;
        time latency;
        time phase;
        if (!rst_ni) begin
            if (reset_settled)
                check(clk_o === 1'b0, "Output transition to high/X/Z during reset");
            have_rise = 0;
            have_fall = 0;
            high_open = 0;
        end else if ((clk_o !== 1'b0) && (clk_o !== 1'b1)) begin
            check(0, "clk_o is X/Z");
        end else if (clk_o !== previous_output) begin
            check(($time % HALF_PERIOD) == 0,
                  "clk_o changed away from a source-clock edge (zero-delay RTL check)");
            if (expect_quiet)
                check(clk_o === 1'b0, "Unexpected output pulse while stopped");

            if (clk_o === 1'b1) begin
                if (stop_pending) begin
                    check(stop_rises_left != 0,
                          "Extra rising edge after the final permitted stop pulse");
                    if (stop_rises_left != 0)
                        stop_rises_left--;
                end
                if (model_div == 1)
                    check(clk_i === 1'b1, "Bypass rising edge is not a clk_i rising edge");
                if (have_fall) begin
                    width = $time - last_fall;
                    check(width >= HALF_PERIOD, "Runt/zero-width low pulse");
                    minimum_low = HALF_PERIOD;
                    if (ref_valid[fall_div]) begin
                        minimum_low = low_ref[fall_div];
                        // Transition low-time is not numerically specified.
                        // Use the smaller adjacent steady low time across a change.
                        if (model_div != fall_div) begin
                            if (!ref_valid[model_div])
                                minimum_low = HALF_PERIOD;
                            else if (low_ref[model_div] < minimum_low)
                                minimum_low = low_ref[model_div];
                        end
                    end
                    check(width >= minimum_low,
                          $sformatf("Short low interval across div=%0d -> %0d: got %0t, minimum %0t",
                                    fall_div, model_div, width, minimum_low));
                end
                if (have_rise && (rise_div == model_div)) begin
                    expected_period = CLK_PERIOD * model_div;
                    check(($time - last_rise) >= expected_period,
                          "Two rising edges are closer than one configured period");
                    if (!gap_allowed)
                        check(($time - last_rise) == expected_period,
                              $sformatf("Unexpected period/pause for div=%0d: got %0t, expected %0t",
                                        model_div, $time - last_rise, expected_period));
                end
                if (startup_pending) begin
                    check(model_div == startup_div, "Startup configuration mismatch");
                    check($time >= startup_anchor, "Clock started before the sampled start event");
                    latency = $time - startup_anchor;
                    phase   = latency % CLK_PERIOD;
                    if (phase_valid[startup_kind][model_div]) begin
                        check(phase == phase_ref[startup_kind][model_div],
                              $sformatf("Non-repeatable source-edge phase, div=%0d kind=%0d",
                                        model_div, startup_kind));
                        if (CHECK_STARTUP_LATENCY)
                            check(latency == latency_ref[startup_kind][model_div],
                                  $sformatf("Non-repeatable startup latency, div=%0d kind=%0d",
                                            model_div, startup_kind));
                    end else begin
                        phase_valid[startup_kind][model_div] = 1;
                        phase_ref[startup_kind][model_div] = phase;
                        latency_ref[startup_kind][model_div] = latency;
                    end
                    startup_pending = 0;
                end
                last_rise = $time;
                rise_div  = model_div;
                have_rise = 1;
                high_open = 1;
                gap_allowed = !en_i || ((valid_i === 1'b1) &&
                                           (effective(int'(div_i)) != model_div));
            end else if (high_open) begin
                width = $time - last_rise;
                check(width >= HALF_PERIOD, "Runt/zero-width high pulse");
                if (rise_div == 1)
                    check(clk_i === 1'b0, "Bypass falling edge is not a clk_i falling edge");
                if (ref_valid[rise_div])
                    check(width == high_ref[rise_div],
                          $sformatf("Changed/truncated high pulse for div=%0d: got %0t, expected %0t",
                                    rise_div, width, high_ref[rise_div]));
                if (CHECK_50_PERCENT_DUTY)
                    check(width == (CLK_PERIOD * rise_div) / 2,
                          "High pulse violates the optional exact-50-percent check");
                last_fall = $time;
                fall_div  = rise_div;
                have_fall = 1;
                high_open = 0;
            end
        end
        previous_output = clk_o;
    end

    always @(rst_ni) begin
        reset_settled = 0;
        if (!rst_ni) begin
            #DRIVE_SKEW;
            reset_settled = 1;
        end
    end

    // Allow reset's NBA/continuous-assignment propagation, but not another cycle.
    always @(negedge rst_ni or posedge clk_i or negedge clk_i) begin
        #DRIVE_SKEW;
        if (!rst_ni)
            check(clk_o === 1'b0, "clk_o is not low while reset is asserted");
    end

    task automatic wait_accept;
        bit accepted_here;
        accepted_here = 0;
        for (int unsigned n = 0; n < TIMEOUT_CYCLES; n++) begin
            @(posedge clk_i);
            if (ready_o === 1'b1) begin
                accepted_here = 1;
                break;
            end
        end
        if (!accepted_here)
            $fatal(1, "[TB_TIMEOUT] No configuration acceptance for div=%0d", div_i);
    endtask

    task automatic request_division(input int unsigned raw);
        if (raw > MAX_DIVISION)
            $fatal(1, "[TB_ERROR] request_division called with illegal value %0d", raw);
        drive_slot();
        if (effective(raw) != model_div)
            gap_allowed = 1;
        div_i = CNT_WIDTH'(raw);
        valid_i = 1'b1;
        wait_accept();
        drive_slot();
        valid_i = 1'b0;
        check(model_div == effective(raw), "Configuration scoreboard mismatch");
    endtask

    task automatic start_clock;
        check(en_i === 1'b0, "TB tried to start an already enabled divider");
        drive_slot();
        expect_quiet    = 0;
        stop_pending    = 0;
        startup_pending = 1;
        startup_kind    = 0;
        startup_div     = model_div;
        startup_anchor  = $time + HALF_PERIOD - DRIVE_SKEW;
        gap_allowed     = 1;
        en_i = 1'b1;
    endtask

    task automatic request_stop;
        drive_slot();
        startup_pending = 0;
        gap_allowed     = 1;
        stop_pending    = 1;
        // The current safe-boundary-to-boundary period has at most one rise left.
        stop_rises_left = (clk_o === 1'b1) ? 0 : 1;
        en_i = 1'b0;
    endtask

    task automatic wait_stopped;
        cycles(TIMEOUT_CYCLES);
        check(clk_o === 1'b0, "Clock did not stop within the TB timeout");
        expect_quiet = 1;
        cycles(2 * MAX_DIVISION + 4);
        check(clk_o === 1'b0, "Clock is not held low after stopping");
    endtask

    task automatic stop_clock;
        request_stop();
        wait_stopped();
    endtask

    task automatic check_running(input int unsigned raw, input int unsigned periods);
        time rise0, fall0, rise1;
        time high_width, low_width;
        int unsigned d;
        d = effective(raw);
        check((en_i === 1'b1) && (model_div == d), "Incorrect setup for running-clock check");
        next_rise(); rise0 = g_edge_time;
        repeat (periods) begin
            next_fall(); fall0 = g_edge_time;
            next_rise(); rise1 = g_edge_time;
            high_width = fall0 - rise0;
            low_width  = rise1 - fall0;
            check((rise1 - rise0) == CLK_PERIOD * d,
                  $sformatf("Wrong divide ratio: raw=%0d got period=%0t expected=%0t",
                            raw, rise1 - rise0, CLK_PERIOD * d));
            if (ref_valid[d]) begin
                check(high_width == high_ref[d], "Non-repeatable steady-state high width");
                check(low_width  == low_ref[d],  "Non-repeatable steady-state low width");
            end else begin
                high_ref[d] = high_width;
                low_ref[d]  = low_width;
                ref_valid[d] = 1;
            end
            if ((d == 1) || CHECK_50_PERCENT_DUTY) begin
                check(high_width == (CLK_PERIOD * d) / 2, "Incorrect high duty interval");
                check(low_width  == (CLK_PERIOD * d) / 2, "Incorrect low duty interval");
            end
            rise0 = rise1;
        end
        measured[raw]++;
    endtask

    task automatic apply_reset(input bit keep_enable = 1'b0);
        // Call off the source-clock edge, including from inside an output pulse.
        rst_ni = 1'b0;
        if (!keep_enable)
            en_i = 1'b0;
        valid_i = 1'b0;
        div_i = '0;
        expect_quiet = 1;
        cycles(keep_enable ? (2 * MAX_DIVISION + 3) : 3);
        en_i = 1'b0;
        cycles(2);
        rst_ni = 1'b1;
        cycles(3);
        check(clk_o === 1'b0, "Reset release generated a clock with en_i=0");
        check(model_div == effective(DEFAULT_DIVISION), "Reset scoreboard mismatch");
    endtask

    task automatic burst_requests;
        int unsigned raw;
        drive_slot();
        valid_i = 1'b1;
        for (int unsigned n = 0; n < 2 * (MAX_DIVISION + 1); n++) begin
            raw = n % (MAX_DIVISION + 1);
            if (effective(raw) != model_div)
                gap_allowed = 1;
            div_i = CNT_WIDTH'(raw);
            wait_accept();
            // Change data immediately in the next drive slot; valid stays high.
            drive_slot();
        end
        valid_i = 1'b0;
        check_running(raw, CHECK_PERIODS);
    endtask

    task automatic illegal_request(input int unsigned raw);
        if ((raw <= MAX_DIVISION) ||
            ((64'(raw) >> CNT_WIDTH) != 0))
            $fatal(1, "[TB_ERROR] ILLEGAL_DIV must be > MAX_DIVISION and fit in div_i");
        $display("[TB_NEGATIVE] Driving representable illegal division %0d", raw);
        $display("[TB_NEGATIVE] Expect a DUT assertion; this mode never prints TB_PASS");
        drive_slot();
        div_i = CNT_WIDTH'(raw);
        valid_i = 1'b1;
        // Reset ends the deliberately illegal request without breaking a stall.
        cycles(TIMEOUT_CYCLES);
        rst_ni = 1'b0;
        valid_i = 1'b0;
        cycles(2);
        $display("[TB_NEGATIVE_END] Inspect DUT assertion diagnostics; result is UNSCORED");
        $finish;
    endtask

    initial begin : watchdog
        #WATCHDOG_TIME;
        $fatal(1, "[TB_TIMEOUT] Global watchdog expired");
    end

    initial begin : test_sequence
        int unsigned discard;
        int unsigned target;
        int unsigned illegal_raw;
        time edge_time;
        string vcd_name;

        $timeformat(-9, 3, " ns", 12);
        if ((MAX_DIVISION < 1) || (DEFAULT_DIVISION > MAX_DIVISION) ||
            (CNT_WIDTH < 1) || (HALF_PERIOD <= 4 * DRIVE_SKEW) ||
            ((CLK_PERIOD % 2) != 0) || (TIMEOUT_CYCLES < 2) || (CHECK_PERIODS < 2))
            $fatal(1, "[TB_ERROR] Illegal TB parameters");

        for (int unsigned a = 0; a <= MAX_DIVISION; a++) begin
            accepted[a] = 0;
            measured[a] = 0;
            for (int unsigned b = 0; b <= MAX_DIVISION; b++)
                transitions[a][b] = 0;
        end
        for (int unsigned d = 1; d <= MAX_DIVISION; d++) begin
            ref_valid[d] = 0;
            for (int unsigned kind = 0; kind < 2; kind++)
                phase_valid[kind][d] = 0;
        end

        discard = $value$plusargs("SEED=%d", rng_state);
        discard = $value$plusargs("N_RANDOM=%d", random_tests);
        negative_mode = $value$plusargs("ILLEGAL_DIV=%d", illegal_raw);
        if ($value$plusargs("VCD=%s", vcd_name)) begin
            $dumpfile(vcd_name);
            $dumpvars(0, tb_clk_div);
        end
        $display("[TB] MAX_DIVISION=%0d DEFAULT_DIVISION=%0d SEED=%0d N_RANDOM=%0d",
                 MAX_DIVISION, DEFAULT_DIVISION, rng_state, random_tests);
        $display("[TB] Exact duty check=%0b; exact startup-latency repeatability=%0b",
                 CHECK_50_PERCENT_DUTY, CHECK_STARTUP_LATENCY);

        #2ps;
        apply_reset();
        if (negative_mode)
            illegal_request(illegal_raw);

        $display("[TEST] Default configuration after reset");
        start_clock();
        check_running(DEFAULT_DIVISION, CHECK_PERIODS);
        stop_clock();

        $display("[TEST] All legal divisions, idle writes, unchanged requests, restart");
        for (int unsigned d = 0; d <= MAX_DIVISION; d++) begin
            request_division(d);
            cycles(3);
            check(clk_o === 1'b0, "Idle configuration generated an output clock");
            start_clock();
            check_running(d, CHECK_PERIODS);
            request_division(d);
            check_running(d, 2);
            stop_clock();
            start_clock();
            check_running(d, 2);
            stop_clock();
        end

        $display("[TEST] All ordered active reconfiguration pairs, including 0 <-> 1");
        request_division(0);
        start_clock();
        check_running(0, 2);
        for (int unsigned a = 0; a <= MAX_DIVISION; a++) begin
            for (int unsigned b = 0; b <= MAX_DIVISION; b++) begin
                request_division(a);
                check_running(a, 2);
                request_division(b);
                check_running(b, 2);
            end
        end
        stop_clock();

        $display("[TEST] Sweep source-cycle offsets for stopping and reconfiguration");
        for (int unsigned d = 1; d <= MAX_DIVISION; d++) begin
            for (int unsigned offset = 0; offset < d; offset++) begin
                request_division(d);
                start_clock();
                next_rise(); edge_time = g_edge_time;
                repeat (offset) @(posedge clk_i);
                stop_clock();

                start_clock();
                next_rise(); edge_time = g_edge_time;
                repeat (offset) @(posedge clk_i);
                target = (d == MAX_DIVISION) ? 0 : d + 1;
                request_division(target);
                check_running(target, 2);
                stop_clock();
            end
        end

        $display("[TEST] Configuration submitted while a stop is in flight");
        request_division(MAX_DIVISION);
        start_clock();
        next_rise(); edge_time = g_edge_time;
        request_stop();
        request_division(0);
        wait_stopped();
        start_clock();
        check_running(0, CHECK_PERIODS);

        $display("[TEST] Consecutive requests with valid_i continuously asserted");
        burst_requests();
        stop_clock();

        $display("[TEST] Asynchronous reset during output high and output low");
        for (int unsigned level = 0; level < 2; level++) begin
            target = (effective(DEFAULT_DIVISION) == MAX_DIVISION) ? 0 : MAX_DIVISION;
            request_division(target);
            start_clock();
            if (level == 0) begin
                next_rise(); edge_time = g_edge_time;
            end else begin
                next_fall(); edge_time = g_edge_time;
            end
            #2ps;
            apply_reset(1'b1);
            start_clock();
            check_running(DEFAULT_DIVISION, CHECK_PERIODS);
            stop_clock();
        end

        $display("[TEST] Randomized requests and enable/disable sequences");
        start_clock();
        for (int unsigned n = 0; n < random_tests; n++) begin
            cycles(random_below(MAX_DIVISION + 1));
            target = random_below(MAX_DIVISION + 1);
            request_division(target);
            check_running(target, 2);
            if (random_below(3) == 0) begin
                stop_clock();
                start_clock();
                check_running(target, 2);
            end
        end
        stop_clock();

        $display("[COVERAGE] Raw division: accepted requests / steady-state measurements");
        for (int unsigned d = 0; d <= MAX_DIVISION; d++) begin
            $display("[COVERAGE] div=%0d accepted=%0d measured=%0d", d, accepted[d], measured[d]);
            check(accepted[d] != 0, "A legal division was never accepted");
            check(measured[d] != 0, "A legal division was never measured");
            for (int unsigned b = 0; b <= MAX_DIVISION; b++)
                check(transitions[d][b] != 0, "An ordered configuration pair was not exercised");
        end
        $display("[SUMMARY] checks=%0d transactions=%0d stalled_cycles=%0d errors=%0d",
                 checks, transactions, stalled_cycles, errors);
        if (errors != 0)
            $fatal(1, "[TB_FAIL] clk_div regression failed");
        $display("[TB_PASS] clk_div regression passed");
        $finish;
    end
endmodule
