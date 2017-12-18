`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:        University of Bonn
// Engineer:       Kilian Kluge, Tim Ballance
// 
// Create Date:    2017
// Design Name: 
// Module Name:    instructionparser
// Project Name:   IonCavity PulseSequencer
// Target Devices: XEM6001 (Xilinx Spartan 6)
// Tool versions:  
// Description:    The instruction parser reads the compiled sequence
//						 from RAM, one instruction at a time. It then performs
//						 the desired command.
//
//						 This instruction parser was written as a replacement
//                 for the old parser written by Tim Ballance when it
//                 became apparent that the old implementation did not
//                 allow for inclusion of jumps while maintaining proper
//                 timing and behavior.
//
//                 The principle of operation is exactly the same, but
//                 this implementation exclusively uses non-blocking
//                 assignments in the sequential blocks. It also splits
//                 the module into three concurrent blocks, which are
//                 easier to understand, simulate, and debug.
//
// Dependencies: 
//
// Revision:
// Revision 0.01 - File Created 
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module instructionparser (
	input sys_clock, // 100 MHz clock
	
	output [23:0] o_output_bus, // external and internal channels
	
	// RAM access
	output [9:0] o_ram_address, // RAM address
	input [31:0] i_ram_data, // instruction data
	
	// SPC access
	input [15:0] i_spc_data, // SPC data
		
	// configuration
	input [23:0] i_idle_state, // output state while not running
	input [31:0] i_shots, // number of time the sequence is run
	
	// control signals
	input i_trigger, // trigger sequence run
	input i_stop, // when high, stop the parser
	output o_finished // high when parser is not running
);

/* PARSER CONTROL
If r_run goes high, the parser will start on the next
clock cycle.

If i_stop or r_stop goes high, the parser will stop on
the next clock cycle.
*/
reg r_run;
reg r_stop;

assign w_running = r_run && !i_stop && !r_stop;
assign o_finished = !w_running;

/* The module writes a 24-bit ouput register, which is mapped to
   internal and external outputs further up.
	
	While the parser is not running, the output bus is held in its
	idle state.
*/
reg [23:0] r_output;
assign o_output_bus = r_output;

/* The instructions are held as 32-bit values in the RAM and are
	retrieved through their 10-bit address (starting at 1).
*/
reg [9:0] r_address;
assign o_ram_address = r_address;

/* The last count value of the SPCs is retrieved through their
	1-bit address. This can be extended to give access to earlier
	count windows by modifying the sequencerCore module accordingly.
	
	The bits i_ram_data[28:26] are reserved for that purpose,
	currently we only use bit 26.
*/

reg [29:0] r_wait_counter;
reg [31:0] r_shot_counter;

initial begin
	r_run <= 0;
	r_stop <= 0;
	r_trigger <= 0;
	r_address <= 1;
	r_wait_counter <= 0;
	r_shot_counter <= 0;
	r_output <= i_idle_state;
end

/* ASYNCHRONOUS TRIGGER DETECTION

A positive edge on i_trigger sets r_trigger to high, which
is sampled by the parser control.
*/
reg r_trigger;

always @ (negedge sys_clock or posedge i_trigger) begin
	if (i_trigger == 1) begin
		r_trigger <= 1;
	end else begin
		r_trigger <= 0;
	end
end

/* PARSER

The command is in the upper two bits of the instruction data.
For details on this, see the (Py)FECS documentation.

*/
always @ (negedge sys_clock) begin

	/* PARSER CONTROL */

	if (w_running == 0) begin
		r_output <= i_idle_state;
		
		// reset the parser
		r_wait_counter <= 0;
		r_shot_counter <= 0;
		r_address <= 1;
		r_stop <= 0;
		
		// sample the trigger
		r_run <= r_trigger;
	end
	
	/* WAIT COUNTER DECREMENT

	Waiting periods are realized by counting down r_wait_counter.
	As long as r_wait_counter is above 0, the parser idles.
	
	For some reason this needs to be up here, if it is below the
	PARSER block, delays are infinite.
	*/

	if (r_wait_counter > 0) begin
		r_wait_counter <= r_wait_counter - 1;
	end
	
	
	/* PARSER */
	
	if (r_wait_counter == 0 && w_running == 1) begin
	
		casez (i_ram_data[31:29])
		
		3'b00?: // WAIT
		begin
			r_wait_counter <= i_ram_data[29:0];
			r_address <= r_address + 1;
		end
		
		3'b10?: // SET
		begin
			r_output <= i_ram_data[23:0];
			r_address <= r_address + 1;
		end
		
		3'b010: // THRESHOLD JUMP
		begin
		
			if (i_spc_data >= i_ram_data[25:10]) begin
				r_address <= i_ram_data[9:0];
			end else begin
				r_address <= r_address + 1;
			end
			
	   end 
		
		3'b011: // ALWAYS JUMP
		begin
			r_address <= i_ram_data[9:0];
		end
		
		default: // END
		begin
			r_address <= 1;
			if (r_shot_counter < i_shots) begin
				r_shot_counter <= r_shot_counter + 1;
			end else begin
				r_stop <= 1;
			end
		end
		
		endcase
	
	end

end

endmodule
