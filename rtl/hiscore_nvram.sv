`include "game_config.svh"

module hiscore_nvram #(
	parameter int GAME_ID = `GAME_RAINBOW,
	parameter [23:0] WORK_RAM_BASE = 24'h10C000,
	parameter [7:0]  NVRAM_INDEX   = 8'd2
)
(
	input             clk,
	input             reset,
	input             save_req,
	output            busy_load,
	output            busy_save,
	input             ioctl_download,
	input             ioctl_upload,
	input             ioctl_wr,
	input      [24:0] ioctl_addr,
	input       [7:0] ioctl_dout,
	output reg  [7:0] ioctl_din,
	input       [7:0] ioctl_index,
	output reg        ioctl_upload_req,
	input             wram_grant,
	output reg [12:0] wram_addr,
	output reg  [7:0] wram_wdata,
	output reg        wram_wr_hi,
	output reg        wram_wr_lo,
	input      [15:0] wram_rdata,
	output            restored
);

localparam [23:0] B0_BASE  = `CFG_HS_BLK0_BASE(GAME_ID);
localparam [15:0] B0_LEN   = `CFG_HS_BLK0_LEN(GAME_ID);
localparam  [7:0] B0_FIRST = `CFG_HS_BLK0_FIRST(GAME_ID);
localparam  [7:0] B0_LAST  = `CFG_HS_BLK0_LAST(GAME_ID);
localparam [23:0] B1_BASE  = `CFG_HS_BLK1_BASE(GAME_ID);
localparam [15:0] B1_LEN   = `CFG_HS_BLK1_LEN(GAME_ID);
localparam  [7:0] B1_FIRST = `CFG_HS_BLK1_FIRST(GAME_ID);
localparam  [7:0] B1_LAST  = `CFG_HS_BLK1_LAST(GAME_ID);
localparam [15:0] TOTAL    = `CFG_HS_TOTAL(GAME_ID);
localparam        HAS_B1   = (B1_LEN != 16'd0);
reg [7:0] nvram [0:63];

function automatic [23:0] byte_addr_of(input [15:0] off);
	return (off < B0_LEN) ? (B0_BASE + 24'(off))
	                      : (B1_BASE + 24'(off - B0_LEN));
endfunction

reg loaded;
always @(posedge clk) begin
	if (reset) loaded <= 1'b0;
	else if (ioctl_download && (ioctl_index == NVRAM_INDEX) && ioctl_wr) begin
		if (ioctl_addr < 25'(TOTAL)) nvram[ioctl_addr[5:0]] <= ioctl_dout;
		if (ioctl_addr == 25'(TOTAL - 16'd1)) loaded <= 1'b1;
	end
end

localparam S_WAIT     = 4'd0;
localparam S_CHK_ADDR = 4'd1;
localparam S_CHK_DATA = 4'd2;
localparam S_INJ_ADDR = 4'd3;
localparam S_INJ_DATA = 4'd4;
localparam S_IDLE     = 4'd5;
localparam S_SAVE     = 4'd6;
localparam S_WAIT_UP  = 4'd10;
localparam S_CHK_WAIT = 4'd11;
localparam S_INJ_WR   = 4'd13;
reg  [3:0] state;
reg [15:0] idx;
reg  [1:0] chk_i;
reg        restored_r;
reg [21:0] poll_div;
assign restored = restored_r;
wire [23:0] up_byte_addr = byte_addr_of(ioctl_addr[15:0]);
wire [12:0] up_word_idx  = (up_byte_addr - WORK_RAM_BASE) >> 1;

function automatic [15:0] chk_off(input [1:0] i);
	case (i)
		2'd0: return 16'd0;
		2'd1: return B0_LEN - 16'd1;
		2'd2: return HAS_B1 ? B0_LEN            : 16'd0;
		default: return HAS_B1 ? (TOTAL - 16'd1) : (B0_LEN - 16'd1);
	endcase
endfunction

function automatic [7:0] chk_val(input [1:0] i);
	case (i)
		2'd0: return B0_FIRST;
		2'd1: return B0_LAST;
		2'd2: return HAS_B1 ? B1_FIRST : B0_FIRST;
		default: return HAS_B1 ? B1_LAST : B0_LAST;
	endcase
endfunction

wire [23:0] cur_byte_addr = byte_addr_of((state == S_CHK_ADDR || state == S_CHK_WAIT ||
                                          state == S_CHK_DATA)
                                          ? chk_off(chk_i) : idx);
wire [12:0] cur_word_idx  = (cur_byte_addr - WORK_RAM_BASE) >> 1;
wire        cur_is_even   = ~cur_byte_addr[0];
wire  [7:0] cur_rd_byte   = cur_is_even ? wram_rdata[15:8] : wram_rdata[7:0];
reg  manual_pending;
reg  save_req_d;
assign busy_load = (state == S_CHK_ADDR) || (state == S_CHK_WAIT) ||
                   (state == S_CHK_DATA) || (state == S_INJ_ADDR) ||
                   (state == S_INJ_DATA) || (state == S_INJ_WR);

assign busy_save = manual_pending || (state == S_WAIT_UP) || (state == S_SAVE);

always @(posedge clk) save_req_d <= reset ? 1'b0 : save_req;

always @(posedge clk) begin
	if (reset) begin
		state            <= S_WAIT;
		idx              <= 16'd0;
		chk_i            <= 2'd0;
		manual_pending   <= 1'b0;
		restored_r       <= 1'b0;
		wram_wr_hi       <= 1'b0;
		wram_wr_lo       <= 1'b0;
		ioctl_upload_req <= 1'b0;
		poll_div         <= 22'd0;
	end else begin

		if (save_req && !save_req_d && restored_r) manual_pending <= 1'b1;

		case (state)
		S_WAIT: begin

			poll_div <= poll_div + 22'd1;

			if (&poll_div && loaded && !restored_r) begin
				chk_i <= 2'd0;
				state <= S_CHK_ADDR;
			end
		end

		S_CHK_ADDR: begin
			wram_addr <= cur_word_idx;
			state     <= S_CHK_WAIT;
		end

		S_CHK_WAIT: begin

			if (wram_grant) state <= S_CHK_DATA;
		end

		S_CHK_DATA: begin
			if (cur_rd_byte != chk_val(chk_i)) begin

				state <= S_WAIT;
			end else if (chk_i == 2'd3) begin
				idx   <= 16'd0;
				state <= S_INJ_ADDR;
			end else begin
				chk_i <= chk_i + 2'd1;
				state <= S_CHK_ADDR;
			end
		end

		S_INJ_ADDR: begin
			wram_addr  <= cur_word_idx;
			wram_wdata <= nvram[idx[5:0]];
			wram_wr_hi <=  cur_is_even;
			wram_wr_lo <= ~cur_is_even;
			state      <= S_INJ_WR;
		end

		S_INJ_WR: begin

			if (wram_grant) begin
				wram_wr_hi <= 1'b0;
				wram_wr_lo <= 1'b0;
				if (idx == TOTAL - 16'd1) begin
					restored_r <= 1'b1;
					state      <= S_IDLE;
				end else begin
					idx   <= idx + 16'd1;
					state <= S_INJ_ADDR;
				end
			end
		end

		S_IDLE: begin

			if (manual_pending) begin
				ioctl_upload_req <= 1'b1;
				manual_pending   <= 1'b0;
				state            <= S_WAIT_UP;
			end
		end

		S_WAIT_UP: begin
			if (ioctl_upload) begin
				ioctl_upload_req <= 1'b0;
				state            <= S_SAVE;
			end else if (!ioctl_upload_req) begin

				state <= S_IDLE;
			end
		end

		S_SAVE: begin
			if (!ioctl_upload) state <= S_IDLE;
		end

		default: state <= S_WAIT;
		endcase

		if (ioctl_upload) begin
			wram_addr <= up_word_idx;
			ioctl_din <= ~up_byte_addr[0] ? wram_rdata[15:8] : wram_rdata[7:0];
		end
	end
end

endmodule
