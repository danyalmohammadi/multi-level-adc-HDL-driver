`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 			Boise State University Power LAB Research
// Engineer: 			Danyal Mohammadi
// 
// Create Date:    	12:43:43 05/18/2016 
// Design Name: 		Maxim Integrated (Santa Fe Module) Multi-Channel ADC HDL Driver 	
// Module Name:    	FSM_CHANNELS 
// Project Name: 		Multi-Channel ADC HDL Driver 
// Target Devices: 	Any FPGA
// Tool versions: 	14.7 ISE
// Description: 		This module starts sampling at variable sampling rate (40KHz - 1KHz)
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////



//////////////////////////////////////////////////////////////////////////////////
// Datasheet summary:
//
//	sclk should be between 0.272 and 62 us, in this driver it is chosen to be 500ns
//	
//	This driver samples three ADC and updates its outputs at every 10 KHz
//	By changing the "counter" value in sampling_wait state
//
//////////////////////////////////////////////////////////////////////////////////







module adc_fsm ( clk, rst, start_fsm, stop_sampling, samplingInProcess, configInProcess, CSnot, SCLK, SSTRB, 
							DIN, DOUT, ADC_ValueCH1, ADC_ValueCH2, ADC_ValueCH3 , sample_updated  );

// --------------------------------
// -- input and output declaration
// --------------------------------

// -- input

input 										clk ;								// 2MHz clock input
input 										rst ;								// reset 
input 										start_fsm ;						// start configuration and after that start sampling
input 										stop_sampling ;				// stop sampling and exit from state machine
input 										DOUT ;							// serial value of ADC gets to master (MISO)

// -- outputs
output 		reg 						 	SSTRB;							// refer to MAX1301 data sheet
output 		reg 						 	DIN;								//	MOSI
output 			 						 	SCLK;								// slave clock input
output 			 						 	CSnot;							// chip select

output		reg							samplingInProcess = LOW;	// HIGH when sampling is in process
output		reg							configInProcess = LOW;		// HIGH when configuration is in process


output		reg	[15:0]				ADC_ValueCH1 = 16'd0;		// MISO value for channel 1
output		reg	[15:0]				ADC_ValueCH2 = 16'd0;		// MISO value for channel 2
output		reg	[15:0]				ADC_ValueCH3 = 16'd0;  		// MISO value for channel 3
output 										sample_updated;				// becomes HIGH every time new sample is captured


// -- these registers are used for temporary values of MISO

				reg	[15:0]				ADC_ValueCH1_temp = 16'd0;	// temp MISO value for channel 1
				reg	[15:0]				ADC_ValueCH2_temp = 16'd0;	// temp MISO value for channel 1
				reg	[15:0]				ADC_ValueCH3_temp = 16'd0; // temp MISO value for channel 1
 
// -- ADC configuration has 8-bits

/*
	--	ADC must be configured (only one time) to a desired voltage range before starting sampling. 
	-- Voltage range specifics are in the datasheet MAX1301 

	-- ADC (salve) configuration is done by DIN. (MOSI)

	-- MOSI selects channel and voltage range of the ADC (AFE)
------------------------------------------------------
DIN format is 
         
LOW- START BIT - C2 - C1 - C0 - DIF - R2 - R1 - R0 - LOW 

Start Bit is always 1

C2...C0 selects ADC channel 

DIF is always zero for non-differential voltages 

R2..R0 selects input voltage range

*/
											
				reg [7:0]	ChannelConfig					= 8'd0;
												
	
			
// ---------------------------------------------
// -- first 4 bit of the register ChannelConfig
// -- determines ADC channel
// -- LSB is sent first -> 4'b{c2,c1,c0,startbit}
// ---------------------------------------------


parameter ADC_channel0 = 4'b0001;
parameter ADC_channel1 = 4'b1001;
parameter ADC_channel2 = 4'b0101;



// ---------------------------------------------
// -- second 4 bit of the register ChannelConfig.
// -- determines ADC input voltage range.
// -- LSB is sent first -> 4'b{R2,R1,R0,DIF}.
// -- This will configure ADCs with voltage range
// -- of 0 to 6.1 volt (refer to MAX1301 datasheet)
// -- FSR = 3*Vref/2
// -- ( FSR*Vref/(2^16*4.096) )
// ---------------------------------------------
// --	for different voltage range the following 
// -- three parameters must be changed 
// ---------------------------------------------

parameter ADC_config0 = 4'b1100;													// since some bits are always zero, this creates some warning when synthesized as these are assigned to regs
parameter ADC_config1 = 4'b1100;
parameter ADC_config2 = 4'b1100;
 

// ---------------------------------------------
// -- 		concatenation
// ---------------------------------------------


parameter config_config_ADC0 = { ADC_config0 , ADC_channel0 };			// 8'b11000001;
parameter config_config_ADC1 = { ADC_config1 , ADC_channel1 };			// 8'b11001001;
parameter config_config_ADC2 = { ADC_config2 , ADC_channel2 };			// 8'b11000101;


// ------------------------------------------------
// -- 		concatenation
// -- During sampling: R2, R1, and R0 must be zero
// ------------------------------------------------


parameter config_sample_ADC0 = { 	4'd0 , ADC_channel0 };	 			// 8'b00000001;
parameter config_sample_ADC1 = {  	4'd0 , ADC_channel0 };	 			// 8'b00001001;
parameter config_sample_ADC2 = {  	4'd0 , ADC_channel0 };	 			// 8'b00000101; 

// ------------------------------------------------------------
// --	control register for starting configuration and sampling
// ------------------------------------------------------------
				reg 			start_transmit_config 		= LOW;											
				reg 			start_transmit_sampling 	= LOW;

			

// ------------------------------------------------------------
// --	used for initiation and control 
// ------------------------------------------------------------


	parameter	HIGH 			= 1'b1;
	parameter 	LOW 			= 1'b0;


// -------------------------------------------------------------------------
// --	done_config: control register for indicating config is done
// --	done_spi: control register is HIGH any package to slave is transmitted
// -------------------------------------------------------------------------

			reg done_config = LOW;
			reg done_spi = LOW;
					
					
					
// -----------------------------------------------------------------------
// --	Finite State Machine : TOP_FSM
// -- After IDLE state, it configures the ADCs before sampling starts
//	--------------------------------------------------------------	
//	-- "state" states : IDLE -> ADC configuration -> ADC sampling state
// -----------------------------------------------------------------------

	
   parameter 	state0 		= 2'b00;											// IDLE state
   parameter 	state1 		= 2'b01;											// configure state
   parameter 	state2 		= 2'b10;											// sampling state

   (* FSM_ENCODING="SEQUENTIAL", SAFE_IMPLEMENTATION="NO" *) reg [1:0] state = state0;

   always@(posedge clk)
      if (rst || stop_sampling) begin										// stop sampling if rst or stop_sampling is HIGH
         state <= state0;
         samplingInProcess <= LOW;
			configInProcess <= LOW;
      end
      else
         (* FULL_CASE, PARALLEL_CASE *) case (state)
            state0 : begin
               if (start_fsm)
                  state <= state1;
               else
               state <= state0;
               samplingInProcess <= LOW;
					configInProcess <= LOW;
            end
            state1 : begin														
               if (done_config)
                  state <= state2;
               else
                  state <= state1;
               samplingInProcess <= LOW;
					configInProcess <= HIGH;
            end
            state2 : begin														// Whole designs stays in this state unless stop_sampling signal is HIGH
               if (stop_sampling)
                  state <= state0;
               else
                  state <= state2;
               samplingInProcess <= HIGH;
					configInProcess <= LOW;
            end

         endcase
			
	
// -----------------------------------------------------------------------
// --	Finite State Machine : CONFIG_FSM
// -- has 3 states (3 ADC channel is being used)
// --	"config_state" gets changed when each ADC gets configured
//	-----------------------------------------------------------------------
//	-- "config_state" states : 
// -- IDLE -> ADC1 configured -> ADC2 configured ...
//	-- -> ADC3 configured -> make "done_config" signal HIGH ...
// -- (config_state == config_idle_
// ------------------------------------------------------------------------


			
   parameter config_state0 = 3'b000;												//IDLE state
   parameter config_ch1 	= 3'b001;
   parameter config_ch2 	= 3'b010;
   parameter config_ch3 	= 3'b011;
   parameter config_idle 	= 3'b100;												// make the "done_config" signal HIGH
 

  reg [2:0] config_state = config_state0;

   always@(posedge clk)
      if (rst || stop_sampling) begin
         config_state <= config_state0;
			done_config <= LOW;
      end
      else
 case (config_state)
            config_state0 : begin
               if (state==state1)													// configuration starts - from TOP_FSM
						begin
                  config_state <= config_ch1;
						start_transmit_config <= HIGH;
						ChannelConfig_config = config_config_ADC0;
						end
               else
                  begin
						config_state <= config_state0;
						start_transmit_config <= LOW;
						end
            end
            config_ch1 : begin
               if (done_spi)
                  begin
						config_state <= config_ch2;
						start_transmit_config <= HIGH;
						ChannelConfig_config = config_config_ADC1;
						end
               else
						begin
                  config_state <= config_ch1;
						done_config <= LOW;
						start_transmit_config <= LOW;
						end
            end
            config_ch2 : begin
               if (done_spi)
						begin
                  config_state <= config_ch3;
						start_transmit_config <= HIGH;		
						ChannelConfig_config = config_config_ADC2;						
						end
               else
						begin
                  config_state <= config_ch2;
						done_config <= LOW;
						start_transmit_config <= LOW;						
						end
            end
            config_ch3 : begin
               if (done_spi)
						begin
						config_state <= config_idle;
						done_config <= LOW;
						start_transmit_config <= LOW;

						end
               else
						begin
						config_state <= config_ch3;
						done_config <= LOW;
						start_transmit_config <= LOW;						
						end
            end
				 config_idle : 																		// configuration is done for 3 ADCs - prepare TOP_FSM for sampling
					begin
               	config_state <= config_idle;
						done_config <= HIGH;

					end
					
         endcase
							
			
// ---------------------------------------------------------------------------
// --	Finite State Machine : SAMPLING_FSM
// -- has 3 states (3 ADC channel is being used)
// --	"sampling_state" gets changed when each ADC gets sampled (MISO captured)
//	---------------------------------------------------------------------------
//	-- "sampling_state" states : 
// -- IDLE -> ADC1 sampled -> ADC2 sampled ...
//	-- -> ADC3 sampled -> go to "sampling_wait" state. In this state, FSM waits
// --	for some variable amount of clock cycle. 
// -- This allows to control slave sampling rate. -> start sampling again
// -- (config_state == config_idle_
// ----------------------------------------------------------------------------
						


   parameter sampling_state0 			= 3'b000;
   parameter sampling_ch1 				= 3'b001;
   parameter sampling_ch2 				= 3'b010;
   parameter sampling_ch3 				= 3'b011;
   parameter sampling_wait 			= 3'b100;										// In this state slave's sampling rate gets changed

 reg [2:0] sampling_state = sampling_state0;
	reg [9:0] counter = 10'd0;
   
	always@(posedge clk)
      if (rst || stop_sampling) begin
         sampling_state <= sampling_state0;
			start_transmit_sampling <= LOW;
			counter <= 7'd0;
      end
      else
         case (sampling_state)
            sampling_state0 : begin
               if (state==state2) 
						begin
                  sampling_state <= sampling_ch1;
						start_transmit_sampling <= HIGH;
						ChannelConfigSample = config_sample_ADC0;
						end
               else
						begin
                  sampling_state <= sampling_state0;
						start_transmit_sampling <= LOW;
						end
            end
            sampling_ch1 : begin
               if (done_spi)
                  begin
						sampling_state <= sampling_ch2;
						start_transmit_sampling <= HIGH;
						ChannelConfigSample = config_sample_ADC1;
						end
               else 
						begin
                  sampling_state <= sampling_ch1;
						start_transmit_sampling <= LOW;
						end
            end
            sampling_ch2 : begin
               if (done_spi)
                  begin
						sampling_state <= sampling_ch3;
						start_transmit_sampling <= HIGH;
						ChannelConfigSample = config_sample_ADC2;
						end
               else
                  begin
						sampling_state <= sampling_ch2;
						start_transmit_sampling <= LOW;
						end
            end
				sampling_ch3 : begin
               if (done_spi)
						begin
                  sampling_state <= sampling_wait;
						start_transmit_sampling <= LOW;
						end
               else
                  begin
						sampling_state <= sampling_ch3;
						start_transmit_sampling <= LOW;
						end
            end
// -------------------------------------------------------------------------------
// --  This state controls how often ADC output values must be updated
// -- The following calculation is done at cock input of 2 MHz (or 500 ns)
// --  3 ADCs' convertion time takes 54.5 us (or 109 clock cycle) 
// -- if desired sampling rate was 100 us (or 10KHz) which is 200 clock cycles
// -- This value must be 200 - 109 = 91. The counter starts from zero so 90.
// -------------------------------------------------------------------------------
				sampling_wait : begin
               if (counter == 10'd90)		// starts from 0														
						begin
                  sampling_state <= sampling_state0;
						counter <= 10'd0;
						start_transmit_sampling <= LOW;						
						end
               else
						begin
                  counter <= counter + 10'd1;
						sampling_state <= sampling_wait;
						start_transmit_sampling <= LOW;
						end
            end
         endcase

assign sample_updated = (counter == 10'd1)? HIGH : LOW;


// -------------------------------------------------------------------------------
// -- The following is done in order to change configuration value when the master 
// -- in configuration mode or sampling mode
// -------------------------------------------------------------------------------
	

 
reg [7:0] ChannelConfig_config = 8'd0;							
reg [7:0] ChannelConfigSample = 8'd0;							
							

 always @ (posedge clk)
 if (rst)
 ChannelConfig <= 8'd0;
 else if( start_transmit_config)
 ChannelConfig <= ChannelConfig_config;					// MOSI : ADC control register uses config register
 else
  ChannelConfig <= ChannelConfigSample;					// MOSI : ADC control register uses sampling register (R2...R0 regs are zero)
 
 
 
// ---------------------------------------------------------------------------
// --	Finite State Machine : SPI_FSM
// -- has 3 states 
// --	"state_adc"  gets changed according to the datasheet Figure 2
// -- makes chip select low -> sends config register to specify ADC channel #
//	-- MOSI clocked at positive edge and MISO clocked at negative edge 
// -- -> make chip select HIGH
// ----------------------------------------------------------------------------
  
										
 

	parameter state1_adc 		= 2'b00;
   parameter state2_adc 		= 2'b01;
   parameter state3_adc 		= 2'b10;
	
	
	
	parameter incr 		= 6'd1;
	reg 			[5:0] counter_adc = 6'd0;
	reg DIN_start = LOW;
	reg reg_sclk = LOW;
	reg reg_CSnot = HIGH;

  reg [1:0] state_adc = state1_adc;

   always@(posedge clk)
      if (rst) begin
         state_adc <= state1_adc;
			reg_sclk 	<= LOW;
			SSTRB <= LOW;
			done_spi <= LOW;
      end
      else
  case (state_adc)
            state1_adc : begin
               if (start_transmit_sampling || start_transmit_config)						// start transmitting : make chip select LOW
                  begin
						state_adc 		<= state2_adc;
						reg_sclk 	<= LOW;
						SSTRB 		<= LOW;
						DIN_start	<= LOW;
						done_spi <= LOW;
						end
               else
					begin
                  state_adc 		<= state1_adc;
						reg_sclk 	<= LOW;
						SSTRB 		<= LOW;
						DIN_start	<= LOW;
						done_spi <= LOW;
					end
            end
            state2_adc : begin
               if (counter_adc <  6'd32)
						begin
							if (counter_adc >= 6'd7)	
								begin
								DIN_start	<= LOW;
								end
							else 
								begin 
								DIN_start	<= HIGH;
								end
                  state_adc <= state2_adc;
						counter_adc <= counter_adc + incr;
						reg_sclk 	<= HIGH;
						SSTRB <= LOW;
						done_spi <= LOW;
						end
               else if (counter_adc == 6'd32)
                  begin
						state_adc <= state3_adc;
						reg_sclk 	<= LOW;
						SSTRB <= LOW;
						done_spi <= LOW;
						end


            end
            state3_adc : begin
						counter_adc <= 6'd0;
                  state_adc <= state1_adc;
						reg_sclk 	<= LOW;
						SSTRB <= LOW;
						done_spi <= HIGH;
            end

         endcase
						
// ---------------------------------------------------------------------------
// -- SPI output : clock and chip select
// ----------------------------------------------------------------------------


	assign CSnot = (state_adc == state1_adc || ( counter_adc == 6'd32 && reg_CSnot))? HIGH :LOW;
	assign SCLK = ( reg_sclk ) ? clk : LOW; 
	
	
// ---------------------------------------------------------------------------
// -- shift registers: parallel in and serial out  -- 8 bits for MOSI
// ----------------------------------------------------------------------------
	
	parameter piso_shift = 8;
   
   reg [piso_shift-2:0] reg_DIN = 7'd0;


   always @(negedge clk)
      if (state_adc == state2_adc && ~DIN_start && counter_adc == 6'd0) begin
         reg_DIN <= ChannelConfig[piso_shift-1:1];
         DIN    <= ChannelConfig[0];
      end
      else if (DIN_start) begin
         reg_DIN <= {1'b0, reg_DIN[piso_shift-2:1]};
         DIN   <= reg_DIN[0];
			end
		else if (state_adc == state2_adc)
			  begin
         DIN   <= LOW;
			end
		else
			DIN <= LOW;    
					
// ---------------------------------------------------------------------------
// -- shift registers: parallel in and serial out  -- 16 bits for MISO
// ----------------------------------------------------------------------------

				
    parameter shift = 16;
   
   reg [shift-1:0] reg_adc_value = 16'd0;
   
   always @(negedge clk)
	if (rst) begin
	reg_CSnot <= LOW;
	reg_adc_value <= 16'd0;
	end
	else if (counter_adc >= 6'd16 && counter_adc <= 6'd32 && (state_adc!=state3_adc) )
      begin
			if (counter_adc == 6'd32)
				begin
				reg_CSnot <= HIGH;
				end
			else
				begin
				reg_CSnot <= LOW;
				end
			reg_adc_value  <= { reg_adc_value[shift-2:0], DOUT};
		end
	else 
		begin
		reg_adc_value <= reg_adc_value;
		end

 

// ---------------------------------------------------------------------------
// -- synchronized outputs at every sampling cycle
// ----------------------------------------------------------------------------




always @ (posedge clk)
	if (rst) 
		begin 
		ADC_ValueCH1 	= 16'd0;
		ADC_ValueCH2	= 16'd0;
		ADC_ValueCH3	= 16'd0;
		end
	else if (sampling_state == sampling_ch1)
				ADC_ValueCH1_temp = reg_adc_value;
	else if (sampling_state == sampling_ch2)	
				ADC_ValueCH2_temp = reg_adc_value;	
	else if (sampling_state == sampling_ch3)				

				ADC_ValueCH3_temp = reg_adc_value;
	else if(sampling_state == sampling_wait)
				begin 
				ADC_ValueCH1 = ADC_ValueCH1_temp;
				ADC_ValueCH2 = ADC_ValueCH2_temp;
				ADC_ValueCH3 = ADC_ValueCH3_temp;
				end


 

//////////////////////////////////////////////////////////////////
// .xdc file (constraint file) for zedboard
//////////////////////////////////////////////////////////////////
//
/*


set_property PACKAGE_PIN T22 [get_ports configInProcess]
set_property PACKAGE_PIN T21 [get_ports samplingInProcess]
set_property IOSTANDARD LVCMOS33 [get_ports configInProcess]
set_property IOSTANDARD LVCMOS33 [get_ports samplingInProcess]



set_property PACKAGE_PIN W12 [get_ports CSnot]
set_property PACKAGE_PIN W11 [get_ports DIN]
set_property PACKAGE_PIN V10 [get_ports DOUT]
set_property PACKAGE_PIN W8 [get_ports SCLK]
set_property PACKAGE_PIN V8 [get_ports SSTRB]
set_property IOSTANDARD LVCMOS33 [get_ports SSTRB]
set_property IOSTANDARD LVCMOS33 [get_ports SCLK]
set_property IOSTANDARD LVCMOS33 [get_ports DOUT]
set_property IOSTANDARD LVCMOS33 [get_ports DIN]
set_property IOSTANDARD LVCMOS33 [get_ports CSnot]





set_property PACKAGE_PIN AB7 [get_ports sample_updated]
set_property IOSTANDARD LVCMOS33 [get_ports sample_updated]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk]
*/


endmodule
