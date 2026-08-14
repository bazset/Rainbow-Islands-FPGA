//============================================================================
// rbisland_top.sv
// Rainbow Islands (and sister boards) MiSTer core top-level.
//
// Wires 68000 + Z80/YM2151 (or script player), PC080SN layers, PC090OJ
// sprites, PC060HA CIU, C-chip, SDRAM loaders, and OSD helpers.
// GAME_ID selects address map / video quirks via game_config.svh.
//
// Video timing for this board family matches measured Taito PC080SN paths
// (same family as Rastan); pixel clock ~6.6715 MHz, ~59.83 Hz.
//============================================================================

`include "game_config.svh"

module rbisland_top #(

	parameter int GAME_ID = `GAME_RAINBOW,
	parameter bit SOUND_SCRIPTS = 1'b1,
	parameter bit SCRIPTS_EMBEDDED = 1'b1
)
(
	input         clk_sys,
	input         ce_8m,
	input         ce_4m,
	input         reset,
	input         reset_video,
	input         reset_dl,
	output reg    dbg_cpu_alive,
	output reg    dbg_ever_as,
	output reg    dbg_ever_dtack,
	output  [8:0] dbg_vpos,
	output  [8:0] dbg_hpos,
	output        dbg_unmapped,
	output  [7:0] dbg_unmapped_addr,
	output reg    dbg_pal_wr,
	output reg    dbg_tile_wr,
	output reg    dbg_spr_wr,
	output reg    dbg_cchip_acc,
	output reg    dbg_gfx_dl,
	output reg    dbg_gfx_nz,
	output reg    dbg_tilemap_nz,
	output reg    dbg_pal_nz,
	output reg    dbg_pix_nz,
	output reg    dbg_palword_nz,
	output reg    dbg_rgb_nz,
	output reg    dbg_vid_run,
	output reg    dbg_live_idx,
	output reg    dbg_live_word,
	output reg    dbg_live_rgb,
	output reg    dbg_live_lbw,
	output reg    dbg_bg_stuck,
	output reg    dbg_live_lbwnz,
	output reg    dbg_live_gfxnz,
	output reg    dbg_live_pxnz,
	output reg    dbg_live_attrnz,
	output reg    dbg_live_codenz,
	output reg [15:0] dbg_v_tile,
	output reg [15:0] dbg_v_gfx,
	output reg [15:0] dbg_v_palwr,
	output reg [15:0] dbg_v_palrd,
	output reg [15:0] dbg_v_pixidx,
	output reg [15:0] dbg_v_scroll,
	output reg [15:0] dbg_v_cnt,
	output reg [15:0] dbg_v_cchip,
	output reg [15:0] dbg_v_tilewr,
	output reg [15:0] dbg_v_palwrc,
	output reg [15:0] dbg_dl0,
	output reg [15:0] dbg_dl1,
	output reg [15:0] dbg_dl2,
	output reg [15:0] dbg_dl3,
	output reg [15:0] dbg_dl4,
	output reg [15:0] dbg_v_rom0,
	output reg [15:0] dbg_v_rom1,
	output reg [15:0] dbg_v_rom2,
	output reg [15:0] dbg_v_rom3,
	output reg [15:0] dbg_v_cpua,
	output reg [15:0] dbg_v_buscnt,
	output reg [15:0] dbg_v_asstuck,
	input  [15:0] joystick_0,
	input  [15:0] joystick_1,
	input         coin1,
	input         coin2,
	input         start1,
	input         start2,
	input         service,
	input         tilt,
	input   [7:0] dswa,
	input   [7:0] dswb,
	input        [1:0] layer_sel,
	input        [8:0] bg_vadj,
	input              bg_yneg,
	input              snd_test,
	input        [1:0] snd_diag,
	input              pause,
	input         ioctl_download,
	input         ioctl_wr,
	input  [24:0] ioctl_addr,
	input   [7:0] ioctl_dout,
	input   [7:0] ioctl_index,
	input         ioctl_upload,
	output  [7:0] ioctl_din,
	output        ioctl_upload_req,
	input         hs_save_req,
	output [24:1] sdram_addr,
	output [15:0] sdram_din,
	input  [15:0] sdram_dout,
	output        sdram_wrl,
	output        sdram_wrh,
	output        sdram_req,
	input         sdram_ack,
	output [24:1] gfx_addr,
	output [15:0] gfx_din,
	input  [15:0] gfx_dout,
	output        gfx_wrl,
	output        gfx_wrh,
	output        gfx_req,
	input         gfx_ack,
	output [24:1] obj_addr,
	output [15:0] obj_din,
	input  [15:0] obj_dout,
	output        obj_wrl,
	output        obj_wrh,
	output        obj_req,
	input         obj_ack,
	output        HBlank,
	output        VBlank,
	output        HSync,
	output        VSync,
	input         ce_pix,
	output  [7:0] R,
	output  [7:0] G,
	output  [7:0] B,
	output [15:0] audio_l,
	output [15:0] audio_r,
	output        dbg_cc_cs,
	output        dbg_cc_wr,
	output        dbg_cc_asic,
	output [10:0] dbg_cc_addr,
	output  [7:0] dbg_cc_wdata,
	output  [7:0] dbg_cc_rdata
);

wire [23:1] cpu_a;
wire [15:0] cpu_dout, cpu_din;
wire        cpu_as_n, cpu_rw, cpu_uds_n, cpu_lds_n, cpu_dtack_n;
reg cpu_as_n_d;
always @(posedge clk_sys) begin
	cpu_as_n_d <= cpu_as_n;
	if (reset) dbg_cpu_alive <= 1'b0;
	else if (cpu_as_n_d && !cpu_as_n) dbg_cpu_alive <= ~dbg_cpu_alive;
end

