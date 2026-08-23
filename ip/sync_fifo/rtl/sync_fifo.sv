// ============================================================================
// Module      : sync_fifo
// Description : Synchronous single-clock FIFO
// Author      : Dat Tran <dat.trantan.business@gmail.com>
// ============================================================================ 
`timescale 1ns/1ps

module sync_fifo #(
    // Configurable Parameters
    parameter int unsigned DATA_WIDTH = 32, // Default Data Width
    parameter int unsigned DEPTH      =  8, // Default Fifo Depth, should be >= 2
    // Derived parameters
    localparam int unsigned PTR_WIDTH = $clog2(DEPTH),
    localparam int unsigned USG_WIDTH = $clog2(DEPTH+1)
)(
    input  logic                  clk_i,
    input  logic                  rst_ni,

    input  logic                  push_i,
    input  logic [DATA_WIDTH-1:0] data_i,
    
    input  logic                  pop_i,
    output logic [DATA_WIDTH-1:0] data_o,
   
    input  logic                  flush_i,
    output logic                  full_o,
    output logic                  empty_o,
    output logic [USG_WIDTH-1:0]  usage_o
);

    logic [DATA_WIDTH-1:0] mem_q [0:DEPTH-1];

    logic [PTR_WIDTH-1:0] write_ptr_q, write_ptr_d, read_ptr_q, read_ptr_d;
    logic [USG_WIDTH-1:0] usage_cnt_q, usage_cnt_d;

    //control signal
    logic push_en, pop_en;
    assign push_en = push_i && !full_o;  // write entry to queue when push_i = 1 and fifo is not full 
    assign pop_en  = pop_i  && !empty_o; // read show-ahead entry successful, increase pointer when pop_i = 1 and fifo is not empty

    always_comb begin
        //default assignment
	full_o      = (usage_cnt_q == USG_WIDTH'(DEPTH));
	empty_o     = (usage_cnt_q == '0);
	usage_o     = usage_cnt_q;
	data_o      = mem_q[read_ptr_q];
        write_ptr_d = write_ptr_q;
	read_ptr_d  = read_ptr_q;
	usage_cnt_d = usage_cnt_q;

	casez ({push_en,pop_en})
            2'b11: begin //both action happens, increase both pointer, remain usage
                write_ptr_d = (write_ptr_q == PTR_WIDTH'(DEPTH-1)) ? '0 : write_ptr_q + 1'b1;
		read_ptr_d  = (read_ptr_q  == PTR_WIDTH'(DEPTH-1)) ? '0 : read_ptr_q  + 1'b1;
	    end
	    2'b10: begin // new entry is pushed into queue, increase write pointer and usage
                write_ptr_d = (write_ptr_q == PTR_WIDTH'(DEPTH-1)) ? '0 : write_ptr_q + 1'b1;
		usage_cnt_d = usage_cnt_q + 1'b1;
	    end
	    2'b01: begin // show-ahead entry is consumed, increase read pointer and decrease usage
		read_ptr_d  = (read_ptr_q  == PTR_WIDTH'(DEPTH-1)) ? '0 : read_ptr_q  + 1'b1;
		usage_cnt_d = usage_cnt_q - 1'b1;
            end
	    2'b00: begin
                //no aciton
            end
	endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
	if (!rst_ni) begin
            write_ptr_q <= '0;
	    read_ptr_q  <= '0;
	    usage_cnt_q <= '0;
	end else if (flush_i) begin
            write_ptr_q <= '0;
            read_ptr_q  <= '0;
            usage_cnt_q <= '0;
        end else begin
            write_ptr_q <= write_ptr_d;
            read_ptr_q  <= read_ptr_d;
            usage_cnt_q <= usage_cnt_d;
	end
    end

    always_ff @(posedge clk_i) begin
        if (push_en) begin
            mem_q[write_ptr_q] <= data_i;
        end
    end

endmodule: sync_fifo
