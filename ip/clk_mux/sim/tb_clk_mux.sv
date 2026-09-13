`timescale 1ns/1ps

module tb_clk_mux;

    // --- Internal signals ---
    logic i_reset1;
    logic i_reset2;
    logic i_clk1;
    logic i_clk2;
    logic i_sel;
    logic o_clk;

    // --- Parameters for Clock Periods ---
    localparam CLK1_PERIOD = 10;  // 100 MHz
    localparam CLK2_PERIOD = 16;  // 62.5 MHz (Asynchronous to CLK1)

    // --- Device Under Test (DUT) ---
    clk_mux u_clk_mux (
        .i_reset1 (i_reset1),
        .i_reset2 (i_reset2),
        .i_clk1   (i_clk1),
        .i_clk2   (i_clk2),
        .i_sel    (i_sel),
        .o_clk    (o_clk)
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
        // 1. Initialize: Keep both domains in reset state
        i_reset1 = 0;
        i_reset2 = 0;
        i_sel    = 0;

        // 2. Staggered reset release
        #21;
        i_reset1 = 1;   // Release reset1 first
        
        #18; 
        i_reset2 = 1;   // Release reset2 18ns later

        // Let it run with i_clk1 (i_sel = 0)
        #150; // Tăng delay để bù trừ độ trễ qua synchronizer

        // 3. Switch to i_clk2 (i_sel = 1)
        #12;
        i_sel = 1;
        #200; // Tăng thời gian chạy để quan sát sau khi switch

        // 4. Test asserting reset1 while running on domain 2
        #15;
        i_reset1 = 0;   // Assert reset1 unexpectedly
        #23;
        i_reset1 = 1;   // Release reset1
        #150;

        // 5. Switch back to i_clk1 (i_sel = 0)
        #17;
        i_sel = 0;
        #200;

        // 6. Test asserting reset2 while running on domain 1
        #27;
        i_reset2 = 0;   // Assert reset2 unexpectedly
        #19;
        i_reset2 = 1;   // Release reset2

        #200;
        $display("Simulation Finished!");
        $finish;
    end

    // --- Waveform Dumping ---
    initial begin
        $dumpfile("tb_clk_mux.fst");
        $dumpvars(0, tb_clk_mux);
    end

endmodule
