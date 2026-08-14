module sdram_arbiter #(parameter [24:1] BASE      = 24'h000000,
                       parameter [24:1] AUX_BASE  = 24'h180000,
                       parameter [24:1] VRAM_BASE = 24'h400000)
(
	input             clk,
	input             reset,
	input             dl_en,
	input             dl_wr,
	input      [24:0] dl_addr,
	input       [7:0] dl_data,
	input             cpu_sel,
	input      [23:1] cpu_addr,
	output            cpu_ready,
	output     [15:0] cpu_dout,
	input             aux_dl_en,
	input             aux_dl_wr,
	input      [24:0] aux_dl_addr,
	input       [7:0] aux_dl_data,
	input             aux_rd_req,
	input      [23:1] aux_rd_addr,
	output reg        aux_rd_ready,
	output reg [15:0] aux_rd_dout,
	input             vram_req,
	output reg        vram_ack,
	input      [18:1] vram_addr,
	input      [15:0] vram_din,
	output reg [15:0] vram_dout,
	input             vram_wrl,
	input             vram_wrh,
	output reg [24:1] sdram_addr,
	output reg        sdram_wrl,
	output reg        sdram_wrh,
	output reg [15:0] sdram_din,
	input      [15:0] sdram_dout,
	output reg        sdram_req,
	input             sdram_ack
);

reg cpu_sel_d;
always @(posedge clk) cpu_sel_d <= cpu_sel;
wire cpu_sel_rising = cpu_sel & ~cpu_sel_d;
reg req_pending;
reg req_was_cpu;
reg        cpu_want;
reg [23:1] cpu_addr_l;
reg        aux_want;
reg [23:1] aux_addr_l;
reg        aux_rd_req_d;
wire       aux_rd_rising = aux_rd_req & ~aux_rd_req_d;
reg        req_was_aux;
wire       vram_pending = (vram_req != vram_ack);
reg        req_was_vram;

always @(posedge clk) begin
	if (reset) begin
		sdram_req   <= 1'b0;
		req_pending <= 1'b0;
		req_was_cpu <= 1'b0;
		sdram_wrl   <= 1'b0;
		sdram_wrh   <= 1'b0;
		cpu_want    <= 1'b0;
		aux_want    <= 1'b0;
		req_was_aux <= 1'b0;
		aux_rd_ready<= 1'b0;
		aux_rd_req_d<= 1'b0;
		req_was_vram<= 1'b0;
		vram_ack    <= 1'b0;
	end else begin
		aux_rd_req_d <= aux_rd_req;
		aux_rd_ready <= 1'b0;
		if (!req_pending) begin
			if (dl_en) begin
				if (dl_wr) begin
					sdram_addr  <= BASE + dl_addr[24:1];
					sdram_din   <= {dl_data, dl_data};
					sdram_wrh   <= ~dl_addr[0];
					sdram_wrl   <=  dl_addr[0];
					sdram_req   <= ~sdram_req;
					req_pending <= 1'b1;
					req_was_cpu <= 1'b0;
					req_was_vram<= 1'b0;
				end
			end else if (aux_dl_en) begin
				if (aux_dl_wr) begin
					sdram_addr  <= AUX_BASE + aux_dl_addr[24:1];
					sdram_din   <= {aux_dl_data, aux_dl_data};
					sdram_wrh   <= ~aux_dl_addr[0];
					sdram_wrl   <=  aux_dl_addr[0];
					sdram_req   <= ~sdram_req;
					req_pending <= 1'b1;
					req_was_cpu <= 1'b0;
					req_was_aux <= 1'b0;
					req_was_vram<= 1'b0;
				end
			end else if (cpu_want) begin
				sdram_addr  <= BASE + {1'b0, cpu_addr_l};
				sdram_wrl   <= 1'b0;
				sdram_wrh   <= 1'b0;
				sdram_req   <= ~sdram_req;
				req_pending <= 1'b1;
				req_was_cpu <= 1'b1;
				req_was_aux <= 1'b0;
				req_was_vram<= 1'b0;
				cpu_want    <= 1'b0;
			end else if (vram_pending) begin

				sdram_addr  <= VRAM_BASE + {6'd0, vram_addr};
				sdram_din   <= vram_din;
				sdram_wrl   <= vram_wrl;
				sdram_wrh   <= vram_wrh;
				sdram_req   <= ~sdram_req;
				req_pending <= 1'b1;
				req_was_cpu <= 1'b0;
				req_was_aux <= 1'b0;
				req_was_vram<= 1'b1;
			end else if (aux_want) begin

				sdram_addr  <= AUX_BASE + {1'b0, aux_addr_l};
				sdram_wrl   <= 1'b0;
				sdram_wrh   <= 1'b0;
				sdram_req   <= ~sdram_req;
				req_pending <= 1'b1;
				req_was_cpu <= 1'b0;
				req_was_aux <= 1'b1;
				req_was_vram<= 1'b0;
				aux_want    <= 1'b0;
			end
		end else if (sdram_ack == sdram_req) begin
			req_pending <= 1'b0;
			if (req_was_aux) begin
				aux_rd_dout  <= sdram_dout;
				aux_rd_ready <= 1'b1;
			end
			if (req_was_vram) begin

				vram_dout <= sdram_dout;

				vram_ack  <= vram_req;
			end
		end

		if (cpu_sel_rising) begin
			cpu_want   <= 1'b1;
			cpu_addr_l <= cpu_addr;
		end
		if (aux_rd_rising) begin
			aux_want   <= 1'b1;
			aux_addr_l <= aux_rd_addr;
		end
	end
end

reg cpu_done;
always @(posedge clk) begin
	if (reset)                                       cpu_done <= 1'b0;
	else if (!cpu_sel)                               cpu_done <= 1'b0;
	else if (req_was_cpu && req_pending &&
	         (sdram_ack == sdram_req))               cpu_done <= 1'b1;
end

reg [15:0] cpu_data;
always @(posedge clk) begin
	if (req_was_cpu && req_pending && (sdram_ack == sdram_req))
		cpu_data <= sdram_dout;
end

assign cpu_ready = cpu_done;
assign cpu_dout  = cpu_data;

endmodule
