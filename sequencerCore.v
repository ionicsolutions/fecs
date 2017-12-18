`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:        University of Cambridge, University of Bonn
// Engineer:       Tim Ballance, Kilian Kluge
// 
// Create Date:    2012
// Design Name: 
// Module Name:    sequencerCore
// Project Name:   IonCavity PulseSequencer
// Target Devices: XEM6001 (Xilinx Spartan 6)
// Tool versions:  
// Description:  	 The sequencerCore module handles the instruction RAM and
//					 controls the instruction parser.
//
// Dependencies:   
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module sequencerCore(
	input sys_clock,
	
	output [23:0] o_output_bus, // external and internal channels
	
	// control signals
	input i_trigger_sequence, // after this receives a positive edge, we start the sequence on the next sys_clk
	input i_stop_sequence, // when this is held high, the device should hold in reset mode
	output o_finished, // this is high after a sequence is finished
	
	// configuration
	input [31:0] i_shots, // Number of times to repeat the sequence - 1, sampled on negative edge i_write_mode
	input [31:0] i_idle_state, // Electronic state of the outputs which should be set when no sequence is running
	
	// FIFO
	input ti_clk, // from okHostInterface
	input [15:0] i_ep_data, // from okPipeIn
    input i_ep_write, // from okPipeIn
	input i_write_mode, // held high to set the device into programming mode, clears ram on positive edge

	// SPC access
	input [15:0] i_spc0_value, // Number of counts in the most recent time window of SPC channel 0
	input [15:0] i_spc1_value // Number of counts in the most recent time window of SPC channel 1
);

////////////////////////////////////////////////////////////
// Instruction RAM
////////////////////////////////////////////////////////////

/* RAM */
wire w_ram_clock;
assign w_ram_clock = sys_clock;

wire w_ram_write_enable;
wire [9:0] w_ram_address;
wire [9:0] w_ram_instruction_address;
reg [9:0] r_fifo_ram_address; 
assign w_ram_address = i_write_mode ? r_fifo_ram_address : w_ram_instruction_address;

wire [31:0] w_ram_data_in;
wire [31:0] w_ram_data_out;

ram myRam (
	.clka(w_ram_clock ),
	.wea(w_ram_write_enable), // Bus [0 : 0] 
	.addra(w_ram_address), // Bus [9 : 0] 
	.dina(w_ram_data_in), // Bus [31 : 0] 
	.douta(w_ram_data_out) // Bus [31 : 0]
);  

/* FIFO */
wire w_fifo_reset;
wire w_fifo_write_clock;
wire w_fifo_read_clock;
wire [15:0] w_fifo_data_in;
wire w_fifo_write_enable;
wire w_fifo_read_enable;
wire [31:0] w_fifo_data_out;
wire w_fifo_full;
wire w_fifo_empty;

// Switch the endianness of the data
assign w_ram_data_in[31:16] = w_fifo_data_out[15:0];
assign w_ram_data_in[15:0] = w_fifo_data_out[31:16];

// Write to FIFO (from OK interface)
assign w_fifo_data_in = i_ep_data;
assign w_fifo_write_clock = ti_clk & i_write_mode;
assign w_fifo_write_enable = i_ep_write & i_write_mode;
assign w_ram_write_enable = !w_fifo_empty;

// Read from FIFO (into RAM)
initial begin
	r_fifo_ram_address <= 0;
end

assign w_fifo_read_enable = !w_fifo_empty; // if fifo is not empty, read it out
assign w_fifo_read_clock = sys_clock;
assign w_fifo_reset = !i_write_mode;

always @(negedge sys_clock) begin
	if(w_fifo_read_enable == 1) begin
		r_fifo_ram_address <= r_fifo_ram_address + 1;
	end else if(i_write_mode == 0) begin
		r_fifo_ram_address <= 0;
	end
end

fifo myInputFifo (
	.rst(w_fifo_reset),
	.wr_clk(w_fifo_write_clock),
	.rd_clk(w_fifo_read_clock),
	.din(w_fifo_data_in), // Bus [15 : 0] 
	.wr_en(w_fifo_write_enable),
	.rd_en(w_fifo_read_enable),
	.dout(w_fifo_data_out), // Bus [31 : 0] 
	.full(w_fifo_full),
	.empty(w_fifo_empty)
);

////////////////////////////////////////////////////////////
// Sequencer (IPU)
////////////////////////////////////////////////////////////

/* SPC */

wire w_spc_id;
assign w_spc_id = w_ram_data_out[26];
wire [15:0] w_spc_value;
assign w_spc_value = w_spc_id ? i_spc1_value : i_spc0_value;

/* Instruction Parser */

wire w_stop_parsing;
assign w_stop_parsing = i_stop_sequence | i_write_mode;

reg [31:0] r_shots;
reg [31:0] r_idle_state;

initial begin
	r_shots <= 0;
	r_idle_state <= 0;
end

always @ (negedge i_write_mode) begin
	r_shots <= i_shots;
	r_idle_state <= i_idle_state;
end

instructionparser myInstructionParser (
	.sys_clock(sys_clock),
	.o_output_bus(o_output_bus),
	.o_ram_address(w_ram_instruction_address),
	.i_ram_data(w_ram_data_out),
	.i_spc_data(w_spc_value),
	.i_idle_state(r_idle_state[23:0]),
	.i_shots(r_shots),
	.i_trigger(i_trigger_sequence),
	.i_stop(w_stop_parsing),
	.o_finished(o_finished)
);

endmodule
