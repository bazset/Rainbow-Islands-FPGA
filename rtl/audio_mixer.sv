module audio_mixer
(
	input         clk_sys,
	input         reset,
	input  [15:0] ch0_l, ch0_r,
	input  [15:0] ch1_l, ch1_r,
	output [15:0] audio_l,
	output [15:0] audio_r
);

function [15:0] sat_add16(input signed [16:0] sum);
	begin
		if (sum > 17'sd32767)       sat_add16 = 16'sd32767;
		else if (sum < -17'sd32768) sat_add16 = -17'sd32768;
		else                        sat_add16 = sum[15:0];
	end
endfunction

wire signed [16:0] sum_l = $signed(ch0_l) + $signed(ch1_l);
wire signed [16:0] sum_r = $signed(ch0_r) + $signed(ch1_r);
reg [15:0] mix_l, mix_r;
always @(posedge clk_sys) begin
	if (reset) begin
		mix_l <= 0;
		mix_r <= 0;
	end else begin
		mix_l <= sat_add16(sum_l);
		mix_r <= sat_add16(sum_r);
	end
end

assign audio_l = mix_l;
assign audio_r = mix_r;

endmodule