//------------------------------------------------------------------------
// ROM region map (single ioctl stream, split by address)
//------------------------------------------------------------------------
localparam [24:0] RGN_MAIN  = 25'h000000;
localparam [24:0] RGN_SND   = 25'h080000;
localparam [24:0] RGN_GFX   = 25'h09C000;
localparam [24:0] RGN_OBJ   = 25'h11C000;
localparam [24:0] RGN_CCHIP = 25'h1BC000;
localparam [24:0] RGN_YMS   = 25'h1BF000;
localparam [24:0] RGN_END   = 25'h1E7000;
localparam int YMS_BYTES = 163840;
localparam int YMS_AW    = 18;
localparam [24:1] SDR_MAIN = 24'h000000;
localparam [24:1] SDR_GFX  = 24'h080000;
localparam [24:1] SDR_OBJ  = 24'h100000;
localparam [24:1] SDR_YMS  = 24'h180000;
wire dl_rom = ioctl_download && (ioctl_index == 8'd0);
wire dl_main  = dl_rom && (ioctl_addr >= RGN_MAIN ) && (ioctl_addr < RGN_SND  );
wire dl_snd   = dl_rom && (ioctl_addr >= RGN_SND  ) && (ioctl_addr < RGN_GFX  );
wire dl_gfx   = dl_rom && (ioctl_addr >= RGN_GFX  ) && (ioctl_addr < RGN_OBJ  );
wire dl_obj   = dl_rom && (ioctl_addr >= RGN_OBJ  ) && (ioctl_addr < RGN_CCHIP);
wire dl_cchip = dl_rom && (ioctl_addr >= RGN_CCHIP) && (ioctl_addr < RGN_YMS  );
wire dl_yms   = dl_rom && (ioctl_addr >= RGN_YMS  ) && (ioctl_addr < RGN_END  );
wire [24:0] dl_a_main  = ioctl_addr - RGN_MAIN;
wire [24:0] dl_a_snd   = ioctl_addr - RGN_SND;
wire [24:0] dl_a_gfx   = ioctl_addr - RGN_GFX;
wire [24:0] dl_a_obj   = ioctl_addr - RGN_OBJ;
wire [24:0] dl_a_cchip = ioctl_addr - RGN_CCHIP;
wire [24:0] dl_a_yms   = ioctl_addr - RGN_YMS;
reg [23:0] dl_b0=0, dl_b1=0, dl_b2=0, dl_b3=0, dl_b4=0;
wire [1:0] ym_rom_bank;
wire        cpu_ce_r, cpu_ce_f;
reg vblank_d;
always @(posedge clk_sys) vblank_d <= VBlank;
wire vblank_irq_pulse = VBlank & ~vblank_d;

//------------------------------------------------------------------------
// 68000 main CPU (FX68K via cpu68k_wrapper)
//------------------------------------------------------------------------
cpu68k_wrapper cpu
(
	.clk_sys     (clk_sys),
	.reset       (reset),
	.cpu_a       (cpu_a),
	.cpu_din     (cpu_din),
	.cpu_dout    (cpu_dout),
	.cpu_as_n    (cpu_as_n),
	.cpu_rw      (cpu_rw),
	.cpu_uds_n   (cpu_uds_n),
	.cpu_lds_n   (cpu_lds_n),
	.cpu_dtack_n (cpu_dtack_n),
	.vblank_irq  (vblank_irq_pulse),
	.pause       (pause),
	.cpu_ce_r    (cpu_ce_r),
	.cpu_ce_f    (cpu_ce_f)
);

wire [15:0] z80_a;
wire  [7:0] z80_dout, z80_din;
wire        z80_wr_n, z80_rd_n, z80_mreq_n, z80_iorq_n;
wire        z80_ce;
wire z80_int_req;
wire z80_nmi_req;
wire z80_reset_req;
wire        z80_rom_cs;
wire [16:0] z80_rom_addr;
wire        z80_ram_cs, z80_ram_we;
wire        z80_ym_reg_cs, z80_ym_data_cs;
wire        z80_ciu_port_cs, z80_ciu_comm_cs, z80_ciu_wr, z80_ciu_rd;
wire  [7:0] z80_rom_dout, z80_ram_dout, z80_ym_dout, z80_ciu_comm_din;
generate
if (!SOUND_SCRIPTS) begin : gen_z80

//------------------------------------------------------------------------
// Z80 sound CPU (T80) 
//------------------------------------------------------------------------
	z80_sound_wrapper z80_cpu
	(
		.clk_sys       (clk_sys),
		.reset         (reset),
		.cpu_a         (z80_a),
		.cpu_din       (z80_din),
		.cpu_dout      (z80_dout),
		.cpu_mreq_n    (z80_mreq_n),
		.cpu_iorq_n    (z80_iorq_n),
		.cpu_rd_n      (z80_rd_n),
		.cpu_wr_n      (z80_wr_n),
		.int_req       (z80_int_req),
		.nmi_req       (z80_nmi_req),
		.cpu_reset_req (z80_reset_req),
		.pause         (pause),
		.cpu_ce        (z80_ce)
	);

//------------------------------------------------------------------------
// Z80 address decoder + sound work RAM / ROM
//------------------------------------------------------------------------
	z80_bus_decoder z80_bus
	(
		.clk         (clk_sys),
		.reset       (reset),
		.cpu_a       (z80_a),
		.cpu_mreq_n  (z80_mreq_n),
		.cpu_iorq_n  (z80_iorq_n),
		.cpu_rd_n    (z80_rd_n),
		.cpu_wr_n    (z80_wr_n),
		.cpu_dout    (z80_dout),
		.cpu_din     (z80_din),
		.rom_cs      (z80_rom_cs),
		.rom_addr    (z80_rom_addr),
		.rom_dout    (z80_rom_dout),
		.ram_cs      (z80_ram_cs),
		.ram_we      (z80_ram_we),
		.ram_dout    (z80_ram_dout),
		.ym_reg_cs   (z80_ym_reg_cs),
		.ym_data_cs  (z80_ym_data_cs),
		.ym_dout     (z80_ym_dout),
		.ciu_port_cs (z80_ciu_port_cs),
		.ciu_comm_cs (z80_ciu_comm_cs),
		.ciu_wr      (z80_ciu_wr),
		.ciu_rd      (z80_ciu_rd),
		.ciu_comm_din(z80_ciu_comm_din),
		.rom_bank    (ym_rom_bank)
	);

	reg [7:0] z80_rom_mem [0:'h1BFFF];
	always @(posedge clk_sys) begin
		if (dl_snd && ioctl_wr)
			z80_rom_mem[dl_a_snd[16:0]] <= ioctl_dout;
	end

	reg [7:0] z80_rom_dout_r;
	always @(posedge clk_sys) z80_rom_dout_r <= z80_rom_mem[z80_rom_addr];
	assign z80_rom_dout = z80_rom_dout_r;
	reg [7:0] z80_ram_mem [0:4095];
	reg [7:0] z80_ram_dout_r;
	always @(posedge clk_sys) begin
		if (z80_ram_cs && z80_ram_we) z80_ram_mem[z80_a[11:0]] <= z80_dout;
		z80_ram_dout_r <= z80_ram_mem[z80_a[11:0]];
	end
	assign z80_ram_dout = z80_ram_dout_r;

end else begin : gen_no_z80

	assign z80_a           = 16'd0;
	assign z80_dout        = 8'd0;
	assign z80_mreq_n      = 1'b1;
	assign z80_iorq_n      = 1'b1;
	assign z80_rd_n        = 1'b1;
	assign z80_wr_n        = 1'b1;
	assign z80_ce          = 1'b0;
	assign z80_rom_cs      = 1'b0;
	assign z80_rom_addr    = 17'd0;
	assign z80_rom_dout    = 8'd0;
	assign z80_ram_cs      = 1'b0;
	assign z80_ram_we      = 1'b0;
	assign z80_ram_dout    = 8'd0;
	assign z80_ym_reg_cs   = 1'b0;
	assign z80_ym_data_cs  = 1'b0;
	assign z80_ciu_port_cs = 1'b0;
	assign z80_ciu_comm_cs = 1'b0;
	assign z80_ciu_wr      = 1'b0;
	assign z80_ciu_rd      = 1'b0;
	assign z80_din         = 8'd0;

end
endgenerate
wire       scr_cs_n, scr_wr_n, scr_a0;
wire [7:0] scr_din;
wire       scr_music_active, scr_sfx_active;
wire       ym_cen;
wire       ciu_cmd_stb;
wire [7:0] ciu_cmd_byte;
generate
if (SOUND_SCRIPTS) begin : gen_scripts

//------------------------------------------------------------------------
// YM2151 script player 
//------------------------------------------------------------------------
	ym_script_player #(.ADDR_W(YMS_AW)) player
	(
		.clk_sys  (clk_sys),
		.reset    (reset | ioctl_download),
		.rom_addr (yms_addr),
		.rom_req  (yms_req),
		.rom_ready(yms_ready),
		.rom_data (yms_dout),
		.cmd_stb  (ciu_cmd_stb),
		.cmd      (ciu_cmd_byte),
		.cen      (ym_cen),
		.cs_n     (scr_cs_n),
		.wr_n     (scr_wr_n),
		.a0       (scr_a0),
		.din      (scr_din),
		.music_active (scr_music_active),
		.sfx_active   (scr_sfx_active)
	);

end else begin : gen_no_scripts

	assign scr_cs_n         = 1'b1;
	assign scr_wr_n         = 1'b1;
	assign scr_a0           = 1'b0;
	assign scr_din          = 8'd0;
	assign scr_music_active = 1'b0;
	assign scr_sfx_active   = 1'b0;

end
endgenerate
wire signed [15:0] ym_audio_l, ym_audio_r;
generate
if (`CFG_HAS_YM2203(GAME_ID)) begin : gen_ym2203

//------------------------------------------------------------------------
// YM2203 (Volfied)
//------------------------------------------------------------------------
	ym2203_wrapper ym2203
	(
		.clk_sys   (clk_sys),
		.reset     (reset),
		.ym_reg_cs  (z80_ym_reg_cs),
		.ym_data_cs (z80_ym_data_cs),
		.cpu_wr_n   (z80_wr_n),
		.din        (z80_dout),
		.dout       (z80_ym_dout),
		.irq_req    (z80_int_req),
		.dswa       (dswa),
		.dswb       (dswb),
		.pause      (pause),
		.cen_o      (ym_cen),
		.audio_l    (ym_audio_l),
		.audio_r    (ym_audio_r)
	);

	assign ym_rom_bank = 2'b00;

end else begin : gen_ym2151

//------------------------------------------------------------------------
// YM2151 (Rainbow Islands / Rastan)
//------------------------------------------------------------------------
	ym2151_wrapper ym2151
	(
		.clk_sys   (clk_sys),
		.reset     (reset),
		.ym_reg_cs  (z80_ym_reg_cs),
		.ym_data_cs (z80_ym_data_cs),
		.cpu_wr_n   (z80_wr_n),
		.din        (z80_dout),
		.dout       (z80_ym_dout),
		.irq_req    (z80_int_req),
		.rom_bank   (ym_rom_bank),
		.snd_test   (snd_test),
		.pause      (pause),
		.scr_en     (SOUND_SCRIPTS),
		.scr_cs_n   (scr_cs_n),
		.scr_wr_n   (scr_wr_n),
		.scr_a0     (scr_a0),
		.scr_din    (scr_din),
		.cen_o      (ym_cen),
		.audio_l (ym_audio_l),
		.audio_r (ym_audio_r)
	);

end
endgenerate
wire        rom_cs;
wire [15:0] rom_dout;
wire        rom_ready;
wire [YMS_AW-1:0] yms_addr;
wire              yms_req;
wire              yms_ready;
wire [7:0]        yms_dout;
reg yms_req_d;
always @(posedge clk_sys) yms_req_d <= yms_req;
wire yms_req_edge = yms_req ^ yms_req_d;
wire        yms_sd_ready;
wire [15:0] yms_sd_dout;
generate
if (SCRIPTS_EMBEDDED) begin : gen_yms_bram

	(* ramstyle = "M10K" *) reg [7:0] yms_mem [0:YMS_BYTES-1];
	initial $readmemh("sound/rbisland_ym.hex", yms_mem);

	reg [7:0] bram_dout;
	reg       bram_ready;
	always @(posedge clk_sys) begin
		bram_dout  <= yms_mem[yms_addr];

		bram_ready <= yms_req_edge;
	end

	assign yms_dout  = bram_dout;
	assign yms_ready = bram_ready;

end else begin : gen_yms_sdram

	reg  [7:0] sd_byte;
	reg        sd_ready;
	reg        yms_byte_sel;

	always @(posedge clk_sys) begin
		sd_ready <= 1'b0;
		if (yms_sd_ready) begin

			sd_byte  <= yms_byte_sel ? yms_sd_dout[7:0] : yms_sd_dout[15:8];
			sd_ready <= 1'b1;
		end
	end
	always @(posedge clk_sys) if (yms_req_edge) yms_byte_sel <= yms_addr[0];

	assign yms_dout  = sd_byte;
	assign yms_ready = sd_ready;

end
endgenerate
wire yms_sd_req = SCRIPTS_EMBEDDED ? 1'b0 : yms_req;

//------------------------------------------------------------------------
// Program ROM arbiter (SDRAM port 0)
//------------------------------------------------------------------------
sdram_arbiter #(.BASE(SDR_MAIN), .AUX_BASE(SDR_YMS)) rom_arbiter
(
	.clk   (clk_sys),
	.reset (reset_dl),
	.dl_en   (dl_main),
	.dl_wr   (ioctl_wr),
	.dl_addr (dl_a_main),
	.dl_data (ioctl_dout),
	.aux_dl_en   (dl_yms),
	.aux_dl_wr   (ioctl_wr),
	.aux_dl_addr (dl_a_yms),
	.aux_dl_data (ioctl_dout),
	.aux_rd_req  (yms_sd_req),
	.aux_rd_addr ({{(24-YMS_AW){1'b0}}, yms_addr[YMS_AW-1:1]}),
	.aux_rd_ready(yms_sd_ready),
	.aux_rd_dout (yms_sd_dout),
	.cpu_sel   (rom_cs),
	.cpu_addr  (cpu_a),
	.cpu_ready (rom_ready),
	.cpu_dout  (rom_dout),
	.vram_req  (1'b0),
	.vram_ack  (),
	.vram_addr (18'd0),
	.vram_din  (16'd0),
	.vram_dout (),
	.vram_wrl  (1'b0),
	.vram_wrh  (1'b0),
	.sdram_addr (sdram_addr),
	.sdram_wrl  (sdram_wrl),
	.sdram_wrh  (sdram_wrh),
	.sdram_din  (sdram_din),
	.sdram_dout (sdram_dout),
	.sdram_req  (sdram_req),
	.sdram_ack  (sdram_ack)
);

wire        gfx_rd_req, obj_rd_req;
wire [23:1] gfx_rd_addr, obj_rd_addr;
wire        gfx_rd_ready, obj_rd_ready;
wire [15:0] gfx_rd_dout, obj_rd_dout;
wire        obj_rd_burst;
wire [63:0] obj_rd_dout4;

//------------------------------------------------------------------------
// Tile GFX ROM loader (SDRAM port 1)
//------------------------------------------------------------------------
gfx_rom_loader #(.BASE(SDR_GFX), .SWAP_BELOW(25'h80000)) gfx_loader
(
	.clk   (clk_sys),
	.reset (reset_dl),
	.dl_en   (dl_gfx),
	.dl_wr   (ioctl_wr),
	.dl_addr (dl_a_gfx),
	.dl_data (ioctl_dout),
	.rd_req   (gfx_rd_req),
	.rd_addr  (gfx_rd_addr),
	.rd_ready (gfx_rd_ready),
	.rd_dout  (gfx_rd_dout),
	.rd_burst (1'b0),
	.rd_dout4 (),
	.sdram_addr (gfx_addr),
	.sdram_wrl  (gfx_wrl),
	.sdram_wrh  (gfx_wrh),
	.sdram_din  (gfx_din),
	.sdram_dout (gfx_dout),
	.sdram_req  (gfx_req),
	.sdram_ack  (gfx_ack)
);

//------------------------------------------------------------------------
// Sprite GFX ROM loader (SDRAM port 2)
//------------------------------------------------------------------------
gfx_rom_loader #(.BASE(SDR_OBJ), .SWAP_BELOW(25'h80000)) obj_loader
(
	.clk   (clk_sys),
	.reset (reset_dl),
	.dl_en   (dl_obj),
	.dl_wr   (ioctl_wr),
	.dl_addr (dl_a_obj),
	.dl_data (ioctl_dout),
	.rd_req   (obj_rd_req),
	.rd_addr  (obj_rd_addr),
	.rd_ready (obj_rd_ready),
	.rd_dout  (obj_rd_dout),
	.rd_burst (obj_rd_burst),
	.rd_dout4 (obj_rd_dout4),
	.sdram_addr (obj_addr),
	.sdram_wrl  (obj_wrl),
	.sdram_wrh  (obj_wrh),
	.sdram_din  (obj_din),
	.sdram_dout (obj_dout),
	.sdram_req  (obj_req),
	.sdram_ack  (obj_ack)
);

wire work_ram_cs, work_ram_we;
wire ext_ram_cs, ext_ram_we;
wire palette_cs, palette_we;
wire tilemap_cs, tilemap_we;
wire sprite_ram_cs, sprite_ram_we;
wire sprite_ctrl_cs;
wire dswa_cs, dswb_cs;
wire watchdog_cs;
wire yscroll_cs, xscroll_cs, vcu_ctrl_cs;
wire ciu_port_cs, ciu_comm_cs, ciu_wr, ciu_rd;
wire cchip_mem_cs, cchip_asic_cs, cchip_wr;
wire [15:0] work_ram_dout, ext_ram_dout, palette_dout, tilemap_dout, sprite_ram_dout;
wire [15:0] dswa_din, dswb_din;
wire  [7:0] ciu_comm_din, cchip_din;

//------------------------------------------------------------------------
// 68000 bus decoder
//------------------------------------------------------------------------
rbisland_bus_decoder #(.GAME_ID(GAME_ID)) bus_decoder
(
	.clk         (clk_sys),
	.reset       (reset),
	.cpu_a       (cpu_a),
	.cpu_as_n    (cpu_as_n),
	.cpu_rw      (cpu_rw),
	.cpu_uds_n   (cpu_uds_n),
	.cpu_lds_n   (cpu_lds_n),
	.cpu_dtack_n (cpu_dtack_n),
	.dbg_unmapped      (dbg_unmapped),
	.dbg_unmapped_addr (dbg_unmapped_addr),
	.cpu_dout    (cpu_dout),
	.cpu_din     (cpu_din),
	.rom_cs      (rom_cs),
	.rom_dout    (rom_dout),
	.rom_ready   (rom_ready),
	.work_ram_cs (work_ram_cs), .work_ram_we (work_ram_we), .work_ram_dout (work_ram_dout),
	.ext_ram_cs  (ext_ram_cs),  .ext_ram_we  (ext_ram_we),  .ext_ram_dout  (ext_ram_dout),
	.palette_cs  (palette_cs),  .palette_we  (palette_we),  .palette_dout  (palette_dout),
	.tilemap_cs   (tilemap_cs), .tilemap_we (tilemap_we), .tilemap_dout (tilemap_dout),
	.yscroll_cs   (yscroll_cs),
	.xscroll_cs   (xscroll_cs),
	.vcu_ctrl_cs  (vcu_ctrl_cs),
	.sprite_ram_cs (sprite_ram_cs), .sprite_ram_we (sprite_ram_we), .sprite_ram_dout (sprite_ram_dout),
	.sprite_ctrl_cs (sprite_ctrl_cs),
	.dswa_cs (dswa_cs), .dswa_din (dswa_din),
	.dswb_cs (dswb_cs), .dswb_din (dswb_din),
	.watchdog_cs (watchdog_cs),
	.ciu_port_cs (ciu_port_cs),
	.ciu_comm_cs (ciu_comm_cs),
	.ciu_wr      (ciu_wr),
	.ciu_rd      (ciu_rd),
	.ciu_comm_din (ciu_comm_din),
	.cchip_mem_cs  (cchip_mem_cs),
	.cchip_asic_cs (cchip_asic_cs),
	.cchip_wr      (cchip_wr),
	.cchip_din     (cchip_din)
);

wire cpu_wr_hi = ~cpu_uds_n;
wire cpu_wr_lo = ~cpu_lds_n;
reg [1:0][7:0] work_ram_mem [0:8191];
reg [1:0][7:0] ext_ram_mem  [0:6143];
reg [1:0][7:0] palette_mem  [0:2047];
wire        hs_grant = ~work_ram_cs;
wire [12:0] hs_wram_addr;
wire  [7:0] hs_wram_wdata;
wire        hs_wram_wr_hi, hs_wram_wr_lo;
wire [12:0] wram_a     = hs_grant ? hs_wram_addr  : cpu_a[13:1];
wire        wram_we_hi = hs_grant ? hs_wram_wr_hi : (work_ram_cs & work_ram_we & cpu_wr_hi);
wire        wram_we_lo = hs_grant ? hs_wram_wr_lo : (work_ram_cs & work_ram_we & cpu_wr_lo);
wire  [7:0] wram_d_hi  = hs_grant ? hs_wram_wdata : cpu_dout[15:8];
wire  [7:0] wram_d_lo  = hs_grant ? hs_wram_wdata : cpu_dout[7:0];
reg [15:0] wram_q;
always @(posedge clk_sys) begin
	if (wram_we_hi) work_ram_mem[wram_a][1] <= wram_d_hi;
	if (wram_we_lo) work_ram_mem[wram_a][0] <= wram_d_lo;

	wram_q <= work_ram_mem[wram_a];
end

reg hs_grant_d;
always @(posedge clk_sys) hs_grant_d <= hs_grant;

reg [15:0] work_ram_dout_r;
always @(posedge clk_sys) if (!hs_grant_d) work_ram_dout_r <= wram_q;
assign work_ram_dout = work_ram_dout_r;
wire hs_busy_load, hs_busy_save;

//------------------------------------------------------------------------
// High-score NVRAM save/restore
//------------------------------------------------------------------------
hiscore_nvram #(
	.GAME_ID(GAME_ID),
	.WORK_RAM_BASE(`CFG_WORK_RAM_BASE(GAME_ID))
) u_hiscore (
	.clk    (clk_sys),
	.reset  (reset),
	.save_req    (hs_save_req),
	.busy_load   (hs_busy_load),
	.busy_save   (hs_busy_save),
	.ioctl_download   (ioctl_download),
	.ioctl_upload     (ioctl_upload),
	.ioctl_wr         (ioctl_wr),
	.ioctl_addr       (ioctl_addr),
	.ioctl_dout       (ioctl_dout),
	.ioctl_din        (ioctl_din),
	.ioctl_index      (ioctl_index),
	.ioctl_upload_req (ioctl_upload_req),
	.wram_grant (hs_grant),
	.wram_addr  (hs_wram_addr),
	.wram_wdata (hs_wram_wdata),
	.wram_wr_hi (hs_wram_wr_hi),
	.wram_wr_lo (hs_wram_wr_lo),
	.wram_rdata (wram_q),
	.restored ()
);

wire [12:0] ext_ram_idx = cpu_a[13:1] - 13'h800;
always @(posedge clk_sys) begin
	if (ext_ram_cs && ext_ram_we) begin
		if (cpu_wr_hi) ext_ram_mem[ext_ram_idx][1] <= cpu_dout[15:8];
		if (cpu_wr_lo) ext_ram_mem[ext_ram_idx][0] <= cpu_dout[7:0];
	end
end

reg [15:0] ext_ram_dout_r;
always @(posedge clk_sys) ext_ram_dout_r <= ext_ram_mem[cpu_a[13:1] - 13'h800];
assign ext_ram_dout = ext_ram_dout_r;

always @(posedge clk_sys) begin
	if (palette_cs && palette_we) begin
		if (cpu_wr_hi) palette_mem[cpu_a[11:1]][1] <= cpu_dout[15:8];
		if (cpu_wr_lo) palette_mem[cpu_a[11:1]][0] <= cpu_dout[7:0];
	end
end

reg [15:0] palette_dout_r;

always @(posedge clk_sys) palette_dout_r <= palette_mem[cpu_a[11:1]];
assign palette_dout = palette_dout_r;
reg [1:0][7:0] tilemap_mem [0:32767];
always @(posedge clk_sys) begin
	if (tilemap_cs && tilemap_we) begin
		if (cpu_wr_hi) tilemap_mem[cpu_a[15:1]][1] <= cpu_dout[15:8];
		if (cpu_wr_lo) tilemap_mem[cpu_a[15:1]][0] <= cpu_dout[7:0];
	end
end

reg [15:0] tilemap_dout_r;
always @(posedge clk_sys) tilemap_dout_r <= tilemap_mem[cpu_a[15:1]];
assign tilemap_dout = tilemap_dout_r;
wire [14:0] bg_tile_rd_addr;
reg  [15:0] bg_tile_rd_dout;
reg [1:0][7:0] tilemap_mem_bg [0:32767];
always @(posedge clk_sys) begin
	if (tilemap_cs && tilemap_we) begin
		if (cpu_wr_hi) tilemap_mem_bg[cpu_a[15:1]][1] <= cpu_dout[15:8];
		if (cpu_wr_lo) tilemap_mem_bg[cpu_a[15:1]][0] <= cpu_dout[7:0];
	end
	bg_tile_rd_dout <= tilemap_mem_bg[bg_tile_rd_addr];
end

wire [14:0] fg_tile_rd_addr;
reg  [15:0] fg_tile_rd_dout;
reg [1:0][7:0] tilemap_mem_fg [0:32767];
always @(posedge clk_sys) begin
	if (tilemap_cs && tilemap_we) begin
		if (cpu_wr_hi) tilemap_mem_fg[cpu_a[15:1]][1] <= cpu_dout[15:8];
		if (cpu_wr_lo) tilemap_mem_fg[cpu_a[15:1]][0] <= cpu_dout[7:0];
	end
	fg_tile_rd_dout <= tilemap_mem_fg[fg_tile_rd_addr];
end

wire cpu_wr_cycle = ~cpu_as_n & ~cpu_rw;
reg [8:0] pc080sn_bg_scrollx, pc080sn_fg_scrollx;
reg [8:0] pc080sn_bg_scrolly, pc080sn_fg_scrolly;
reg       pc080sn_flip;

always @(posedge clk_sys) begin
	if (reset) begin
		pc080sn_bg_scrollx <= 9'd0; pc080sn_fg_scrollx <= 9'd0;
		pc080sn_bg_scrolly <= 9'd0; pc080sn_fg_scrolly <= 9'd0;
		pc080sn_flip <= 1'b0;
	end else if (cpu_wr_cycle) begin

		if (xscroll_cs) begin
			if (!cpu_a[1]) begin
				if (cpu_wr_lo) pc080sn_bg_scrollx[7:0] <= cpu_dout[7:0];
				if (cpu_wr_hi) pc080sn_bg_scrollx[8]   <= cpu_dout[8];
			end else begin
				if (cpu_wr_lo) pc080sn_fg_scrollx[7:0] <= cpu_dout[7:0];
				if (cpu_wr_hi) pc080sn_fg_scrollx[8]   <= cpu_dout[8];
			end
		end
		if (yscroll_cs) begin
			if (!cpu_a[1]) begin
				if (cpu_wr_lo) pc080sn_bg_scrolly[7:0] <= cpu_dout[7:0];
				if (cpu_wr_hi) pc080sn_bg_scrolly[8]   <= cpu_dout[8];
			end else begin
				if (cpu_wr_lo) pc080sn_fg_scrolly[7:0] <= cpu_dout[7:0];
				if (cpu_wr_hi) pc080sn_fg_scrolly[8]   <= cpu_dout[8];
			end
		end

		if (vcu_ctrl_cs && !cpu_a[1] && cpu_wr_lo) pc080sn_flip <= cpu_dout[0];
	end
end

reg [1:0][7:0] sprite_mem [0:8191];
always @(posedge clk_sys) begin
	if (sprite_ram_cs && sprite_ram_we) begin
		if (cpu_wr_hi) sprite_mem[cpu_a[13:1]][1] <= cpu_dout[15:8];
		if (cpu_wr_lo) sprite_mem[cpu_a[13:1]][0] <= cpu_dout[7:0];
	end
end

reg [15:0] sprite_ram_dout_r;
always @(posedge clk_sys) sprite_ram_dout_r <= sprite_mem[cpu_a[13:1]];
assign sprite_ram_dout = sprite_ram_dout_r;
wire [12:0] sp_rd_addr;
reg  [15:0] sp_rd_dout;
reg [1:0][7:0] sprite_mem_spr [0:1023];
reg     [15:0] oam_cp_q;
reg      [9:0] oam_cp_i, oam_cp_i_d;
reg            oam_cp_run, oam_cp_run_d;
wire spr_list_sel = (cpu_a[13:11] == 3'd0);

always @(posedge clk_sys) begin
	if (sprite_ram_cs && sprite_ram_we && spr_list_sel) begin
		if (cpu_wr_hi) sprite_mem_spr[cpu_a[10:1]][1] <= cpu_dout[15:8];
		if (cpu_wr_lo) sprite_mem_spr[cpu_a[10:1]][0] <= cpu_dout[7:0];
	end
	oam_cp_q <= sprite_mem_spr[oam_cp_i];
end

reg vblank_oam_d;
always @(posedge clk_sys) begin
	vblank_oam_d <= VBlank;
	oam_cp_i_d   <= oam_cp_i;
	oam_cp_run_d <= oam_cp_run;

	if (reset) begin
		oam_cp_run <= 1'b0;
		oam_cp_i   <= 10'd0;
	end else if (VBlank && !vblank_oam_d) begin
		oam_cp_run <= 1'b1;
		oam_cp_i   <= 10'd0;
	end else if (oam_cp_run) begin
		if (oam_cp_i == 10'd1023) oam_cp_run <= 1'b0;
		oam_cp_i <= oam_cp_i + 10'd1;
	end
end

reg [15:0] oam_buf [0:1023];
always @(posedge clk_sys) begin
	if (oam_cp_run_d) oam_buf[oam_cp_i_d] <= oam_cp_q;
	sp_rd_dout <= oam_buf[sp_rd_addr[9:0]];
end

reg pc090oj_ctrl_flip;
always @(posedge clk_sys) begin
	if (reset) pc090oj_ctrl_flip <= 1'b0;
	else if (sprite_ram_cs && sprite_ram_we && cpu_wr_lo && cpu_a[13:1] == 13'h0dff)
		pc090oj_ctrl_flip <= cpu_dout[0];
end

reg [15:0] pc090oj_sprite_ctrl;
always @(posedge clk_sys) begin
	if (reset) pc090oj_sprite_ctrl <= 16'd0;
	else if (cpu_wr_cycle && sprite_ctrl_cs) pc090oj_sprite_ctrl <= cpu_dout;
end

assign dswa_din = {8'hFF, dswa};
assign dswb_din = {8'hFF, dswb};
assign dbg_cc_cs    = cchip_mem_cs | cchip_asic_cs;
assign dbg_cc_wr    = cchip_wr;
assign dbg_cc_asic  = cchip_asic_cs;
assign dbg_cc_addr  = cpu_a[11:1];
assign dbg_cc_wdata = cpu_dout[7:0];
assign dbg_cc_rdata = cchip_din;

//------------------------------------------------------------------------
// C-chip (TC0030CMD)
//------------------------------------------------------------------------
rbisland_cchip cchip
(
	.clk_sys (clk_sys),
	.reset   (reset),
	.mem_cs  (cchip_mem_cs),
	.asic_cs (cchip_asic_cs),
	.wr      (cchip_wr),
	.addr    (cpu_a[10:1]),
	.din     (cpu_dout[7:0]),
	.dout    (cchip_din),
	.ext_irq (vblank_irq_pulse),
	.ioctl_download (ioctl_download),
	.ioctl_wr       (ioctl_wr),
	.ioctl_addr     (ioctl_addr),
	.ioctl_dout     (ioctl_dout),
	.ioctl_index    (ioctl_index),
	.dl_en          (dl_cchip),
	.dl_addr        (dl_a_cchip),
	.service   (~service),
	.cab_1p    ({~start2, ~start1}),
	.coin      ({~coin2, ~coin1}),
	.tilt      (~tilt),
	.joystick1 (~{joystick_0[4], joystick_0[5], joystick_0[3:0]}),
	.pause     (pause)
);

//------------------------------------------------------------------------
// PC060HA CIU (68000 <-> Z80 sound mailbox)
//------------------------------------------------------------------------
pc060ha_ciu ciu
(
	.clk   (clk_sys),
	.reset (reset),
	.m_port_cs (ciu_port_cs),
	.m_comm_cs (ciu_comm_cs),
	.m_wr      (ciu_wr),
	.m_rd      (ciu_rd),
	.m_din     (cpu_dout[7:0]),
	.m_dout    (ciu_comm_din),
	.s_port_cs (z80_ciu_port_cs),
	.s_comm_cs (z80_ciu_comm_cs),
	.s_wr      (z80_ciu_wr),
	.s_rd      (z80_ciu_rd),
	.s_din     (z80_dout),
	.s_dout    (z80_ciu_comm_din),
	.slave_nmi   (z80_nmi_req),
	.slave_reset (z80_reset_req),
	.cmd_stb     (ciu_cmd_stb),
	.cmd_byte    (ciu_cmd_byte)
);

wire       hblank_w, vblank_w;
wire [8:0] hpos, vpos;
assign dbg_vpos = vpos;
assign dbg_hpos = hpos;
reg vblank_d2;
always @(posedge clk_sys) vblank_d2 <= vblank_w;
wire vbl_rise = vblank_w & ~vblank_d2;

//------------------------------------------------------------------------
// Video timing
//------------------------------------------------------------------------
video #(.H_FRONT_P(20), .H_SYNC_P(33), .H_BACK_P(51)) video
(
	.clk_sys (clk_sys),
	.ce_pix  (ce_pix),
	.reset   (reset_video),
	.HBlank  (hblank_w),
	.VBlank  (vblank_w),
	.HSync   (HSync),
	.VSync   (VSync),
	.hpos    (hpos),
	.vpos    (vpos)
);

assign HBlank = hblank_w;
assign VBlank = vblank_w;
wire [10:0] bg_pixel_pal_addr;
wire        bg_lb_we, bg_lb_we_nz, bg_px_nz, bg_attr_nz, bg_code_nz;
wire  [2:0] bg_state;
wire        bg_gfx_rd_req, fg_gfx_rd_req;
wire [23:1] bg_gfx_rd_addr, fg_gfx_rd_addr;
wire        bg_gfx_rd_ready, fg_gfx_rd_ready;
wire [15:0] bg_gfx_rd_dout, fg_gfx_rd_dout;

//------------------------------------------------------------------------
// Tile ROM read arbiter (BG + FG share one loader port)
//------------------------------------------------------------------------
gfx_read_arbiter2 tile_gfx_arbiter
(
	.clk   (clk_sys),
	.reset (reset),
	.a_req   (bg_gfx_rd_req),
	.a_addr  (bg_gfx_rd_addr),
	.a_ready (bg_gfx_rd_ready),
	.a_dout  (bg_gfx_rd_dout),
	.b_req   (fg_gfx_rd_req),
	.b_addr  (fg_gfx_rd_addr),
	.b_ready (fg_gfx_rd_ready),
	.b_dout  (fg_gfx_rd_dout),
	.req   (gfx_rd_req),
	.addr  (gfx_rd_addr),
	.ready (gfx_rd_ready),
	.dout  (gfx_rd_dout)
);

wire static_screen = 1'b0;
wire [8:0] bg_pic_adj = static_screen ? 9'd15 : 9'd0;

//------------------------------------------------------------------------
// PC080SN background layer
//------------------------------------------------------------------------
pc080sn_layer_renderer #(.TILE_BASE(15'd0), .ROWSCROLL_BASE(15'h2000),
                         .TRANSPARENT(1'b0), .Y_PIC_ADJ(9'd0)) bg_renderer
(
	.clk_sys (clk_sys),
	.reset   (reset),
	.hc (10'(hpos)),
	.vc (10'(vpos)),
	.scrollx (pc080sn_bg_scrollx),
	.scrolly (pc080sn_bg_scrolly),
	.y_adjust (bg_pic_adj),
	.y_scroll_neg (bg_yneg),
	.tile_rd_addr (bg_tile_rd_addr),
	.tile_rd_dout (bg_tile_rd_dout),
	.gfx_rd_req   (bg_gfx_rd_req),
	.gfx_rd_addr  (bg_gfx_rd_addr),
	.gfx_rd_ready (bg_gfx_rd_ready),
	.gfx_rd_dout  (bg_gfx_rd_dout),
	.pixel_valid    (),
	.pixel_pal_addr (bg_pixel_pal_addr),
	.dbg_lb_we      (bg_lb_we),
	.dbg_lb_we_nz   (bg_lb_we_nz),
	.dbg_px_nz      (bg_px_nz),
	.dbg_attr_nz    (bg_attr_nz),
	.dbg_code_nz    (bg_code_nz),
	.dbg_state      (bg_state)
);

wire        fg_pixel_valid;
wire [10:0] fg_pixel_pal_addr;

//------------------------------------------------------------------------
// PC080SN foreground layer
//------------------------------------------------------------------------
pc080sn_layer_renderer #(.TILE_BASE(15'h4000), .ROWSCROLL_BASE(15'h6000),
                         .TRANSPARENT(1'b1)) fg_renderer
(
	.clk_sys (clk_sys),
	.reset   (reset),
	.hc (10'(hpos)),
	.vc (10'(vpos)),
	.scrollx (pc080sn_fg_scrollx),
	.scrolly (pc080sn_fg_scrolly),
	.y_adjust (9'd0),
	.y_scroll_neg (1'b0),
	.tile_rd_addr (fg_tile_rd_addr),
	.tile_rd_dout (fg_tile_rd_dout),
	.gfx_rd_req   (fg_gfx_rd_req),
	.gfx_rd_addr  (fg_gfx_rd_addr),
	.gfx_rd_ready (fg_gfx_rd_ready),
	.gfx_rd_dout  (fg_gfx_rd_dout),
	.pixel_valid    (fg_pixel_valid),
	.pixel_pal_addr (fg_pixel_pal_addr),
	.dbg_lb_we      (),
	.dbg_lb_we_nz   (),
	.dbg_px_nz      (),
	.dbg_attr_nz    (),
	.dbg_code_nz    (),
	.dbg_state      ()
);

wire        sp_pixel_valid;
wire [12:0] sp_pixel_pal_addr;

//------------------------------------------------------------------------
// PC090OJ sprites
//------------------------------------------------------------------------
pc090oj_renderer #(.COLBANK_W(`CFG_SPR_COLBANK_W(GAME_ID))) sprite_renderer
(
	.clk_sys (clk_sys),
	.reset   (reset),
	.hc (10'(hpos)),
	.vc (10'(vpos)),
	.sprite_ctrl (pc090oj_sprite_ctrl),
	.ctrl_flip   (pc090oj_ctrl_flip),
	.sp_rd_addr (sp_rd_addr),
	.sp_rd_dout (sp_rd_dout),
	.gfx_rd_req   (obj_rd_req),
	.gfx_rd_addr  (obj_rd_addr),
	.gfx_rd_ready (obj_rd_ready),
	.gfx_rd_dout  (obj_rd_dout),
	.gfx_rd_burst (obj_rd_burst),
	.gfx_rd_dout4 (obj_rd_dout4),
	.pixel_valid    (sp_pixel_valid),
	.pixel_pal_addr (sp_pixel_pal_addr)
);

wire [10:0] sp_pal11 = sp_pixel_pal_addr[10:0];
wire [10:0] normal_pixel = fg_pixel_valid ? fg_pixel_pal_addr :
                           sp_pixel_valid ? sp_pal11 :
                                            bg_pixel_pal_addr;

//------------------------------------------------------------------------
// Layer priority mux + palette lookup
//------------------------------------------------------------------------
wire [10:0] final_pixel_pal_addr =
	(layer_sel == 2'd1) ? bg_pixel_pal_addr :
	(layer_sel == 2'd2) ? (fg_pixel_valid ? fg_pixel_pal_addr : 11'd0) :
	(layer_sel == 2'd3) ? (sp_pixel_valid ? sp_pal11 : 11'd0) :
	                      normal_pixel;
reg  [15:0] final_pal_word;
reg [1:0][7:0] palette_mem_vid [0:2047];
always @(posedge clk_sys) begin
	if (palette_cs && palette_we) begin
		if (cpu_wr_hi) palette_mem_vid[cpu_a[11:1]][1] <= cpu_dout[15:8];
		if (cpu_wr_lo) palette_mem_vid[cpu_a[11:1]][0] <= cpu_dout[7:0];
	end
	final_pal_word <= palette_mem_vid[final_pixel_pal_addr];
end

wire [4:0] pal_b = final_pal_word[14:10];
wire [4:0] pal_g = final_pal_word[9:5];
wire [4:0] pal_r = final_pal_word[4:0];
wire [7:0] game_r = {pal_r, pal_r[4:2]};
wire [7:0] game_g = {pal_g, pal_g[4:2]};
wire [7:0] game_b = {pal_b, pal_b[4:2]};
wire        overlay_on;
wire [23:0] overlay_rgb;

//------------------------------------------------------------------------
// Pause overlay panel
//------------------------------------------------------------------------
pause_overlay #(
	.H_VISIBLE (10'd320),
	.V_VISIBLE (`CFG_V_VISIBLE(GAME_ID)),
	.V_FIRST   (10'd0),
	.ROTATE    (1'b0),
	.CELL_W    (4'd6)
) pause_panel
(
	.clk_sys (clk_sys),
	.hpos    (hpos),
	.vpos    (vpos),
	.pause   (pause),
	.overlay_on  (overlay_on),
	.overlay_rgb (overlay_rgb)
);

wire        toast_on;
wire [23:0] toast_rgb;

//------------------------------------------------------------------------
// High-score toast (load/save message)
//------------------------------------------------------------------------
hs_toast #(.H_VISIBLE(10'd320), .V_VISIBLE(`CFG_V_VISIBLE(GAME_ID)))
u_hs_toast
(
	.clk_sys   (clk_sys),
	.hpos      (hpos),
	.vpos      (vpos),
	.busy_load (hs_busy_load),
	.busy_save (hs_busy_save),
	.overlay_on  (toast_on),
	.overlay_rgb (toast_rgb)
);

wire        ovl_on  = overlay_on | toast_on;
wire [23:0] ovl_rgb = overlay_on ? overlay_rgb : toast_rgb;
assign R = (!hblank_w && !vblank_w) ? (ovl_on ? ovl_rgb[23:16] : game_r) : 8'd0;
assign G = (!hblank_w && !vblank_w) ? (ovl_on ? ovl_rgb[15:8]  : game_g) : 8'd0;
assign B = (!hblank_w && !vblank_w) ? (ovl_on ? ovl_rgb[7:0]   : game_b) : 8'd0;
wire [15:0] fm_l, fm_r;
wire [15:0] pcm_l, pcm_r;
assign fm_l  = ym_audio_l;
assign fm_r  = ym_audio_r;
wire [15:0] click_out;

//------------------------------------------------------------------------
// Sound diagnostic probe (optional click tones)
//------------------------------------------------------------------------
sound_probe probe
(
	.clk_sys  (clk_sys),
	.reset    (reset),
	.enable   (snd_diag != 2'd0),
	.rom_wr   (dl_snd & ioctl_wr),
	.rom_data (ioctl_dout),
	.trig_68k (ciu_comm_cs & ciu_wr),
	.trig_z80 (z80_ym_reg_cs & ~z80_wr_n),
	.trig_irq (z80_int_req),
	.out      (click_out)
);

assign pcm_l = click_out;
assign pcm_r = click_out;
wire [15:0] mix_l, mix_r;

//------------------------------------------------------------------------
// Audio mixer + pause fade
//------------------------------------------------------------------------
audio_mixer audio_mixer
(
	.clk_sys (clk_sys),
	.reset   (reset),
	.ch0_l (fm_l),  .ch0_r (fm_r),
	.ch1_l (pcm_l), .ch1_r (pcm_r),
	.audio_l (mix_l),
	.audio_r (mix_r)
);

reg  [4:0]  pause_gain = 5'd16;
reg  [11:0] gain_div   = 12'd0;

always @(posedge clk_sys) begin
	gain_div <= gain_div + 12'd1;
	if (gain_div == 12'd0) begin
		if (pause) begin
			if (pause_gain != 5'd0)  pause_gain <= pause_gain - 5'd1;
		end else begin
			if (pause_gain != 5'd16) pause_gain <= pause_gain + 5'd1;
		end
	end
end

wire signed [21:0] gain_l = $signed(mix_l) * $signed({2'b00, pause_gain});
wire signed [21:0] gain_r = $signed(mix_r) * $signed({2'b00, pause_gain});
assign audio_l = gain_l[19:4];
assign audio_r = gain_r[19:4];
reg        rom_ready_d;
reg  [2:0] rom_cap = 3'd0;
reg  [2:0] bg_state_d;
reg [19:0] state_same;

always @(posedge clk_sys) begin
	if (cpu_as_n_d && !cpu_as_n) dbg_ever_as    <= 1'b1;
	if (!cpu_dtack_n)            dbg_ever_dtack <= 1'b1;
	if (palette_cs    && palette_we)    dbg_pal_wr    <= 1'b1;
	if (palette_cs && palette_we && cpu_dout != 16'd0) dbg_pal_nz <= 1'b1;
	if (dl_gfx && ioctl_wr) dbg_gfx_dl <= 1'b1;
	if (gfx_rd_ready && gfx_rd_dout != 16'd0)                 dbg_gfx_nz <= 1'b1;
	if (bg_tile_rd_dout != 16'd0)                             dbg_tilemap_nz <= 1'b1;
	if (final_pixel_pal_addr != 11'd0)                        dbg_pix_nz <= 1'b1;
	if (ioctl_download && ioctl_wr) begin
		if (dl_main ) dl_b0 <= dl_b0 + 1'd1;
		if (dl_snd  ) dl_b1 <= dl_b1 + 1'd1;
		if (dl_gfx  ) dl_b2 <= dl_b2 + 1'd1;
		if (dl_obj  ) dl_b3 <= dl_b3 + 1'd1;
		if (dl_cchip) dl_b4 <= dl_b4 + 1'd1;
	end
	dbg_dl0 <= dl_b0[23:8]; dbg_dl1 <= dl_b1[23:8]; dbg_dl2 <= dl_b2[23:8];
	dbg_dl3 <= dl_b3[23:8]; dbg_dl4 <= dl_b4[23:8];

	rom_ready_d <= rom_ready;
	if (reset) begin
		rom_cap    <= 3'd0;
		dbg_v_rom0 <= 16'd0; dbg_v_rom1 <= 16'd0;
		dbg_v_rom2 <= 16'd0; dbg_v_rom3 <= 16'd0;
	end else if (rom_ready && !rom_ready_d && rom_cap < 3'd4) begin
		case (rom_cap)
			3'd0: dbg_v_rom0 <= rom_dout;
			3'd1: dbg_v_rom1 <= rom_dout;
			3'd2: dbg_v_rom2 <= rom_dout;
			3'd3: dbg_v_rom3 <= rom_dout;
		endcase
		rom_cap <= rom_cap + 1'd1;
	end

	if (cpu_as_n)            dbg_v_asstuck <= 16'd0;
	else if (~&dbg_v_asstuck) dbg_v_asstuck <= dbg_v_asstuck + 1'd1;
	if (cpu_as_n_d && !cpu_as_n) dbg_v_cpua <= {1'b0, cpu_a[23:9]};
	if (bg_tile_rd_dout != 16'd0 && dbg_v_tile  == 16'd0) dbg_v_tile  <= bg_tile_rd_dout;
	if (bg_gfx_rd_ready && bg_gfx_rd_dout != 16'd0 && dbg_v_gfx == 16'd0) dbg_v_gfx <= bg_gfx_rd_dout;
	if (palette_cs && palette_we && cpu_dout != 16'd0 && dbg_v_palwr == 16'd0) dbg_v_palwr <= cpu_dout;
	if (final_pal_word != 16'd0 && dbg_v_palrd == 16'd0) dbg_v_palrd <= final_pal_word;
	if (final_pixel_pal_addr != 11'd0 && dbg_v_pixidx == 16'd0)
		dbg_v_pixidx <= {5'd0, final_pixel_pal_addr};
	dbg_v_scroll <= {pc080sn_bg_scrolly[7:0], pc080sn_bg_scrollx[7:0]};

	if (final_pal_word != 16'd0)                              dbg_palword_nz <= 1'b1;
	if ({R,G,B} != 24'd0)                                     dbg_rgb_nz     <= 1'b1;
	if (vblank_w && !vblank_d2)                               dbg_vid_run    <= 1'b1;
	if (tilemap_cs    && tilemap_we)    dbg_tile_wr   <= 1'b1;
	if (sprite_ram_cs && sprite_ram_we) dbg_spr_wr    <= 1'b1;
	if (cchip_mem_cs  || cchip_asic_cs) dbg_cchip_acc <= 1'b1;
end

reg [19:0] cnt_idx, cnt_word, cnt_rgb, cnt_lbw, cnt_lbwnz, cnt_gfxnz, cnt_pxnz, cnt_attrnz, cnt_codenz;
reg [19:0] cnt_cchip, cnt_tilewr, cnt_palwr, cnt_bus;
always @(posedge clk_sys) begin
	if (vbl_rise) begin
		dbg_live_idx  <= (cnt_idx  > 20'd1000);
		dbg_live_word <= (cnt_word > 20'd1000);
		dbg_live_rgb  <= (cnt_rgb  > 20'd1000);
		dbg_live_lbw   <= (cnt_lbw   > 20'd1000);
		dbg_live_lbwnz <= (cnt_lbwnz > 20'd1000);
		dbg_live_gfxnz  <= (cnt_gfxnz  > 20'd1000);
		dbg_live_pxnz   <= (cnt_pxnz   > 20'd1000);
		dbg_live_attrnz <= (cnt_attrnz > 20'd1000);
		dbg_live_codenz <= (cnt_codenz > 20'd1000);
		dbg_v_cnt    <= cnt_idx[19:4];
		dbg_v_cchip  <= cnt_cchip[15:0];
		dbg_v_tilewr <= cnt_tilewr[15:0];
		dbg_v_palwrc <= cnt_palwr[15:0];
		dbg_v_buscnt <= cnt_bus[15:0];
		cnt_bus <= 0;
		cnt_cchip <= 0; cnt_tilewr <= 0; cnt_palwr <= 0;

		dbg_bg_stuck <= (state_same > 20'd50000);
		cnt_idx  <= 0;
		cnt_word <= 0;
		cnt_rgb  <= 0;
		cnt_lbw  <= 0;
		cnt_lbwnz <= 0;
		cnt_gfxnz <= 0;
		cnt_pxnz <= 0;
		cnt_attrnz <= 0;
		cnt_codenz <= 0;
	end else if (ce_pix && !hblank_w && !vblank_w) begin
		if (final_pixel_pal_addr != 11'd0) cnt_idx  <= cnt_idx  + 1'd1;
		if (final_pal_word       != 16'd0) cnt_word <= cnt_word + 1'd1;
		if ({R,G,B}              != 24'd0) cnt_rgb  <= cnt_rgb  + 1'd1;
	end
	if (bg_lb_we    && !vbl_rise) cnt_lbw   <= cnt_lbw   + 1'd1;
	if (bg_lb_we_nz && !vbl_rise) cnt_lbwnz <= cnt_lbwnz + 1'd1;
	if (bg_gfx_rd_ready && bg_gfx_rd_dout != 16'd0 && !vbl_rise)
		cnt_gfxnz <= cnt_gfxnz + 1'd1;
	if (bg_px_nz   && !vbl_rise) cnt_pxnz   <= cnt_pxnz   + 1'd1;
	if (bg_attr_nz && !vbl_rise) cnt_attrnz <= cnt_attrnz + 1'd1;
	if (bg_code_nz && !vbl_rise) cnt_codenz <= cnt_codenz + 1'd1;
	if (!vbl_rise) begin
		if (cchip_mem_cs || cchip_asic_cs)      cnt_cchip  <= cnt_cchip  + 1'd1;
		if (tilemap_cs && tilemap_we)           cnt_tilewr <= cnt_tilewr + 1'd1;
		if (palette_cs && palette_we)           cnt_palwr  <= cnt_palwr  + 1'd1;
		if (cpu_as_n_d && !cpu_as_n)            cnt_bus    <= cnt_bus    + 1'd1;
	end
end

always @(posedge clk_sys) begin
	bg_state_d <= bg_state;
	if (bg_state != bg_state_d) state_same <= 0;
	else if (!(&state_same))    state_same <= state_same + 1'd1;
end

endmodule
