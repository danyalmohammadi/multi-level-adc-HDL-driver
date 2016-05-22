`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer:
//
// Create Date:   15:16:24 05/22/2016
// Design Name:   adc_fsm
// Module Name:   C:/Users/danyalmohammadi/Desktop/PhD/Research/FPGA_PROJECTS/Zedboard and Pmod/PMOD/MaximIntegratedADC/driver_HDL/santaFe_ADC_driver/tb_adc_fsm.v
// Project Name:  santaFe_ADC_driver
// Target Device:  
// Tool versions:  
// Description: 
//
// Verilog Test Fixture created by ISE for module: adc_fsm
//
// Dependencies:
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
////////////////////////////////////////////////////////////////////////////////

module tb_adc_fsm;

	// Inputs
	reg clk;
	reg rst;
	reg start_fsm;
	reg stop_sampling;
	reg DOUT;

	// Outputs
	wire samplingInProcess;
	wire configInProcess;
	wire CSnot;
	wire SCLK;
	wire SSTRB;
	wire DIN;
	wire [15:0] ADC_ValueCH1;
	wire [15:0] ADC_ValueCH2;
	wire [15:0] ADC_ValueCH3;
	wire sample_updated;

	// Instantiate the Unit Under Test (UUT)
	adc_fsm uut (
		.clk(clk), 
		.rst(rst), 
		.start_fsm(start_fsm), 
		.stop_sampling(stop_sampling), 
		.samplingInProcess(samplingInProcess), 
		.configInProcess(configInProcess), 
		.CSnot(CSnot), 
		.SCLK(SCLK), 
		.SSTRB(SSTRB), 
		.DIN(DIN), 
		.DOUT(DOUT), 
		.ADC_ValueCH1(ADC_ValueCH1), 
		.ADC_ValueCH2(ADC_ValueCH2), 
		.ADC_ValueCH3(ADC_ValueCH3), 
		.sample_updated(sample_updated)
	);

	 parameter PERIOD = 500;

   always begin
      clk = 1'b0;
      #(PERIOD/2) clk = 1'b1;
      #(PERIOD/2);
   end  
	
	
	initial begin
		// Initialize Inputs
		clk = 0;
		rst = 0;
		start_fsm = 0;
		stop_sampling = 0;
		DOUT = 0;

		// Wait 100 ns for global reset to finish
		#100;
        
		  
		start_fsm = 1;
		// Timing and 160 samples are random, it can be corrected  
  #50000;
	  repeat (160) begin
      @(negedge clk);
      #50 DOUT = $random;
   end
	
	
	
	end
      
endmodule

