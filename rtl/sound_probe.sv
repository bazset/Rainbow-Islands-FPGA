module sound_probe #(

	parameter [24:0] ROM_CNT = 25'h1C000,
	parameter [15:0] ROM_SUM = 16'h1180,
	parameter integer CLK_HZ = 48_000_000
)(
	input             clk_sys,
	input             reset,
	input             enable,
	input             rom_wr,
	input       [7:0] rom_data,
	input             trig_68k,
	input             trig_z80,
	input             trig_irq,
	output     [15:0] out
);

`define HALFP(hz) ((CLK_HZ) / ((hz) * 2))
`define MS(ms)    (((CLK_HZ) / 1000) * (ms))
reg [15:0] rom_sum = 16'd0;
reg [24:0] rom_cnt = 25'd0;

always @(posedge clk_sys) begin
	if (rom_wr) begin
		rom_sum <= rom_sum + {8'd0, rom_data};
		rom_cnt <= rom_cnt + 1'd1;
	end
end

wire rom_ok = (rom_cnt == ROM_CNT) && (rom_sum == ROM_SUM);
localparam integer RPT_HI   = `HALFP(1500);
localparam integer RPT_LO   = `HALFP(200);
localparam integer RPT_BEEP = `MS(100);
localparam integer RPT_GAP  = `MS(200);
localparam integer RPT_END2 = `MS(300);
localparam integer RPT_BUZZ = `MS(800);
localparam integer RPT_MUTE = `MS(1000);
localparam [25:0] RPT_IDLE = 26'h3FFFFFF;
reg        reset_d = 1'b1;
reg [25:0] rpt_t   = RPT_IDLE;
reg [16:0] rpt_div = 17'd0;
reg        rpt_sq  = 1'b0;

always @(posedge clk_sys) begin
	reset_d <= reset;
	if (reset_d && !reset)      rpt_t <= 26'd0;
	else if (rpt_t != RPT_IDLE) rpt_t <= rpt_t + 1'd1;
end

wire rpt_on = rom_ok ? ((rpt_t < RPT_BEEP) ||
                        (rpt_t >= RPT_GAP && rpt_t < RPT_END2))
                     :  (rpt_t < RPT_BUZZ);

wire [16:0] rpt_period = rom_ok ? RPT_HI[16:0] : RPT_LO[16:0];

always @(posedge clk_sys) begin
	if (rpt_on) begin
		if (rpt_div == 17'd0) begin rpt_div <= rpt_period; rpt_sq <= ~rpt_sq; end
		else                        rpt_div <= rpt_div - 1'd1;
	end else begin
		rpt_div <= 17'd0;
		rpt_sq  <= 1'b0;
	end
end

wire rpt_busy = (rpt_t < RPT_MUTE);
localparam integer ACT_HOLD = `MS(250);
reg [23:0] act_h [0:2];
reg [16:0] act_d [0:2];
reg  [2:0] act_q;
wire [2:0] act_trig = {trig_irq, trig_z80, trig_68k};
localparam integer ACT_P0 = `HALFP(400);
localparam integer ACT_P1 = `HALFP(1000);
localparam integer ACT_P2 = `HALFP(2500);

function automatic [16:0] act_period(input integer i);
	act_period = (i == 0) ? ACT_P0[16:0] :
	             (i == 1) ? ACT_P1[16:0] : ACT_P2[16:0];
endfunction

integer ai;
always @(posedge clk_sys) begin
	for (ai = 0; ai < 3; ai = ai + 1) begin
		if (reset) begin
			act_h[ai] <= 24'd0;
			act_d[ai] <= 17'd0;
			act_q[ai] <= 1'b0;
		end else begin
			if (act_trig[ai])            act_h[ai] <= ACT_HOLD[23:0];
			else if (act_h[ai] != 24'd0) act_h[ai] <= act_h[ai] - 1'd1;
			if (act_h[ai] != 24'd0) begin
				if (act_d[ai] == 17'd0) begin
					act_d[ai] <= act_period(ai);
					act_q[ai] <= ~act_q[ai];
				end else begin
					act_d[ai] <= act_d[ai] - 1'd1;
				end
			end else begin
				act_d[ai] <= 17'd0;
				act_q[ai] <= 1'b0;
			end
		end
	end
end

function automatic signed [15:0] tone(input on, input sq, input [15:0] amp);
	tone = on ? (sq ? $signed(amp) : -$signed(amp)) : 16'sd0;
endfunction

wire signed [15:0] mixed =
      tone(act_h[0] != 24'd0 && !rpt_busy, act_q[0], 16'd4000)
    + tone(act_h[1] != 24'd0 && !rpt_busy, act_q[1], 16'd4000)
    + tone(act_h[2] != 24'd0 && !rpt_busy, act_q[2], 16'd4000)
    + tone(rpt_on,                         rpt_sq,   16'd6000);

assign out = enable ? mixed : 16'sd0;

`undef HALFP
`undef MS

endmodule
