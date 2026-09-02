// ============================================================================
// Module      : tb_clk_div
// Description : Self-checking testbench for parameterized clock divider
//                Tests multiple DIV_VALUE configurations concurrently.
//
// Checks:
//   1. clk_o is known after reset.
//   2. clk_o period matches the expected divide ratio.
//   3. All test configurations complete before simulation exits.
//
// Expected behavior:
//   - DIV_VALUE < 2 : clk_o == clk_i
//   - DIV_VALUE >= 2: clk_o frequency is divided by DIV_VALUE
// ============================================================================

`timescale 1ns/1ps

module tb_clk_div;

    // ------------------------------------------------------------------------
    // Test parameters
    // ------------------------------------------------------------------------
    localparam int NUM_TESTS = 6;

    localparam int DIV_VALUES[NUM_TESTS] = '{
        1, 2, 3, 4, 5, 7
    };

    localparam real CLK_PERIOD = 10.0; // ns, 100 MHz

    int errors = 0;

    // One completion flag per DUT/checker.
    bit [NUM_TESTS-1:0] done_flags;

    // ------------------------------------------------------------------------
    // Clock / reset
    // ------------------------------------------------------------------------
    logic clk_i;
    logic rst_ni;

    logic clk_o[NUM_TESTS];

    initial begin
        clk_i = 1'b0;
    end

    always #(CLK_PERIOD / 2.0) begin
        clk_i = ~clk_i;
    end

    // ------------------------------------------------------------------------
    // DUTs + parallel checkers
    // ------------------------------------------------------------------------
    genvar gi;

    generate
        for (gi = 0; gi < NUM_TESTS; gi++) begin : g_dut

            // ----------------------------------------------------------------
            // DUT
            // ----------------------------------------------------------------
            clk_div #(
                .DIV_VALUE (DIV_VALUES[gi])
            ) u_clk_div (
                .clk_i  (clk_i),
                .rst_ni (rst_ni),
                .clk_o  (clk_o[gi])
            );

            // ----------------------------------------------------------------
            // Checker
            // ----------------------------------------------------------------
            initial begin : chk_proc

                automatic int div_value = DIV_VALUES[gi];

                // DIV_VALUE < 2 means no division.
                automatic int effective_div =
                    (div_value < 2) ? 1 : div_value;

                automatic real expected_period =
                    CLK_PERIOD * effective_div;

                automatic real tolerance =
                    CLK_PERIOD * 0.1;

                automatic realtime t_edge0;
                automatic realtime t_edge1;

                automatic real measured_period;

                // ------------------------------------------------------------
                // Wait for reset release.
                // ------------------------------------------------------------
                wait (rst_ni === 1'b1);

                $display(
                    "[DIV_VALUE=%0d] Checker started at %0t",
                    div_value,
                    $time
                );

                // ------------------------------------------------------------
                // Check 1:
                // clk_o must become known after reset release.
                // ------------------------------------------------------------
                repeat (2 * effective_div + 2)
                    @(posedge clk_i);

                if (clk_o[gi] === 1'bx) begin

                    $error(
                        "[DIV_VALUE=%0d] FAIL: clk_o is X after reset release",
                        div_value
                    );

                    errors++;

                end
                else begin

                    $display(
                        "[DIV_VALUE=%0d] PASS: clk_o is known (%b)",
                        div_value,
                        clk_o[gi]
                    );

                end

                // ------------------------------------------------------------
                // Check 2:
                // Measure clk_o period.
                // ------------------------------------------------------------
                $display(
                    "[DIV_VALUE=%0d] Waiting for first clk_o edge...",
                    div_value
                );

                @(posedge clk_o[gi]);

                t_edge0 = $realtime;

                $display(
                    "[DIV_VALUE=%0d] First clk_o edge at %.2f ns",
                    div_value,
                    t_edge0
                );

                @(posedge clk_o[gi]);

                t_edge1 = $realtime;

                $display(
                    "[DIV_VALUE=%0d] Second clk_o edge at %.2f ns",
                    div_value,
                    t_edge1
                );

                measured_period = real'(t_edge1 - t_edge0);

                // ------------------------------------------------------------
                // Check measured period.
                // ------------------------------------------------------------
                if ((measured_period < (expected_period - tolerance)) ||
                    (measured_period > (expected_period + tolerance))) begin

                    $error(
                        "[DIV_VALUE=%0d] FAIL: expected period ~%.2f ns, measured %.2f ns",
                        div_value,
                        expected_period,
                        measured_period
                    );

                    errors++;

                end
                else begin

                    $display(
                        "[DIV_VALUE=%0d] PASS: period = %.2f ns (expected ~%.2f ns)",
                        div_value,
                        measured_period,
                        expected_period
                    );

                end

                // ------------------------------------------------------------
                // Mark this checker as complete.
                // ------------------------------------------------------------
                done_flags[gi] = 1'b1;

                $display(
                    "[DIV_VALUE=%0d] DONE",
                    div_value
                );

            end

        end
    endgenerate

    // ------------------------------------------------------------------------
    // Main test sequence
    // ------------------------------------------------------------------------
    initial begin

        $display("=========================================================");
        $display(" Testbench: tb_clk_div");
        $display(" Start time = %0t", $time);
        $display(
            " Running %0d DIV_VALUE configurations CONCURRENTLY",
            NUM_TESTS
        );
        $display("=========================================================");

        // --------------------------------------------------------------------
        // Waveform
        // --------------------------------------------------------------------
        $dumpfile("wf.fst");
        $dumpvars(0, tb_clk_div);

        // --------------------------------------------------------------------
        // Initialize completion flags.
        // --------------------------------------------------------------------
        for (int i = 0; i < NUM_TESTS; i++) begin
            done_flags[i] = 1'b0;
        end

        // --------------------------------------------------------------------
        // Reset
        // --------------------------------------------------------------------
        rst_ni = 1'b0;

        repeat (3)
            @(posedge clk_i);
        // Add latency for synchronizer by uncomment this #1;
        rst_ni = 1'b1;

        $display(
            "[TB] Reset released at %0t",
            $time
        );

        // --------------------------------------------------------------------
        // Wait for ALL parallel checkers.
        //
        // Reduction AND:
        //
        //   done_flags = 111111
        //
        // means all checkers are complete.
        // --------------------------------------------------------------------
        wait (&done_flags);

        // --------------------------------------------------------------------
        // Final result
        // --------------------------------------------------------------------
        $display("=========================================================");

        if (errors == 0) begin

            $display(" RESULT: ALL TESTS PASSED");

        end
        else begin

            $display(
                " RESULT: %0d TEST(S) FAILED",
                errors
            );

        end

        $display("=========================================================");

        $finish;

    end

    // ------------------------------------------------------------------------
    // Global safety timeout
    // ------------------------------------------------------------------------
    initial begin

        #(CLK_PERIOD * 2000);

        $display("");
        $display("=========================================================");
        $display(" ERROR: GLOBAL TIMEOUT");
        $display(" One or more checkers did not complete.");
        $display(" done_flags:");

        for (int i = 0; i < NUM_TESTS; i++) begin

            $display(
                "   DIV_VALUE=%0d : done=%b",
                DIV_VALUES[i],
                done_flags[i]
            );

        end

        $display("=========================================================");

        $finish;

    end

endmodule

