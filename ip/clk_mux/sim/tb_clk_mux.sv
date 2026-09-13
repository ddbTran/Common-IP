`timescale 1ns/1ps

module tb_clk_mux;

    // --- Internal signals ---
    logic i_reset;
    logic i_clk1;
    logic i_clk2;
    logic i_sel;
    logic o_clk;

    // --- Parameters for Clock Periods ---
    localparam CLK1_PERIOD = 10;  //  100 MHz
    localparam CLK2_PERIOD = 16;  // 62.5 MHz (Asynchronous to CLK1)

    // --- Device Under Test (DUT) ---
    clk_mux u_clk_mux (
        .i_reset (i_reset),
        .i_clk1  (i_clk1),
        .i_clk2  (i_clk2),
        .i_sel   (i_sel),
        .o_clk   (o_clk)
    );

    // --- Clock Generation ---
    initial begin
        i_clk1 = 0;
        forever #(CLK1_PERIOD / 2.0) i_clk1 = ~i_clk1;
    end

    initial begin
        i_clk2 = 0;
        forever #(CLK2_PERIOD / 2.0) i_clk2 = ~i_clk2;
    end

    // --- Stimulus ---
    initial begin
        // 1. Initialize
        i_reset = 0;
        i_sel   = 0;
        
        // 2. Release reset after some time
        #25;
        i_reset = 1;
        
        // Let it run with i_clk1 (i_sel = 0)
        #50;

        // 3. Switch to i_clk2 (i_sel = 1)
        // Note: Switching at a random time to test glitch-free logic
        #12;
        i_sel = 1;
        
        // Let it run with i_clk2
        #100;

        // 4. Switch back to i_clk1 (i_sel = 0)
        #17;
        i_sel = 0;

        // Let it run with i_clk1
        #100;
        
        // 5. Another quick toggle just to stress test
        #13;
        i_sel = 1;
        #25;
        i_sel = 0;

        #100;
        $display("Simulation Finished!");
        $finish;
    end

    // --- Waveform Dumping (Optional but recommended) ---
    initial begin
        $dumpfile("tb_clk_mux.fst");
        $dumpvars(0, tb_clk_mux);
    end

endmodule
