module gfx_read_arbiter2
(
	input             clk,
	input             reset,
	input             a_req,
	input      [23:1] a_addr,
	output            a_ready,
	output     [15:0] a_dout,
	input             b_req,
	input      [23:1] b_addr,
	output            b_ready,
	output     [15:0] b_dout,
	output reg        req,
	output reg [23:1] addr,
	input             ready,
	input      [15:0] dout
);

reg a_req_d, b_req_d;
always @(posedge clk) begin
	a_req_d <= a_req;
	b_req_d <= b_req;
end
wire a_edge = (a_req != a_req_d);
wire b_edge = (b_req != b_req_d);
reg ready_d;
always @(posedge clk) ready_d <= ready;
wire ready_re = ready & ~ready_d;
reg servicing_a, servicing_b;
reg a_pending, b_pending;
reg a_want, b_want;
reg [23:1] a_addr_l, b_addr_l;
assign a_ready = ~a_pending;
assign b_ready = ~b_pending;

always @(posedge clk) begin
	if (reset) begin
		req <= 1'b0;
		servicing_a <= 1'b0;
		servicing_b <= 1'b0;
		a_pending   <= 1'b0;
		b_pending   <= 1'b0;
		a_want      <= 1'b0;
		b_want      <= 1'b0;
	end else begin

		if (a_edge) begin a_pending <= 1'b1; a_want <= 1'b1; a_addr_l <= a_addr; end
		if (b_edge) begin b_pending <= 1'b1; b_want <= 1'b1; b_addr_l <= b_addr; end
		if (!servicing_a && !servicing_b) begin
			if (a_want) begin
				addr <= a_addr_l;
				req  <= ~req;
				servicing_a <= 1'b1;
				a_want <= 1'b0;
			end else if (b_want) begin
				addr <= b_addr_l;
				req  <= ~req;
				servicing_b <= 1'b1;
				b_want <= 1'b0;
			end
		end else if (ready_re) begin
			if (servicing_a) a_pending <= 1'b0;
			if (servicing_b) b_pending <= 1'b0;
			servicing_a <= 1'b0;
			servicing_b <= 1'b0;
		end
	end
end

assign a_dout = dout;
assign b_dout = dout;

endmodule
