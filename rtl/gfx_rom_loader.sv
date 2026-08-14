module gfx_rom_loader #(parameter [24:1] BASE = 24'h000000,
                        parameter [24:0] SWAP_BELOW = 25'h000000)
(
	input             clk,
	input             reset,
	input             dl_en,
	input             dl_wr,
	input      [24:0] dl_addr,
	input       [7:0] dl_data,
	input             rd_req,
	input      [23:1] rd_addr,
	output            rd_ready,
	output     [15:0] rd_dout,
	input             rd_burst,
	output     [63:0] rd_dout4,
	output reg [24:1] sdram_addr,
	output reg        sdram_wrl,
	output reg        sdram_wrh,
	output reg [15:0] sdram_din,
	input      [15:0] sdram_dout,
	output reg        sdram_req,
	input             sdram_ack
);

wire swap_byte = (SWAP_BELOW != 25'd0) && (dl_addr < SWAP_BELOW);
reg rd_req_d;
always @(posedge clk) rd_req_d <= rd_req;
wire rd_req_edge = (rd_req != rd_req_d);
reg req_pending;
reg req_was_read;
reg        rd_want;
reg [23:1] rd_addr_l;
reg [1:0]  beat;
reg        burst_l;
reg        rd_done;

always @(posedge clk) begin
	if (reset) begin
		sdram_req    <= 1'b0;
		req_pending  <= 1'b0;
		req_was_read <= 1'b0;
		sdram_wrl    <= 1'b0;
		sdram_wrh    <= 1'b0;
		rd_want      <= 1'b0;
		beat         <= 2'd0;
		burst_l      <= 1'b0;
		rd_done      <= 1'b0;
	end else begin
		if (!req_pending) begin
			if (dl_en) begin
				if (dl_wr) begin
					sdram_addr   <= BASE + dl_addr[24:1];
					sdram_din    <= {dl_data, dl_data};

					sdram_wrh    <= swap_byte ?  dl_addr[0] : ~dl_addr[0];
					sdram_wrl    <= swap_byte ? ~dl_addr[0] :  dl_addr[0];
					sdram_req    <= ~sdram_req;
					req_pending  <= 1'b1;
					req_was_read <= 1'b0;
				end
			end else if (rd_want) begin
				sdram_addr   <= BASE + {1'b0, rd_addr_l} + {22'd0, beat};
				sdram_wrl    <= 1'b0;
				sdram_wrh    <= 1'b0;
				sdram_req    <= ~sdram_req;
				req_pending  <= 1'b1;
				req_was_read <= 1'b1;
				rd_want      <= 1'b0;
			end
		end else if (sdram_ack == sdram_req) begin
			req_pending <= 1'b0;
			if (req_was_read) begin
				if (burst_l && beat != 2'd3) begin

					beat    <= beat + 2'd1;
					rd_want <= 1'b1;
				end else begin
					rd_done <= 1'b1;
				end
			end
		end

		if (rd_req_edge) begin
			rd_want   <= 1'b1;
			rd_addr_l <= rd_addr;
			burst_l   <= rd_burst;
			beat      <= 2'd0;

			rd_done   <= 1'b0;
		end
	end
end

reg [15:0] rd_w0, rd_w1, rd_w2, rd_w3;
always @(posedge clk) begin
	if (req_was_read && req_pending && (sdram_ack == sdram_req)) begin
		case (beat)
			2'd0: rd_w0 <= sdram_dout;
			2'd1: rd_w1 <= sdram_dout;
			2'd2: rd_w2 <= sdram_dout;
			2'd3: rd_w3 <= sdram_dout;
		endcase
	end
end

assign rd_ready = rd_done;
assign rd_dout  = rd_w0;
assign rd_dout4 = {rd_w0, rd_w1, rd_w2, rd_w3};

endmodule
