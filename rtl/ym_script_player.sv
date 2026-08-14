module ym_script_player #(

	parameter ADDR_W  = 17,
	parameter TICK_CYC = 786576,
	parameter WR_GAP  = 64
)
(
	input                     clk_sys,
	input                     reset,
	output reg [ADDR_W-1:0]   rom_addr,
	output reg                rom_req,
	input                     rom_ready,
	input      [7:0]          rom_data,
	input                     cmd_stb,
	input      [7:0]          cmd,
	input                     cen,
	output reg                cs_n,
	output reg                wr_n,
	output reg                a0,
	output reg [7:0]          din,
	output                    music_active,
	output                    sfx_active
);

localparam HDR_INIT  = 32'h0000;
localparam HDR_TABLE = 32'h0008;
localparam [7:0] OP_TICK = 8'h00, OP_END = 8'h01, OP_LOOP = 8'h02,
                 OP_TICKS = 8'h03, OP_WRITE_LOW = 8'h04;
reg [19:0] tick_cnt = 20'd0;
wire       tick     = (tick_cnt == 20'd0);
always @(posedge clk_sys) begin
	tick_cnt <= (tick_cnt >= TICK_CYC-1) ? 20'd0 : tick_cnt + 20'd1;
end

reg [ADDR_W-1:0] resume_off = {ADDR_W{1'b0}};
reg              resume_ok  = 1'b0;
reg [ADDR_W-1:0] pc    [0:1];
reg [ADDR_W-1:0] pcs   [0:1];
reg [7:0]        wait_t[0:1];
reg [1:0]        run;
assign music_active = run[0];
assign sfx_active   = run[1];
wire [1:0] ready = run & ~{|wait_t[1], |wait_t[0]};
localparam S_IDLE     = 5'd0,
           S_CMD0     = 5'd1,  S_CMD0D = 5'd2,
           S_CMD1     = 5'd3,  S_CMD1D = 5'd4,
           S_CMD2     = 5'd5,  S_CMD2D = 5'd6,
           S_CMD3     = 5'd7,  S_CMD3D = 5'd8,
           S_CMDGO    = 5'd9,
           S_OP       = 5'd10, S_OPD   = 5'd11,
           S_ARG      = 5'd12, S_ARGD  = 5'd13,
           S_ARG2     = 5'd14, S_ARG2D = 5'd15,
           S_OPW      = 5'd22,
           S_WR_ADDR  = 5'd16, S_WR_AG = 5'd17, S_WR_AW = 5'd18,
           S_WR_DATA  = 5'd19, S_WR_DG = 5'd20, S_WR_DW = 5'd21;
reg [4:0]  st = S_IDLE;
reg        c  = 1'b0;
reg [7:0]  op, arg1, arg2;
reg [31:0] tbl;
reg [7:0]  cmd_l;
reg [6:0]  gap;
reg        cmd_pend = 1'b0;
reg [7:0]  cmd_pl;

always @(posedge clk_sys) begin
	if (reset) begin
		cmd_pend <= 1'b0;
	end else begin
		if (cmd_stb) begin
			cmd_pend <= 1'b1;
			cmd_pl   <= cmd;
		end else if (st == S_CMD0) begin
			cmd_pend <= 1'b0;
		end
	end
end

localparam [1:0] WR_HOLD = 2'd2;
reg [1:0] hold = 2'd0;

always @(posedge clk_sys) begin
	if (reset) begin
		st       <= S_IDLE;
		run       <= 2'b00;
		resume_ok <= 1'b0;
		cs_n     <= 1'b1;
		wr_n     <= 1'b1;
		a0       <= 1'b0;
		din      <= 8'd0;
		hold     <= 2'd0;
		gap      <= 7'd0;
		c        <= 1'b0;
		wait_t[0] <= 8'd0;
		wait_t[1] <= 8'd0;
		pc[0]    <= {ADDR_W{1'b0}};
		pc[1]    <= {ADDR_W{1'b0}};
		pcs[0]   <= {ADDR_W{1'b0}};
		pcs[1]   <= {ADDR_W{1'b0}};
		rom_addr <= HDR_INIT[ADDR_W-1:0];
		rom_req  <= 1'b0;
		tbl      <= 32'd0;
	end else begin

		if (tick) begin
			if (wait_t[0] != 8'd0) wait_t[0] <= wait_t[0] - 8'd1;
			if (wait_t[1] != 8'd0) wait_t[1] <= wait_t[1] - 8'd1;
		end

		case (st)

		S_IDLE: begin

			cmd_l    <= 8'hFF;
			tbl      <= 32'd0;
			st       <= S_CMD0;
			rom_addr <= HDR_INIT[ADDR_W-1:0];
			rom_req  <= ~rom_req;
		end

		S_CMD0:  begin st <= S_CMD0D; end
		S_CMD0D: if (rom_ready) begin tbl[7:0]   <= rom_data;
		               rom_addr <= rom_addr + 1'd1; rom_req <= ~rom_req;
		               st <= S_CMD1; end
		S_CMD1:  begin st <= S_CMD1D; end
		S_CMD1D: if (rom_ready) begin tbl[15:8]  <= rom_data;
		               rom_addr <= rom_addr + 1'd1; rom_req <= ~rom_req;
		               st <= S_CMD2; end
		S_CMD2:  begin st <= S_CMD2D; end
		S_CMD2D: if (rom_ready) begin tbl[23:16] <= rom_data;
		               rom_addr <= rom_addr + 1'd1; rom_req <= ~rom_req;
		               st <= S_CMD3; end
		S_CMD3:  begin st <= S_CMD3D; end
		S_CMD3D: if (rom_ready) begin tbl[31:24] <= rom_data; st <= S_CMDGO; end

		S_CMDGO: begin
			if (tbl[28:0] == 29'd0) begin
				if (tbl[30]) run <= 2'b00;
				st <= S_OP;
			end else begin
				if (tbl[30]) run <= 2'b00;
				pc [tbl[31]]     <= tbl[ADDR_W-1:0];
				pcs[tbl[31]]     <= tbl[ADDR_W-1:0];
				wait_t[tbl[31]]  <= 8'd0;
				run[tbl[31]]     <= 1'b1;
				if (!tbl[31] && tbl[29]) begin
					resume_off <= tbl[ADDR_W-1:0];
					resume_ok  <= 1'b1;
				end
				st <= S_OP;
			end
		end

		S_OP: begin
			cs_n <= 1'b1;
			wr_n <= 1'b1;
			if (cmd_pend) begin

				cmd_l    <= cmd_pl;
				tbl      <= 32'd0;
				rom_addr <= HDR_TABLE[ADDR_W-1:0] + {cmd_pl, 2'b00};
				rom_req  <= ~rom_req;
				st       <= S_CMD0;
			end else if (ready[c]) begin
				rom_addr <= pc[c];
				rom_req  <= ~rom_req;
				st       <= S_OPW;
			end else if (ready[~c]) begin
				c        <= ~c;
			end

		end

		S_OPW: begin st <= S_OPD; end

		S_OPD: if (rom_ready) begin
			op <= rom_data;
			case (rom_data)
			OP_END: begin
				if (c == 1'b0 && resume_ok) begin
					pc [0] <= resume_off;
					pcs[0] <= resume_off;
				end else begin
					run[c] <= 1'b0;
				end
				c  <= ~c;
				st <= S_OP;
			end
			OP_LOOP: begin
				pc[c] <= pcs[c];
				c     <= ~c;
				st    <= S_OP;
			end
			OP_TICK: begin
				pc[c]     <= pc[c] + 1'd1;
				wait_t[c] <= 8'd1;
				c         <= ~c;
				st        <= S_OP;
			end
			default: begin

				rom_addr <= pc[c] + 1'd1;
				rom_req  <= ~rom_req;
				st       <= S_ARG;
			end
			endcase
		end

		S_ARG:  begin st <= S_ARGD; end
		S_ARGD: if (rom_ready) begin
			arg1 <= rom_data;
			if (op == OP_TICKS) begin
				pc[c]     <= pc[c] + 2'd2;
				wait_t[c] <= rom_data;
				c         <= ~c;
				st        <= S_OP;
			end else if (op == OP_WRITE_LOW) begin
				rom_addr <= pc[c] + 2'd2;
				rom_req  <= ~rom_req;
				st       <= S_ARG2;
			end else begin

				pc[c] <= pc[c] + 2'd2;
				st    <= S_WR_ADDR;
			end
		end

		S_ARG2:  begin st <= S_ARG2D; end
		S_ARG2D: if (rom_ready) begin
			arg2  <= rom_data;
			pc[c] <= pc[c] + 2'd3;
			st    <= S_WR_ADDR;
		end

		S_WR_ADDR: begin
			if (cen) begin
				a0   <= 1'b0;
				din  <= (op == OP_WRITE_LOW) ? arg1 : op;
				cs_n <= 1'b0;
				wr_n <= 1'b0;
				hold <= WR_HOLD;
				st   <= S_WR_AG;
			end
		end
		S_WR_AG: begin
			if (cen) begin
				if (hold != 2'd0) begin
					hold <= hold - 2'd1;
				end else begin
					cs_n <= 1'b1;
					wr_n <= 1'b1;
					gap  <= WR_GAP[6:0];
					st   <= S_WR_AW;
				end
			end
		end
		S_WR_AW: begin
			if (cen) begin
				if (gap != 7'd0) gap <= gap - 7'd1;
				else             st  <= S_WR_DATA;
			end
		end
		S_WR_DATA: begin
			if (cen) begin
				a0   <= 1'b1;
				din  <= (op == OP_WRITE_LOW) ? arg2 : arg1;
				cs_n <= 1'b0;
				wr_n <= 1'b0;
				hold <= WR_HOLD;
				st   <= S_WR_DG;
			end
		end
		S_WR_DG: begin
			if (cen) begin
				if (hold != 2'd0) begin
					hold <= hold - 2'd1;
				end else begin
					cs_n <= 1'b1;
					wr_n <= 1'b1;
					gap  <= WR_GAP[6:0];
					st   <= S_WR_DW;
				end
			end
		end
		S_WR_DW: begin
			if (cen) begin
				if (gap != 7'd0) begin
					gap <= gap - 7'd1;
				end else begin
					c  <= ~c;
					st <= S_OP;
				end
			end
		end

		default: st <= S_OP;
		endcase
	end
end

endmodule
