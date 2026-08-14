//============================================================================
//  Arcade: Rainbow Islands (Taito, 1987) - MiSTer FPGA top-level skeleton
//  Based on the standard MiSTer Arcade template (sys/template).
//  This is a SKELETON: CPU/GFX/sound cores are stubbed and must be filled
//  in with real implementations (or ported from an existing MAME driver /
//  open silicon reimplementation) before this will run actual game code.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module.
	//
	// 46 BITS, NOT 49. sys_top.v:1760 concatenates exactly 46 signals into
	// this port, and upstream Template_MiSTer declares [45:0] in BOTH
	// emu_ports.vh and hps_io.sv. A mismatch is tolerated until MISTER_FB is
	// defined, which tightens elaboration of this port into a hard error:
	//   Error (10978): sys_top.v(1760): packed array type ... not equivalent
	// This and sys/hps_io.sv must both stay 46.
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	// FRAMEBUFFER INTERFACE, for screen rotation. sys_top.v:1790 connects
	// these inside `ifdef MISTER_FB -- the macro and this port list must be
	// added or removed together. All but FB_FORCE_BLANK are driven by
	// screen_rotate. Currently OFF; see the macro comment in Rbisland.qsf for
	// why (it breaks Direct Video on a CRT).
`ifdef MISTER_FB
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,
`endif

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER,
	output        VGA_DISABLE,

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,
	output        HDMI_BLACKOUT,
	output        HDMI_BOB_DEINT,

	output        LED_USER,
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,
	output  [1:0] BUTTONS,

	input         CLK_AUDIO,
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,
	output  [1:0] AUDIO_MIX,

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//SDRAM interface
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

	// DDR3 interface (the DE10-nano's own on-board DDR3, via the HPS).
	// This core doesn't use it -- everything lives in the separate SDRAM
	// module above -- but sys_top drives these ports unconditionally, so
	// they must exist here and are tied off below. Port widths confirmed
	// against a real current core's own emu declaration
	// (MiSTer-devel/Arcade-Cosmic_MiSTer), not guessed.
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
// SDRAM_DQ is driven by the sdram module instance below (real inout pin now
// that rtl/sdram.sv is a real controller, not a stub) -- no tie-off here.

assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

// DDR3 IS USED, by screen_rotate below. A rotated frame cannot live in block
// RAM (553 M10K on the device, 442 already held by this core), so the
// rotation buffer goes in DDR3 and every DDRAM_* signal is driven by that
// instance in the VIDEO OUTPUT section rather than tied off here.
//
// FB_FORCE_BLANK is the one framebuffer output screen_rotate does not drive.
`ifdef MISTER_FB
assign FB_FORCE_BLANK = 1'b0;
`endif

assign AUDIO_S   = 1;       // signed samples
assign AUDIO_MIX = 0;

// DIAGNOSTIC BUILDS ONLY. 2'd1 arms the sound probe in rbisland_top.sv; the
// core then reports the health of the whole sound chain through the audio
// output on its own, with no OSD entry to find. Public builds ship 2'd0.
//
// OFF for the script-player build. Two of the probe's three activity tones
// watch the Z80 -- trig_z80 is the Z80's YM register strobe and trig_irq is
// the YM timer interrupt into the Z80 -- and with SOUND_SCRIPTS=1 there is no
// Z80, so both are tied low. The probe would sit there reporting a dead sound
// chain over the top of working music, on the very channel the music needs.
localparam [1:0] SOUND_PROBE = 2'd0;

// FORWARD DECLARATIONS. Both signals are driven further down -- ioctl_download
// by the hps_io instance, status by the width-truncating assign beneath it --
// but the assigns immediately below reference them, so they have to be declared
// before that first use. Leaving them undeclared here made Verilog's implicit-net
// rule invent a 1-BIT net for `status`, and a tool that resolved that against the
// real [31:0] declaration the other way would silently break every status[N] OSD
// option, the status[18] refresh toggle included. ModelSim rejects it outright.
wire        ioctl_download;
// 64 bits, NOT 32.
//
// The .mra's <switches default="fe,bf" base="16"> block puts the two DIP
// bytes at status[31:16], so EVERY core menu option must live outside that
// window or the two silently move each other. Core options live at [63:32];
// bits [31:16] belong entirely to the DIPs, exactly as the .mra declares.
// hps_io supplies status[127:0], so widening costs nothing.
wire [63:0] status;

assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;

//------------------------------------------------------------------------
// Aspect ratio / status menu (customize per game)
//------------------------------------------------------------------------
// Menu options live in the HIGH status bits, clear of the DIP window --
// see the DIP section below.
wire [1:0] ar = status[33:32];

//------------------------------------------------------------------------
// DIRECT VIDEO GUARD
//
// Direct Video and the rotation framebuffer are mutually exclusive by
// construction: screen_rotate writes each frame into the DDR3 framebuffer and
// raises FB_EN, so sys_top scans out of that buffer instead of VGA_*, while
// direct_video exists to bypass the scaler and drive the DAC from the native
// VGA_* timings. With both enabled the DAC is fed from a path that is no
// longer producing a picture -- black screen, and the HDMI sink dropping the
// link takes the audio island with it, so it presents as a sound fault too.
//
// CRT Adjust is NOT covered by this guard. It emits a self-consistent
// {hs, vs, de, ce} set, which is exactly what the Direct Video path forwards,
// and driving a CRT is the case it exists for.
//
// Forced off, not merely hidden. Hiding alone would trap a user who saves
// Rotation = CW and only then sets direct_video=1: they would boot to a
// broken screen with the one option that could fix it now invisible.
wire vid_direct_guard = direct_video;

// Rotation decode. Here because the aspect ratio depends on it.
// 0 = off, 1 = clockwise, 2 = counter-clockwise.
wire [1:0] rot_sel    = vid_direct_guard ? 2'd0 : status[54:53];
wire       no_rotate  = (rot_sel == 2'd0);
wire       rotate_ccw = (rot_sel == 2'd2);
wire       vid_flip   = vid_direct_guard ? 1'b0 : status[55];

// "Original" becomes 3:4 once the picture is on its side, or a rotated
// display shows a correctly-rotated image in a stretched frame. Explicit
// ratio choices are left alone: naming a ratio means that ratio.
assign VIDEO_ARX = (!ar) ? (no_rotate ? 12'd4 : 12'd3) : (12'(ar) - 1'd1);
assign VIDEO_ARY = (!ar) ? (no_rotate ? 12'd3 : 12'd4) : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	// Core name, shown as the OSD title. Renamed from "RBISLAND" now that this
	// is a Taito C-Chip FAMILY core rather than a single game -- see ROADMAP.md.
	//
	// NOTE: this token is also the settings filename the framework uses under
	// /media/fat/config, so changing it orphans any previously saved OSD
	// settings. Users will find their options back at defaults once after
	// upgrading, and will need to re-save. That is a one-time cost and is the
	// reason this string should not be churned again casually.
	"A.Taito C-Chip;;",
	"-;",
	// EVERY option below sits at status bit 32 or above. Bits 31:16 are the
	// .mra's DIP switches (<switches base="16">) and bit 0 is Reset; anything
	// placed in between would move a DIP and be moved by one.
	"O[33:32],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	// Refresh rate. Not a debug switch -- a compatibility option. The arcade
	// rate is 59.83 Hz and that is what the PCB produces, but some consumer
	// CRTs driven through Direct Video have too narrow a vertical hold range
	// to sit still at it. See the PIX_INC constants below.
	"O[34],Refresh,59.83Hz Arcade,60Hz CRT;",
	// status bit allocation: 33:32 Aspect, 34 Refresh, 35 CRT Adjust,
	// 40:36 CRT H-Size, 47:41 CRT H-Position, 52:48 CRT V-Shift,
	// 54:53 Rotation, 55 Flip, 58 Save Highscore. 56 and 57 are retired, not
	// reused, so a config saved by an older build cannot have a stale
	// "Autosave" setting reinterpreted as a save command.
	//
	// HIGH SCORES. Loading is unconditional and has no menu entry -- a saved
	// table is restored whenever the framework supplies the file. Saving is
	// manual: the momentary "R" entry below is the only thing that ever writes
	// the SD card.
	//
	// Shelved -- hidden from the OSD because on hardware the scores neither
	// saved nor loaded. The RTL stays wired and status[58] simply never gets
	// set, so uncommenting the entry restores it. Unresolved: the .mra does
	// carry <nvram index="2" size="54"/> and the load path is unconditional,
	// so the fault is upstream. Check whether hps_io ever raises
	// ioctl_index==2 at all.
	// "R58,SAVE HIGHSCORE;",
	// ROTATION / FLIP. For rotated monitors and vertical cabs; Rainbow Islands
	// itself is horizontal. Costs a frame of latency by construction (a
	// rotated pixel needs a column not yet drawn), hence the DDR3 framebuffer
	// rather than the line-based path. Flip is 180 degrees and applies only
	// when Rotation is Off (screen_rotate: `do_flip <= no_rotate && flip`).
	// H0 hides both under Direct Video -- see the vid_direct_guard block,
	// which also forces them off so a hidden entry cannot leave a stale
	// setting applied.
`ifdef MISTER_FB
	"H0O[54:53],Rotation,Off,CW,CCW;",
	"H0O[55],Flip (no rotation),Off,On;",
`endif
	"-;",
	"DIP;",
	"-;",
	//------------------------------------------------------------------
	// CRT ADJUST (rmonic79/MiSTer-CRT-Adjust, rtl/crt/crt_adjust.sv)
	//
	// Moves the picture CONTENT through a line buffer and leaves sync native.
	// Shifting sync instead is what makes a CRT lose hold while adjusting.
	//
	// Default OFF, so HDMI output is bit-identical to a build without it.
	// H1 hides the three amounts until CRT Adjust is On -- see
	// status_menumask on the hps_io instance. H must come before P.
	//------------------------------------------------------------------
	"P1,CRT Adjust;",
	"P1-;",
	// Deliberately NOT hidden under Direct Video: driving a CRT through a DAC
	// is the case this feature exists for, and it is where the picture most
	// often needs centring.
	"P1O[35],CRT Adjust,Off,On;",
	"P1-;",
	// H-Size: signed 5-bit, -16..+15. Each step changes the DAC read
	// period by ~1.5%; positive reads slower, so pixels get WIDER.
	"H1P1O[40:36],CRT H-Size,",
		"0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,",
		"-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	// H-Position: signed 7-bit. The specified working range is -48..+48;
	// the field is a plain signed 7-bit value (-64..+63) so that all three
	// controls share ONE encoding convention rather than this one being a
	// special wrap-coded case. Beyond roughly +-48 the content runs out of
	// the line-buffer window and a black block appears at the screen edge,
	// which is the documented limit of the CONTENTSHIFT mechanism.
	"H1P1O[47:41],CRT H-Position,",
		"0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,",
		"+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,",
		"+32,+33,+34,+35,+36,+37,+38,+39,+40,+41,+42,+43,+44,+45,+46,+47,",
		"+48,+49,+50,+51,+52,+53,+54,+55,+56,+57,+58,+59,+60,+61,+62,+63,",
		"-64,-63,-62,-61,-60,-59,-58,-57,-56,-55,-54,-53,-52,-51,-50,-49,",
		"-48,-47,-46,-45,-44,-43,-42,-41,-40,-39,-38,-37,-36,-35,-34,-33,",
		"-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,",
		"-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	// V-Shift: signed 5-bit, -16..+15 lines. Delays VSync by N lines; the
	// CRT's vertical hold range is wide enough that this never desyncs.
	"H1P1O[52:48],CRT V-Shift,",
		"0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,",
		"-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"-;",
	"R0,Reset;",
	// Button assignment established on hardware. MAME's rbisland INPUT_PORTS
	// attaches no PORT_NAME, only
	//     PORT_BIT( 0x40, IP_ACTIVE_LOW, IPT_BUTTON1 )   -> C-chip PC6
	//     PORT_BIT( 0x80, IP_ACTIVE_LOW, IPT_BUTTON2 )   -> C-chip PC7
	// so which one jumps is a property of the game: BUTTON1 fires the rainbow,
	// BUTTON2 jumps.
	//
	// The swap is done in the wiring (see the cchip instance in
	// rbisland_top.sv), not by renaming these entries -- a saved config binds
	// a physical button to a joystick BIT, so the bit's meaning is what has to
	// change.
	// Pause is ours, not the game's -- the PCB has no pause. It freezes the
	// CPUs and sound and draws a supporter panel over the picture.
	"J1,Jump,Fire,Start 1P,Start 2P,Coin,Service,Pause;",
	"jn,A,B,Start,Select,R,L,X;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys;   // 48 MHz system clock -- everything in the core runs
                // from this, with per-chip clock enables derived below
                // and inside each wrapper.
wire pll_locked;

// Module "pll" is the Quartus IP Catalog-generated PLL (rtl/pll.v +
// rtl/pll/pll_0002.v), NOT rtl/pll.sv -- see that file's header and the .qsf
// for why the placeholder must stay out of the project.
//
// outclk_0 must be 48.000 MHz from the 50 MHz reference: M=24, N=1
// (VCO 1200 MHz), C0=25 -> 1200/25 = 48.000 MHz exactly. One output is
// enough; the video path runs from CLK_VIDEO (= clk_sys) plus the CE_PIXEL
// clock enable below, the standard MiSTer pattern, so a stock single-output
// PLL works here.
pll pll
(
	.refclk(CLK_50M),
	.rst(1'b0),
	.outclk_0(clk_sys),    // 48.000 MHz
	.locked(pll_locked)
);

// clk_sys is free-running; 68k/Z80 phases are derived with clock-enables
// rather than separate PLL outputs, which keeps everything synchronous
// to clk_sys for the SDRAM controller and video pipeline.
reg [5:0] clk_div;
always @(posedge clk_sys) clk_div <= clk_div + 1'd1;

// NOTE: ce_8m/ce_4m are UNUSED -- rbisland_top declares them as ports
// but never reads them; each CPU/sound wrapper derives its own (correct)
// enable internally from clk_sys. Kept only so the port list matches.
// Note the actual divisors are /8 and /16, not /6 and /12.
wire ce_8m  = (clk_div[2:0] == 0); // clk_sys/8  = 6 MHz  (NOT 8 MHz)
wire ce_4m  = (clk_div[3:0] == 0); // clk_sys/16 = 3 MHz  (NOT 4 MHz)

// Pixel clock enable, as a fractional accumulator. The board runs video from
// a separate 26.686 MHz crystal (26.686/4 = 6.6715 MHz) independent of the
// 16 MHz CPU crystal, so the pixel rate is not an integer division of
// clk_sys; jotego's Rastan core synthesises the same rate the same way. The
// resulting +/-1 clk_sys jitter is 20.8 ns, far below a pixel period.
//
// REFRESH RATE SELECT (OSD "Refresh"). video.sv totals are 424 x 263 =
// 111512 pixels a frame, so
//     9109/65536 * 48 MHz = 6.6714 MHz  ->  59.83 Hz   (arcade original)
//     9135/65536 * 48 MHz = 6.6907 MHz  ->  60.00 Hz   (forced NTSC)
//
// 59.83 Hz is what the PCB does but sits 0.17 Hz below broadcast NTSC, and
// consumer CRTs fed through Direct Video have a narrow vertical hold range.
// Forcing 60.00 Hz costs a 0.28% speed-up -- inaudible in play -- and gives
// those sets something to lock to. Only the pixel rate changes; every H/V
// total stays put, so the renderers' per-line budgets do not move.
localparam [15:0] PIX_INC_NATIVE = 16'd9109;   // 59.83 Hz, matches the PCB
localparam [15:0] PIX_INC_60HZ   = 16'd9135;   // 60.00 Hz, for CRT hold range

reg [16:0] pix_acc;
wire [15:0] pix_inc = status[34] ? PIX_INC_60HZ : PIX_INC_NATIVE;
always @(posedge clk_sys) pix_acc <= {1'b0, pix_acc[15:0]} + pix_inc;
wire ce_pix = pix_acc[16];

assign CLK_VIDEO = clk_sys;
// CE_PIXEL is assigned down in the VIDEO OUTPUT section, not here: with CRT
// Adjust on, the DAC is clocked by the module's slower read rate rather than
// by the core's native pixel enable. Assigning it here as well would be a
// multiple driver, and referencing rd_ce before its declaration would create
// an implicit 1-bit net (see the forward-declaration note above).

////////////////////   HPS I/O   ///////////////////

// Signal widths as hps_io.sv (MiSTer-devel/Template_MiSTer) declares them,
// truncated to this project's internal widths at the boundary below. Safe:
// ROM regions are well under 25 bits, ioctl_index values are 0-4, DIP/menu
// status bits are all in the low 32, and only joystick_0/1's low 16 bits are
// read.
//
// SD-card/disk-image, RTC, upload and UART ports are omitted rather than
// tied off, matching the minimal pattern shipped arcade cores use.
wire [31:0] joystick_0_w, joystick_1_w;
wire [21:0] gamma_bus;
wire        forced_scandoubler;
// direct_video is declared with the forward declarations near the top of the
// file -- the rotation/CRT guard uses it well before this point. Declaring it
// here as well would be a duplicate; using it up there without a declaration
// would silently create an implicit 1-bit net, which is the same trap already
// documented against `status` and the CE_PIXEL forward reference.

// ioctl_download is declared with the forward declarations near the top of the
// file -- assign LED_USER uses it before this point.
wire        ioctl_wr;
wire [26:0] ioctl_addr_w;
wire [7:0]  ioctl_dout;
wire [15:0] ioctl_index_w;
wire        ioctl_wait = 0;

// High score NVRAM save path. ioctl_upload and ioctl_din are hps_io's; the
// core drives ioctl_upload_req to ask for a write-back.
wire        ioctl_upload;
wire  [7:0] ioctl_din;
wire        ioctl_upload_req;

wire [10:0] ps2_key;

wire [127:0] status_w;
wire [1:0]   buttons;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.buttons(buttons),
	.status(status_w),
	// bit 0 (H0)   : hide Rotation, Flip and CRT Adjust while Direct Video is
	//                active. They are forced off in that mode regardless (see
	//                vid_direct_guard), so leaving them visible would offer
	//                settings that cannot take effect.
	//                POLARITY CHANGED -- this was ~direct_video, the inverse
	//                of the MiSTer convention. That was harmless only while
	//                nothing referenced H0; now that H0 is used it has to be
	//                the right way round, or these options would be hidden in
	//                exactly the case where they DO work.
	// bit 1 (H1)   : hide the three CRT Adjust amounts while it is Off.
	//                H<n> hides when the mask bit is 1, hence the inversion.
	.status_menumask({14'd0, ~status[35], direct_video}),

	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr_w),
	.ioctl_dout(ioctl_dout),
	.ioctl_index(ioctl_index_w),
	.ioctl_wait(ioctl_wait),

	// ---- high score NVRAM save path -------------------------------------
	// ioctl_upload_index tells the HPS WHICH region is being written back;
	// it must match the .mra's <nvram index="2"/> or the framework writes the
	// bytes to the wrong file.
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(ioctl_upload_req),
	.ioctl_upload_index(8'd2),
	.ioctl_din(ioctl_din),
	.ioctl_rd(),

	.joystick_0(joystick_0_w),
	.joystick_1(joystick_1_w),

	.ps2_key(ps2_key)
);

// Truncated to this project's own existing internal widths -- see the
// wide-signal comment above for why this is safe.
wire [15:0] joystick_0 = joystick_0_w[15:0];
wire [15:0] joystick_1 = joystick_1_w[15:0];
wire [24:0] ioctl_addr = ioctl_addr_w[24:0];
wire [7:0]  ioctl_index = ioctl_index_w[7:0];
assign      status = status_w[63:0];   // declared up top; see forward declarations

//------------------------------------------------------------------------
// MRA DIP switches.
//
// These do NOT arrive in `status[]`. MiSTer delivers an .mra's <switches>
// block as its own ioctl download with index 254, one byte per switch bank.
// The low status bits are already spoken for by the OSD menu, so reading DIPs
// from there would make a DIP selection silently change unrelated behaviour.
//
// POWER-UP DEFAULTS MATTER. Without an initialiser every switch reads 0x00
// until the index-254 download arrives -- or forever, if it never does. DSWA
// bit 3 is Demo Sounds (ids="Off,On"), so all-zeros disables demo sounds, and
// a game told not to make sounds never sends a sound command at all. Seeded
// with the .mra's own defaults ("fe,bf") so the core is correct from reset
// and the download merely confirms them.
reg [7:0] sw[8];
initial begin
	sw[0] = 8'hFE;   // DSWA
	sw[1] = 8'hBF;   // DSWB
	sw[2] = 8'hFF; sw[3] = 8'hFF; sw[4] = 8'hFF;
	sw[5] = 8'hFF; sw[6] = 8'hFF; sw[7] = 8'hFF;
end
always @(posedge clk_sys) begin
	if (ioctl_wr && (ioctl_index == 8'd254) && !ioctl_addr[24:3])
		sw[ioctl_addr[2:0]] <= ioctl_dout;
end

//------------------------------------------------------------------------
// Cabinet controls.
//
// MiSTer's joystick word puts directions in bits 3:0 and then the buttons
// named by CONF_STR's "J1," list from bit 4 upward. With
//   J1,Jump,Fire,Start 1P,Start 2P,Coin,Service
// that gives bit4=Jump, bit5=Fire, bit6=Start1P, bit7=Start2P, bit8=Coin,
// bit9=Service.
//
// Signals here are ACTIVE HIGH (1 = pressed). rbisland_top inverts them on
// the way to the C-chip, which is where the real cabinet polarity lives
// (MAME: coin inputs active high, start/service active low).
//
// Start/Coin are OR'd across both pads so either controller can insert a
// coin or start, which is the usual arcade-core convention. Player 2's
// own start is also accepted from pad 2's Start button.
wire [15:0] joy = joystick_0 | joystick_1;

wire m_start1  = joy[6];
wire m_start2  = joy[7] | joystick_1[6];
wire m_coin1   = joy[8];
wire m_coin2   = 1'b0;      // no second coin slot mapped
wire m_service = joy[9];
wire m_pause   = joy[10];   // CONF_STR "J1,...,Service,Pause" -> bit 10


////////////////////   RESET   ///////////////////

// Two things deliberately kept OUT of this expression:
//
// 1. `ioctl_download`. The CPUs and SDRAM arbiter must be held during a ROM
//    load (the arbiter's mode mux depends on it), but the video timing
//    generator must not: freezing hc/vc stops sync entirely, leaving the
//    display nothing to lock to while loading.
//
// 2. `status[0]`. It is simultaneously DSWA bit 0 (Cabinet) via the .mra's
//    <switches> block, so including it would put the core into permanent
//    reset whenever "Cocktail" is selected. RESET and buttons[1] already
//    provide the real reset paths.
wire reset       = RESET | status[0] | buttons[1] | ~pll_locked | ioctl_download;

// Video timing keeps running through ROM loading so the display stays
// locked and the loading screen is visible.
// Video timing free-runs: it is deliberately NOT gated on pll_locked or
// status[0]. If the PLL is unlocked there is no clock to run on anyway,
// so gating adds no protection -- it only creates a failure mode where
// the raster stays frozen and the display sees no sync at all ("no
// signal") instead of a black but valid picture.
wire reset_video = RESET | buttons[1];

// Reset for the SDRAM loaders. MUST NOT include ioctl_download.
//
// sdram_arbiter and gfx_rom_loader accept ROM bytes in the `else` branch
// of `if (reset)`. Feeding them the main `reset` -- which asserts for the
// whole of ioctl_download -- held them in reset for exactly the window
// in which they were supposed to be writing, so not one byte of ROM ever
// reached SDRAM. Their own header comments assumed the opposite ("downloads
// only happen while the core is held in reset"), which is what hid this.
wire reset_dl    = RESET | buttons[1] | ~pll_locked;

//------------------------------------------------------------------------
// PAUSE
//
// Ours, not the game's -- the PCB has no pause. Toggled on the button's
// RISING EDGE: a level would re-toggle on every clk_sys cycle the button is
// held, which at 48 MHz is not a toggle at all.
//
// Held clear while ROMs are loading and through reset, so the core can never
// come up paused with no way for the user to know why nothing is happening.
//
// The core freezes by clock-enable gating (see the pause inputs on
// cpu68k_wrapper / z80_sound_wrapper / ym2151_wrapper / rbisland_cchip) and
// paints a supporter panel via rtl/pause_overlay.sv. Video timing keeps
// running throughout, so sync is never interrupted.
//------------------------------------------------------------------------
reg pause_btn_d, paused;
always @(posedge clk_sys) begin
	pause_btn_d <= m_pause;
	if (reset || ioctl_download) paused <= 1'b0;
	else if (m_pause && !pause_btn_d) paused <= ~paused;
end

////////////////////   CORE (stub)   ///////////////////

wire [7:0]  r, g, b;
wire        hs, vs, hblank, vblank;
wire [15:0] audio_l, audio_r;

// Diagnostic and SDRAM-port nets. Declared HERE because the core instance
// immediately below connects to every one of them.
//
// Declaring them after the instance would make each an implicit 1-bit net at
// the point of connection -- Verilog permits that silently inside a port
// connection -- and sdram_addr* are [24:1] while the dbg_v_* set is [15:0].
// Quartus happens to merge the implicit net with the real declaration and get
// the widths right; a tool resolving it the other way would truncate them all
// to one bit.
//
// The blocks describing what each signal means stay at their original
// positions further down.
wire dbg_cpu_alive;
wire dbg_ever_as, dbg_ever_dtack, dbg_unmapped;
wire dbg_pal_wr, dbg_tile_wr, dbg_spr_wr, dbg_cchip_acc;
wire dbg_gfx_dl, dbg_gfx_nz, dbg_tilemap_nz, dbg_pal_nz, dbg_pix_nz;
wire dbg_palword_nz, dbg_rgb_nz, dbg_vid_run;
wire dbg_live_idx, dbg_live_word, dbg_live_rgb, dbg_live_lbw, dbg_bg_stuck;
wire dbg_live_lbwnz, dbg_live_gfxnz;
wire dbg_live_pxnz, dbg_live_attrnz, dbg_live_codenz;
wire [15:0] dbg_v_tile, dbg_v_gfx, dbg_v_palwr, dbg_v_palrd,
            dbg_v_pixidx, dbg_v_scroll, dbg_v_cnt,
            dbg_v_cchip, dbg_v_tilewr, dbg_v_palwrc,
            dbg_v_rom0, dbg_v_rom1, dbg_v_rom2, dbg_v_rom3,
            dbg_v_cpua, dbg_v_buscnt, dbg_v_asstuck,
            dbg_dl0, dbg_dl1, dbg_dl2, dbg_dl3, dbg_dl4;
wire [7:0] dbg_unmapped_addr;
wire [8:0] dbg_vpos, dbg_hpos;

// Port 0: rbisland_top's sdram_arbiter (68000 ROM download + runtime
// reads). Port 1: PC080SN tile gfx ROM. Port 2: PC090OJ sprite gfx ROM
// (both via rtl/gfx_rom_loader.sv instances inside rbisland_top).
wire [24:1] sdram_addr0, sdram_addr1, sdram_addr2;
wire [15:0] sdram_din0, sdram_dout0, sdram_din1, sdram_dout1, sdram_din2, sdram_dout2;
wire        sdram_wrl0, sdram_wrh0, sdram_req0, sdram_ack0;
wire        sdram_wrl1, sdram_wrh1, sdram_req1, sdram_ack1;
wire        sdram_wrl2, sdram_wrh2, sdram_req2, sdram_ack2;

// SOUND_SCRIPTS selects between the real hardware sound path (0) and a
// ym_script_player replaying MAME-captured YM2151 register streams (1).
//
// 0 is correct and is the default. The script player and its blob remain in
// the tree as a fallback; flipping this constant is the whole change.
//
// Three things the real path depends on, each easy to break:
//   - pc060ha_ciu.sv must apply its mode auto-increment on the FALLING edge
//     of chip-select (see that file)
//   - z80_ram_mem's read must be synchronous or block RAM inference fails
//     silently (rbisland_top.sv)
//   - the YM2151 write stretcher must not turn a following read into a
//     spurious write (ym2151_wrapper.sv)
rbisland_top #(
	.SOUND_SCRIPTS    (1'b0),
	// Irrelevant while SOUND_SCRIPTS = 0 (no script player is built at all),
	// but left explicit so the pair always reads as a deliberate choice.
	.SCRIPTS_EMBEDDED (1'b1)
) core
(
	.clk_sys    (clk_sys),
	.ce_8m      (ce_8m),
	.ce_4m      (ce_4m),
	.reset      (reset),
	.reset_video(reset_video),
	.reset_dl   (reset_dl),
	.dbg_cpu_alive  (dbg_cpu_alive),
	.dbg_ever_as    (dbg_ever_as),
	.dbg_ever_dtack (dbg_ever_dtack),
	.dbg_vpos       (dbg_vpos),
	.dbg_hpos       (dbg_hpos),
	.dbg_unmapped      (dbg_unmapped),
	.dbg_unmapped_addr (dbg_unmapped_addr),
	.dbg_pal_wr     (dbg_pal_wr),
	.dbg_tile_wr    (dbg_tile_wr),
	.dbg_spr_wr     (dbg_spr_wr),
	.dbg_cchip_acc  (dbg_cchip_acc),
	.dbg_gfx_dl     (dbg_gfx_dl),
	.dbg_gfx_nz     (dbg_gfx_nz),
	.dbg_tilemap_nz (dbg_tilemap_nz),
	.dbg_pal_nz     (dbg_pal_nz),
	.dbg_pix_nz     (dbg_pix_nz),
	.dbg_palword_nz (dbg_palword_nz),
	.dbg_rgb_nz     (dbg_rgb_nz),
	.dbg_vid_run    (dbg_vid_run),
	.dbg_live_idx   (dbg_live_idx),
	.dbg_live_word  (dbg_live_word),
	.dbg_live_rgb   (dbg_live_rgb),
	.dbg_live_lbw   (dbg_live_lbw),
	.dbg_bg_stuck   (dbg_bg_stuck),
	.dbg_live_lbwnz (dbg_live_lbwnz),
	.dbg_live_gfxnz (dbg_live_gfxnz),
	.dbg_live_pxnz  (dbg_live_pxnz),
	.dbg_live_attrnz(dbg_live_attrnz),
	.dbg_live_codenz(dbg_live_codenz),
	.dbg_v_tile     (dbg_v_tile),
	.dbg_v_gfx      (dbg_v_gfx),
	.dbg_v_palwr    (dbg_v_palwr),
	.dbg_v_palrd    (dbg_v_palrd),
	.dbg_v_pixidx   (dbg_v_pixidx),
	.dbg_v_scroll   (dbg_v_scroll),
	.dbg_v_cnt      (dbg_v_cnt),
	.dbg_v_cchip    (dbg_v_cchip),
	.dbg_v_tilewr   (dbg_v_tilewr),
	.dbg_v_palwrc   (dbg_v_palwrc),
	.dbg_dl0        (dbg_dl0),
	.dbg_dl1        (dbg_dl1),
	.dbg_dl2        (dbg_dl2),
	.dbg_dl3        (dbg_dl3),
	.dbg_dl4        (dbg_dl4),
	.dbg_v_rom0     (dbg_v_rom0),
	.dbg_v_rom1     (dbg_v_rom1),
	.dbg_v_rom2     (dbg_v_rom2),
	.dbg_v_rom3     (dbg_v_rom3),
	.dbg_v_cpua     (dbg_v_cpua),
	.dbg_v_buscnt   (dbg_v_buscnt),
	.dbg_v_asstuck  (dbg_v_asstuck),

	.joystick_0 (joystick_0),

	// TODO: not wired to real hps_io signals yet (sys/ isn't part of
	// this skeleton -- see README.md). Tied inactive so the core still
	// elaborates and runs; same status as the DIP switches.
	.coin1   (m_coin1),
	.coin2   (m_coin2),
	.start1  (m_start1),
	.start2  (m_start2),
	.service (m_service),
	.tilt    (1'b0),

	.dswa (sw[0]),
	.dswb (sw[1]),
	// hoffset/voffset are gone -- picture positioning moved to CRT Adjust at
	// the video output boundary below.
	.pause (paused),
	// Layer isolation and the BG vertical nudge were both debug controls and
	// their OSD entries are gone. layer_sel 0 is "show everything"; the nudge
	// is now a fixed Y_PIC_ADJ in rbisland_top.sv rather than a live offset.
	// The ports stay so the controls can be reinstated without rewiring.
	.layer_sel (2'd0),
	// coarse is in 16-line steps, fine in single lines; sum is 0-255.
	.bg_vadj   (9'd0),
	.bg_yneg   (1'b1),          // negated scrolly -- confirmed on hardware
	// DIAGNOSTIC TEST TONE -- HARD OFF.
	//
	// This was wired to status[3] with the comment "no OSD entry: off". It
	// had one: the legacy "O35,Scandoubler Fx" entry occupied bits 3..5, so
	// choosing HQ2x or CRT 50% set bit 3 and started the test tone over the
	// game. That was inaudible while the core was silent and is very audible
	// now that the real sound path is back. The Scandoubler Fx entry is gone
	// too -- it drove nothing (this core has no arcade_video/video_mixer
	// instance and assigns VGA_SL = 0).
	.snd_test  (1'b0),
	// SOUND PROBE. 1 = on, 0 = off. See the big comment in rbisland_top.sv.
	// Emits a boot report plus three activity tones on the mixer's spare PCM
	// channel, so one listen says which link in the sound chain is dead.
	// >>> SET BACK TO 2'd0 BEFORE THE NEXT PUBLIC RELEASE <<<
	.snd_diag  (SOUND_PROBE),
	.joystick_1 (joystick_1),

	.ioctl_download (ioctl_download),
	.ioctl_wr       (ioctl_wr),
	.ioctl_addr     (ioctl_addr),
	.ioctl_dout     (ioctl_dout),
	.ioctl_index    (ioctl_index),

	// High score NVRAM. The .mra supplies the region via
	// <nvram index="2" size="..."/> and hps_io streams it in on ioctl_index 2
	// like any other download, then answers ioctl_upload_req by raising
	// ioctl_upload and walking ioctl_addr.
	.ioctl_upload     (ioctl_upload),
	.ioctl_din        (ioctl_din),
	.ioctl_upload_req (ioctl_upload_req),
	// Load is automatic; this is the only save trigger. See the CONF_STR entry.
	.hs_save_req      (status[58]),

	.sdram_addr  (sdram_addr0),
	.sdram_din   (sdram_din0),
	.sdram_dout  (sdram_dout0),
	.sdram_wrl   (sdram_wrl0),
	.sdram_wrh   (sdram_wrh0),
	.sdram_req   (sdram_req0),
	.sdram_ack   (sdram_ack0),

	.gfx_addr  (sdram_addr1),
	.gfx_din   (sdram_din1),
	.gfx_dout  (sdram_dout1),
	.gfx_wrl   (sdram_wrl1),
	.gfx_wrh   (sdram_wrh1),
	.gfx_req   (sdram_req1),
	.gfx_ack   (sdram_ack1),

	.obj_addr  (sdram_addr2),
	.obj_din   (sdram_din2),
	.obj_dout  (sdram_dout2),
	.obj_wrl   (sdram_wrl2),
	.obj_wrh   (sdram_wrh2),
	.obj_req   (sdram_req2),
	.obj_ack   (sdram_ack2),

	.HBlank (hblank),
	.VBlank (vblank),
	.HSync  (hs),
	.VSync  (vs),
	.ce_pix (ce_pix),
	.R (r), .G (g), .B (b),

	.audio_l (audio_l),
	.audio_r (audio_r)
);

// Startup diagnostic colours, adopted from meathax/s32 (a core verified
// working on real hardware), which keeps valid sync running throughout
// startup and uses a solid colour to identify exactly which gate is
// holding the core. That turns a blank "no signal" into information:
//
//   BLUE   -> ioctl_download asserted (ROMs still loading)
//   YELLOW -> core held in reset (OSD reset, or PLL not locked)
//   game   -> normal video
//
// If the display shows a solid colour, sync is valid and the video path
// works -- the problem is whatever that colour identifies. If it still
// shows "no signal", the fault is upstream of this module entirely
// (project setup, clocking, or framework wiring), which is a completely
// different thing to investigate.
// Watch the 68000 heartbeat: if it stops toggling for ~0.35s the CPU is
// hung, which is otherwise indistinguishable from a legitimately black
// screen. Red = hung.
// (dbg_cpu_alive itself is declared above the core instance.)
reg  dbg_cpu_alive_d;
reg [23:0] cpu_stall_cnt;
reg        cpu_hung;
always @(posedge clk_sys) begin
	dbg_cpu_alive_d <= dbg_cpu_alive;
	if (reset) begin
		cpu_stall_cnt <= 0;
		cpu_hung      <= 1'b0;
	end else if (dbg_cpu_alive != dbg_cpu_alive_d) begin
		cpu_stall_cnt <= 0;                 // CPU ran a bus cycle
		cpu_hung      <= 1'b0;
	end else if (&cpu_stall_cnt) begin
		cpu_hung      <= 1'b1;              // no bus cycle for 2^24 clocks
	end else begin
		cpu_stall_cnt <= cpu_stall_cnt + 1'd1;
	end
end

// Is the SDRAM controller alive at all? sdram_ack0 toggles once per
// completed access. NOTE this cannot by itself distinguish "controller
// dead" from "nobody ever asked" -- on the previous hardware run magenta
// actually meant the latter: the 68000 was issuing no bus cycles at all
// (its phi clock enables were gated off during reset, see
// cpu68k_wrapper.sv), so no SDRAM request was ever made and the absence
// of acks was a symptom, not the cause.
reg sdram_ack_d;
reg [23:0] sdram_idle_cnt;
reg        sdram_dead;
always @(posedge clk_sys) begin
	sdram_ack_d <= sdram_ack0;
	if (reset) begin
		sdram_idle_cnt <= 0;
		sdram_dead     <= 1'b0;
	end else if (sdram_ack0 != sdram_ack_d) begin
		sdram_idle_cnt <= 0;
		sdram_dead     <= 1'b0;
	end else if (&sdram_idle_cnt) begin
		sdram_dead     <= 1'b1;
	end else begin
		sdram_idle_cnt <= sdram_idle_cnt + 1'd1;
	end
end

//------------------------------------------------------------------------
// Diagnostic bar display, shown only while the CPU is hung.
//
// Four stacked horizontal bars, each GREEN if the event has ever occurred
// and RED if it never has. A single colour cannot distinguish "never
// started" from "started once then stalled":
//
//   bar 1 (top)    ROM download completed
//   bar 2          68000 asserted AS_n (it fetched at least once)
//   bar 3          SDRAM acknowledged at least one access
//   bar 4 (bottom) DTACK was asserted at least once
//
// Reading it:
//   all red          -> core never came out of reset / no clock
//   1 green, rest red-> CPU never ran at all (clock enable / reset issue)
//   1,2 green, 3 red -> CPU fetched but SDRAM never responded
//   1,2,3 green, 4 red-> SDRAM responded but DTACK never reached the CPU
//   all green        -> bus works; the fault is further downstream
//------------------------------------------------------------------------
// (The dbg_* nets this section describes are all declared above the core
// instance, so that the instance's port connections do not create implicit
// 1-bit nets ahead of the real declarations.)

reg dl_done;
always @(posedge clk_sys) if (!pll_locked) dl_done <= 1'b0;
                          else if (ioctl_download) dl_done <= 1'b1;
reg dl_finished;
always @(posedge clk_sys) if (!pll_locked) dl_finished <= 1'b0;
                          else if (dl_done && !ioctl_download) dl_finished <= 1'b1;

reg ever_ack;
always @(posedge clk_sys) if (!pll_locked) ever_ack <= 1'b0;
                          else if (sdram_ack0 != sdram_ack_d) ever_ack <= 1'b1;

// 8 bands, green = "has happened at least once", red = never.
//
//   1 ROM download completed
//   2 68000 issued a bus cycle
//   3 SDRAM acknowledged an access
//   4 DTACK asserted
//   5 game wrote PALETTE RAM
//   6 game wrote TILEMAP RAM
//   7 game wrote SPRITE RAM
//   8 game accessed the C-CHIP
//
// Bands 1-4 confirm the bus works; 5-8 say how far the program actually
// got. A black screen with all of 5-7 red means the game is running but
// has not drawn anything -- typically stuck in an early wait loop, and
// band 8 then says whether it is talking to the C-chip while it waits.
wire [2:0] dbg_bar = dbg_vpos[7:5];
// Bands 1-4 of the previous set all read green on hardware, so the CPU,
// bus, SDRAM and DTACK are all confirmed good and no longer worth screen
// space. These follow the PIXEL path instead, which is where the picture
// is actually being lost:
//
//   1 tile GFX ROM received download data
//   2 tile GFX ROM read back NON-ZERO data
//   3 tilemap RAM read back NON-ZERO data
//   4 a NON-ZERO colour was written to the palette
//   5 a NON-ZERO palette index reached the video output
//   6 game wrote tilemap RAM      (kept - known green)
//   7 game wrote sprite RAM       (kept - known green)
//   8 game accessed the C-chip    (kept - known green)
//
// The first RED band going down the screen is the point where pixel data
// stops flowing. E.g. 1 green / 2 red means the GFX ROM downloaded but
// reads back as zeros (an SDRAM port or arbiter fault); 2 green / 5 red
// means real tile data exists but never becomes a visible pixel index.
// Everything upstream now reads green on hardware, so these zoom in on the
// final three steps, which is the only place the picture can still be
// getting lost:
//
//   1 video timing running (VBlank edges seen)
//   2 a NON-ZERO palette index reached the output      (known green)
//   3 a NON-ZERO colour was WRITTEN to the palette     (known green)
//   4 the palette READ returned a NON-ZERO colour word  <-- decisive
//   5 a NON-ZERO RGB value left rbisland_top            <-- decisive
//   6 tile GFX ROM read back non-zero data             (known green)
//   7 tilemap RAM read back non-zero data              (known green)
//   8 game accessed the C-chip                         (known green)
//
// If 4 is RED the palette lookup itself is broken (addressing, or writes
// not persisting) despite both the index and the written colours being
// fine. If 4 is GREEN and 5 is RED, the colour exists but the RGB
// extraction or output gating is dropping it.
// Bands 1-3 are LIVE per-frame measurements (recounted every frame,
// green only if >1000 pixels qualified THIS frame). Bands 4-8 are the
// sticky flags, kept for reference.
//
//   1 >1000 pixels had a non-zero palette INDEX     this frame
//   2 >1000 pixels had a non-zero palette WORD      this frame
//   3 >1000 pixels had non-zero RGB output          this frame
//   4 video timing running (VBlank edges seen)
//   5 a non-zero colour was ever written to palette  (sticky)
//   6 tile GFX ROM ever read back non-zero data      (sticky)
//   7 tilemap RAM ever read back non-zero data       (sticky)
//   8 C-chip ever accessed                           (sticky)
//
// The sticky flags all read green but latch on a single pixel, so they
// could not distinguish a one-off during boot from a live picture. If
// bands 1-3 are RED while 5-8 are green, the pipeline worked briefly and
// is now producing nothing -- a very different fault from never working.
// Bands 1-3 read RED on hardware: essentially every pixel resolves to
// palette index 0, every frame. So the line buffers are not being filled.
// Band 1 now looks INSIDE the BG renderer's fetch FSM.
//
//   1 >1000 BG line-buffer writes this frame   <-- is the fetch running at all?
//   2 BG fetch FSM NOT stuck (green = healthy) <-- inverted: red = wedged
//   3 >1000 non-zero palette indices this frame (known red)
//   4 video timing running                      (known green)
//   5 non-zero colour ever written to palette   (known green)
//   6 tile GFX ROM ever read non-zero           (known green)
//   7 tilemap RAM ever read non-zero            (known green)
//   8 C-chip ever accessed                      (known green)
//
// Band 1 red + band 2 red  -> the fetch FSM is wedged in one state, almost
//                             certainly waiting on a gfx-ROM handshake that
//                             never completes.
// Band 1 red + band 2 green-> the FSM cycles but never reaches its write
//                             stage, i.e. it is being restarted early.
// Band 1 green             -> pixels ARE written, so the fault is after the
//                             line buffer (read side or palette lookup).
// Previous result: band 1 (writes happening) GREEN, band 2 (FSM healthy)
// GREEN, band 3 (non-zero indices) RED. So the fetch FSM runs and writes
// to the line buffer thousands of times per frame -- but what comes back
// out is index 0. The obvious remaining possibility is that it is writing
// ZEROS, which a write-counter cannot distinguish. These two bands
// measure the DATA rather than the event:
//
//   1 >1000 line-buffer writes carrying a NON-ZERO pixel  this frame
//   2 >1000 gfx-ROM reads returning NON-ZERO data         this frame
//   3 >1000 non-zero palette indices out                  (known red)
//
// 1 red + 2 red   -> the tile ROM is returning zeros at runtime, so the
//                    renderer faithfully writes blank pixels. Fault is in
//                    the shared ROM read path (gfx_read_arbiter2 / SDRAM
//                    port 1), not the renderer.
// 1 red + 2 green -> real ROM data arrives but the renderer turns it into
//                    zero pixels: tile decode or the attribute/index build.
// 1 green         -> non-zero pixels ARE written, so the fault is on the
//                    line-buffer read side (address, or the buffer swap).
//------------------------------------------------------------------------
// VALUE OVERLAY
//
// The boolean bands could only report "something happened at least once",
// which repeatedly proved too coarse -- most recently every band read
// green while the screen stayed black. This shows actual 16-bit VALUES as
// bit patterns, so one boot reports what the hardware is really reading.
//
// Layout: 8 rows (32 scanlines each) x 16 bit-cells (18px each), MSB left.
// A cell is BRIGHT GREEN for 1 and DARK RED for 0, with black gaps.
//
//   row 1  first non-zero TILEMAP word read by the BG renderer
//   row 2  first non-zero GFX-ROM word read by the BG renderer
//   row 3  first non-zero PALETTE word written by the 68000
//   row 4  first non-zero PALETTE word read back at the video output
//   row 5  C-CHIP accesses in the last frame   <-- live, not sticky
//   row 6  TILEMAP writes in the last frame     <-- live, not sticky
//   row 7  non-zero pixels in the last frame (value >> 4)
//   row 8  status bits, MSB first: video_run, live_idx, live_word,
//          live_rgb, live_lbw, live_pxnz, live_attrnz, live_codenz,
//          then gfx_nz, tilemap_nz, pal_nz, cchip, ever_as, ever_dtack,
//          unmapped, bg_stuck
//
// An all-zero row is itself the answer: e.g. row 1 blank means the BG
// renderer reads the tilemap as zeros no matter what the CPU wrote.
// 4x6 hex font for the debug overlay. Makes a photograph of the screen
// directly readable as numbers instead of requiring bit positions to be
// counted by hand.
function [3:0] dbgfont(input [3:0] d, input [2:0] r);
	case ({d, r})
		7'h00: dbgfont = 4'b1111;
		7'h01: dbgfont = 4'b1001;
		7'h02: dbgfont = 4'b1001;
		7'h03: dbgfont = 4'b1001;
		7'h04: dbgfont = 4'b1001;
		7'h05: dbgfont = 4'b1111;
		7'h08: dbgfont = 4'b0010;
		7'h09: dbgfont = 4'b0110;
		7'h0A: dbgfont = 4'b0010;
		7'h0B: dbgfont = 4'b0010;
		7'h0C: dbgfont = 4'b0010;
		7'h0D: dbgfont = 4'b0111;
		7'h10: dbgfont = 4'b1111;
		7'h11: dbgfont = 4'b0001;
		7'h12: dbgfont = 4'b1111;
		7'h13: dbgfont = 4'b1000;
		7'h14: dbgfont = 4'b1000;
		7'h15: dbgfont = 4'b1111;
		7'h18: dbgfont = 4'b1111;
		7'h19: dbgfont = 4'b0001;
		7'h1A: dbgfont = 4'b0111;
		7'h1B: dbgfont = 4'b0001;
		7'h1C: dbgfont = 4'b0001;
		7'h1D: dbgfont = 4'b1111;
		7'h20: dbgfont = 4'b1001;
		7'h21: dbgfont = 4'b1001;
		7'h22: dbgfont = 4'b1111;
		7'h23: dbgfont = 4'b0001;
		7'h24: dbgfont = 4'b0001;
		7'h25: dbgfont = 4'b0001;
		7'h28: dbgfont = 4'b1111;
		7'h29: dbgfont = 4'b1000;
		7'h2A: dbgfont = 4'b1111;
		7'h2B: dbgfont = 4'b0001;
		7'h2C: dbgfont = 4'b0001;
		7'h2D: dbgfont = 4'b1111;
		7'h30: dbgfont = 4'b1111;
		7'h31: dbgfont = 4'b1000;
		7'h32: dbgfont = 4'b1111;
		7'h33: dbgfont = 4'b1001;
		7'h34: dbgfont = 4'b1001;
		7'h35: dbgfont = 4'b1111;
		7'h38: dbgfont = 4'b1111;
		7'h39: dbgfont = 4'b0001;
		7'h3A: dbgfont = 4'b0010;
		7'h3B: dbgfont = 4'b0100;
		7'h3C: dbgfont = 4'b0100;
		7'h3D: dbgfont = 4'b0100;
		7'h40: dbgfont = 4'b1111;
		7'h41: dbgfont = 4'b1001;
		7'h42: dbgfont = 4'b1111;
		7'h43: dbgfont = 4'b1001;
		7'h44: dbgfont = 4'b1001;
		7'h45: dbgfont = 4'b1111;
		7'h48: dbgfont = 4'b1111;
		7'h49: dbgfont = 4'b1001;
		7'h4A: dbgfont = 4'b1111;
		7'h4B: dbgfont = 4'b0001;
		7'h4C: dbgfont = 4'b0001;
		7'h4D: dbgfont = 4'b1111;
		7'h50: dbgfont = 4'b0110;
		7'h51: dbgfont = 4'b1001;
		7'h52: dbgfont = 4'b1111;
		7'h53: dbgfont = 4'b1001;
		7'h54: dbgfont = 4'b1001;
		7'h55: dbgfont = 4'b1001;
		7'h58: dbgfont = 4'b1110;
		7'h59: dbgfont = 4'b1001;
		7'h5A: dbgfont = 4'b1110;
		7'h5B: dbgfont = 4'b1001;
		7'h5C: dbgfont = 4'b1001;
		7'h5D: dbgfont = 4'b1110;
		7'h60: dbgfont = 4'b1111;
		7'h61: dbgfont = 4'b1000;
		7'h62: dbgfont = 4'b1000;
		7'h63: dbgfont = 4'b1000;
		7'h64: dbgfont = 4'b1000;
		7'h65: dbgfont = 4'b1111;
		7'h68: dbgfont = 4'b1110;
		7'h69: dbgfont = 4'b1001;
		7'h6A: dbgfont = 4'b1001;
		7'h6B: dbgfont = 4'b1001;
		7'h6C: dbgfont = 4'b1001;
		7'h6D: dbgfont = 4'b1110;
		7'h70: dbgfont = 4'b1111;
		7'h71: dbgfont = 4'b1000;
		7'h72: dbgfont = 4'b1110;
		7'h73: dbgfont = 4'b1000;
		7'h74: dbgfont = 4'b1000;
		7'h75: dbgfont = 4'b1111;
		7'h78: dbgfont = 4'b1111;
		7'h79: dbgfont = 4'b1000;
		7'h7A: dbgfont = 4'b1110;
		7'h7B: dbgfont = 4'b1000;
		7'h7C: dbgfont = 4'b1000;
		7'h7D: dbgfont = 4'b1000;
		default: dbgfont = 4'b0000;
	endcase
endfunction

// 28-line rows, so all EIGHT fit within the 224 visible lines.
// The previous 32-line rows totalled 256 and pushed row 7 -- the status
// word, the single most informative row -- entirely into vblank where it
// could never be photographed.
wire [8:0] vp = dbg_vpos;
wire [2:0] v_row = (vp <  9'd28) ? 3'd0 : (vp <  9'd56) ? 3'd1 :
                   (vp <  9'd84) ? 3'd2 : (vp < 9'd112) ? 3'd3 :
                   (vp < 9'd140) ? 3'd4 : (vp < 9'd168) ? 3'd5 :
                   (vp < 9'd196) ? 3'd6 :                 3'd7 ;
wire [8:0] v_rowtop = {6'd0,v_row} * 9'd28;
wire [4:0] v_yin    = vp - v_rowtop;
// Layout: 5 glyph slots per row, 24px wide each, starting at x=16.
//   slot 0 = row NUMBER (so a photo identifies each line unambiguously)
//   slots 1-4 = the 16-bit value as four hex digits, MSB first
// Glyphs are the 4x6 font above scaled 6x horizontally and 4x vertically.
wire [8:0] v_x    = dbg_hpos - 9'd16;
wire [2:0] v_slot = v_x[8:0] / 9'd24;
wire [1:0] v_cx   = (v_x % 9'd24) / 9'd6;      // 0..3 within the glyph
wire [4:0] v_y    = v_yin;
wire [2:0] v_cy   = (v_y - 5'd4) >> 2;         // 0..5 within the glyph
wire v_inbox = (dbg_hpos >= 9'd16) && (v_slot < 3'd5) && (v_y >= 5'd2) && (v_y < 5'd26);

// Row 8: 16 status bits, MSB first -- video_run, live_idx, live_word,
// live_rgb, live_lbw, live_pxnz, live_attrnz, live_codenz, gfx_nz,
// tilemap_nz, pal_nz, cchip, ever_as, ever_dtack, unmapped, bg_stuck.
wire [15:0] v_status = {dbg_vid_run, dbg_live_idx, dbg_live_word, dbg_live_rgb,
                        dbg_live_lbw, dbg_live_pxnz, dbg_live_attrnz, dbg_live_codenz,
                        dbg_live_gfxnz, dbg_tilemap_nz, dbg_pal_nz, dbg_cchip_acc,
                        dbg_ever_as, dbg_ever_dtack, dbg_unmapped, dbg_bg_stuck};

// These rows look at the CPU itself rather than downstream of it, for the
// case where the 68000 is not executing game code at all.
//
//   0-3  the FIRST FOUR ROM WORDS the CPU reads = the 68000 reset vector.
//        Words 0-1 are the initial stack pointer, words 2-3 the initial PC.
//        For a correct rbisland image the PC must land inside 0x000000-
//        0x07FFFF. Nonsense here means the ROM image itself is wrong
//        (byte order, part order, or the region never loaded) -- this reads
//        the real bytes instead of reasoning about the .mra.
//   4    a recent 68000 address, top bits -- where it is executing/looping
//   5    68000 bus cycles in the last frame -- alive vs spinning vs idle
//   6    clocks AS_n has been continuously low. The download counter that
//        was here has done its job: it read 0800, so the full 512KB does
//        arrive. The open question moved to why the CPU stops, and row 5
//        alone cannot answer it -- zero bus cycles in a frame means either
//        "stalled mid-cycle waiting for DTACK" or "genuinely stopped", and
//        this row separates them. FFFF (saturated) is a DTACK stall;
//        0000 or a small number is a CPU that is not stuck on the bus.
//   7    status bits
wire [15:0] v_word = (v_row == 3'd0) ? dbg_v_rom0   :
                     (v_row == 3'd1) ? dbg_v_rom1   :
                     (v_row == 3'd2) ? dbg_v_rom2   :
                     (v_row == 3'd3) ? dbg_v_rom3   :
                     (v_row == 3'd4) ? dbg_v_cpua   :
                     (v_row == 3'd5) ? dbg_v_buscnt :
                     (v_row == 3'd6) ? dbg_v_asstuck:
                                       v_status     ;

wire [3:0] v_digit = (v_slot == 3'd0) ? {1'b0, v_row}   :
                     (v_slot == 3'd1) ? v_word[15:12]   :
                     (v_slot == 3'd2) ? v_word[11:8]    :
                     (v_slot == 3'd3) ? v_word[7:4]     :
                                        v_word[3:0]     ;

// A function call's result cannot be bit-indexed directly in a continuous
// assignment, so take it into a net first.
wire [3:0] v_fontrow = dbgfont(v_digit, v_cy);
wire       v_on      = v_inbox && v_fontrow[2'd3 - v_cx];
// Black gaps between rows and between bit cells keep it readable.
// White digits on dark blue photograph far more clearly than colour-coded
// cells, and the row number in slot 0 removes any counting ambiguity.
wire [23:0] dbg_rgb = v_on ? 24'hFFFFFF : 24'h000030;

// The hex overlay is GONE from the video path.
//
// Nothing forces it on. Diagnosing from a photographed screen is replaced by
// simulating the whole core locally (sim/run_boot.bat), so the game gets the
// display to itself.
//
// The dbg_* signals and the font are deliberately left in the file. They
// cost nothing that matters (the design sits at 31% of the device) and
// re-attaching them is a one line change if it is ever wanted again.
//
// Blue during the ROM load stays: it is the standard MiSTer convention and
// it is the only feedback that the .mra is being read at all.
wire [23:0] rgb_out = ioctl_download ? 24'h0000C0 :  // blue = loading ROMs
                                       {r, g, b};

wire [7:0] av_r = rgb_out[23:16];
wire [7:0] av_g = rgb_out[15:8];
wire [7:0] av_b = rgb_out[7:0];

//============================================================================
// CRT ADJUST  (rmonic79/MiSTer-CRT-Adjust, rtl/crt/crt_adjust.sv)
//
// Core-side integration: the module sits at this core's video output boundary
// and sys/ is not modified at all. Wiring follows examples/core_side_snippet.v
// from that repository, with the read-rate generator resized for THIS core --
// see the note on it below, which is the one place the reference glue could
// not be copied verbatim.
//============================================================================

//---- OSD decode ------------------------------------------------------------
// Registered at ce_pix rather than used combinationally, so an OSD change
// cannot land in the middle of a line.
// Available under Direct Video as well -- see the vid_direct_guard block.
reg crt_on;
always @(posedge clk_sys) if (ce_pix) crt_on <= status[35];

reg signed [4:0] hsize_s;      // -16..+15
always @(posedge clk_sys) if (ce_pix) hsize_s <= $signed(status[40:36]);

reg signed [6:0] hpos_s;       // -64..+63, working range +-48
always @(posedge clk_sys) if (ce_pix) hpos_s <= $signed(status[47:41]);
wire signed [8:0] hpos_off = {{2{hpos_s[6]}}, hpos_s};

reg signed [5:0] vshift_off;   // -16..+15 lines (5-bit field, 6-bit port)
always @(posedge clk_sys) if (ce_pix) vshift_off <= $signed(status[52:48]);

//---- Read clock-enable -----------------------------------------------------
// THE ONE PIECE THAT COULD NOT BE COPIED FROM THE REFERENCE GLUE.
//
// The snippet counts quarter-cycles of clk_sys and uses base = 64, because it
// targets a 96 MHz clock with a 6 MHz pixel rate: (96/6) x 4 = 64 quarters,
// and one quarter is ~1.5% of that.
//
// This core cannot use that. Its pixel rate is 6.6714 MHz from a 48 MHz clock
// -- deliberately NOT an integer division, because the real board runs video
// from a separate 26.686 MHz crystal (see the PIX_INC comment above). The
// equivalent base would be (48/6.6714) x 4 = 28.8 quarters: not an integer,
// and one quarter of it would be a 3.4% step, more than double the ~1.5% the
// module is designed around.
//
// So the read rate is generated the same way this core already generates
// ce_pix -- a fractional accumulator -- with the INCREMENT varied instead of a
// quarter-cycle period. Read period = base + hsize means read RATE scales as
// 1/(base+hsize), so a slower increment reads slower and stretches the image:
//
//     rd_inc = pix_inc - hsize x 137,   137 = 1.5% of 9109
//
// giving exactly the intended ~1.5% per step at either refresh setting, and
// hsize > 0 -> slower read -> WIDER pixels, which is the module's documented
// convention.
//
// CRITICAL, and called out in bold by both the module header and the
// integration doc: the accumulator resets on the rise of the module's
// hs_ref_out, NOT on the raw HSync. hs_ref_out is the reference the module's
// own write side and read counter restart on, and sharing that one edge is
// what keeps all three in phase. Resetting on raw HSync is precisely what
// desynced the older upstream scheme when shrinking.
wire hs_ref;
reg  hs_ref_d;
always @(posedge clk_sys) hs_ref_d <= hs_ref;
wire hs_ref_rise = hs_ref & ~hs_ref_d;

wire signed [16:0] hsize_ext = {{12{hsize_s[4]}}, hsize_s};
wire signed [16:0] rd_inc_s  = $signed({1'b0, pix_inc}) - hsize_ext * 17'sd137;
wire        [15:0] rd_inc    = rd_inc_s[15:0];

reg [16:0] rd_acc;
always @(posedge clk_sys) begin
	if (hs_ref_rise) rd_acc <= 17'd0;
	else             rd_acc <= {1'b0, rd_acc[15:0]} + {1'b0, rd_inc};
end
wire rd_tick = rd_acc[16];
wire rd_ce   = crt_on ? rd_tick : ce_pix;

//---- The module ------------------------------------------------------------
// HPOS_MODE = 1 (CONTENTSHIFT): shifts the content, HSync stays native.
// Correct for this game -- 320 active pixels on a 424-pixel line with 44/28
// front/back porch is the "wide / centered" case the module documents.
// SYNCSHIFT (0) is for narrow, side-anchored games with a big asymmetric back
// porch, which this is not.
//
// VTOTAL/HTOTAL must track rtl/video.sv (263 x 424, both from jotego's
// PCB-measured Rastan timings). VTOTAL sizes the V-Shift line shift register.
wire [7:0] str_r, str_g, str_b;
wire       str_hs, str_vs, str_hb, str_vb;

crt_adjust #(
	.VTOTAL    (263),
	.HTOTAL    (424),
	.HPOS_MODE (1)
) u_crt_adjust
(
	.clk      (clk_sys),
	.pxl_cen  (ce_pix),      // write rate: the core's native pixel enable
	.pxl2_cen (rd_ce),       // read rate: scaled by H-Size
	.active   (crt_on),

	.hsize    (hsize_s),
	.hoffset  (hpos_off),
	.voffset  (vshift_off),

	.r_in     (av_r), .g_in (av_g), .b_in (av_b),
	// RAW sync in. The module derives its own reference from these; nothing
	// upstream shifts them any more (see rtl/video.sv).
	.hs_in    (hs),
	.vs_in    (vs),
	.hb_in    (hblank | vblank),
	// TRUE vertical blank, not the combined DE. The module uses this to drop
	// its active window during VBlank so the OSD can find the frame's vertical
	// boundary and stay visible.
	.vb_in    (vblank),

	.r_out    (str_r), .g_out (str_g), .b_out (str_b),
	.hs_out   (str_hs), .vs_out (str_vs),
	.hb_out   (str_hb), .vb_out (str_vb),
	.hs_ref_out (hs_ref)
);

//---- OSD anchoring ---------------------------------------------------------
// The MiSTer OSD centres itself on the RISING edge of VGA_DE. If DE followed
// the module's shifted str_hb, the OSD would slide across the screen with the
// picture whenever H-Position is used. Anchor its rising edge to the NATIVE
// active region and let it fall with the stretched one: the image moves, the
// OSD stays put.
//
// dbg_hpos is rbisland_top's own horizontal counter (video.sv's hc), which is
// exactly the `timing_hpos` the reference glue asks for. It is 9 bits and
// H_TOTAL is 424, so it represents the full line without truncation.
wire line_tick = ce_pix && (dbg_hpos == 9'd423);
reg  vblank_1l;
always @(posedge clk_sys) if (line_tick) vblank_1l <= vblank;
wire native_active = ~(hblank | vblank_1l);
reg  native_active_d;
always @(posedge clk_sys) if (ce_pix) native_active_d <= native_active;
wire native_rise = native_active & ~native_active_d;

wire str_active = ~str_hb;
reg  str_active_d;
always @(posedge clk_sys) if (rd_ce) str_active_d <= str_active;
wire str_fall = str_active_d & ~str_active;

reg de_osd;
always @(posedge clk_sys) begin
	if      (native_rise) de_osd <= 1'b1;
	else if (str_fall)    de_osd <= 1'b0;
end

//---- Output ----------------------------------------------------------------
// Off = native passthrough, bit-identical to a build without this module.
// Named wires rather than assigning the output ports and then reading them
// back. Kept from the (reverted) screen_rotate attempt because anything that
// needs to TAP the finished video -- rotation, a capture, a probe -- must see
// exactly what leaves the core, and a local net makes that provable.
// See doc/ARCHITECTURE.md section 3 for why rotation is blocked.
wire [7:0] vid_r  = crt_on ? str_r  : av_r;
wire [7:0] vid_g  = crt_on ? str_g  : av_g;
wire [7:0] vid_b  = crt_on ? str_b  : av_b;
wire       vid_hs = crt_on ? str_hs : hs;
wire       vid_vs = crt_on ? str_vs : vs;
wire       vid_de = crt_on ? de_osd : ~(hblank | vblank);
wire       vid_ce = crt_on ? rd_ce  : ce_pix;

assign VGA_R  = vid_r;
assign VGA_G  = vid_g;
assign VGA_B  = vid_b;
assign VGA_HS = vid_hs;
assign VGA_VS = vid_vs;
assign VGA_DE = vid_de;
assign CE_PIXEL = vid_ce;
assign VGA_SL = 0;

//============================================================================
// SCREEN ROTATION / FLIP  (sys/arcade_video.v, module screen_rotate)
//
// NOT in the video path -- it has no RGB outputs. It TAPS the finished video
// above, writes each frame into a DDR3 framebuffer and hands sys_top the FB_*
// descriptor; when FB_EN is high sys_top scans out from that buffer instead
// of from VGA_*. With Rotation Off, FB_EN is low and the output is
// bit-identical to a build without this module.
//
// Fed the POST-CRT-Adjust video deliberately: rotating first would leave
// H-Size and H-Position acting on what is now the vertical axis.
//============================================================================
`ifdef MISTER_FB
screen_rotate screen_rotate
(
	.CLK_VIDEO (CLK_VIDEO),
	.CE_PIXEL  (vid_ce),

	.VGA_R  (vid_r),  .VGA_G  (vid_g),  .VGA_B  (vid_b),
	.VGA_HS (vid_hs), .VGA_VS (vid_vs), .VGA_DE (vid_de),

	.rotate_ccw (rotate_ccw),
	.no_rotate  (no_rotate),
	// Passed through unmasked: screen_rotate gates it internally, so the
	// behaviour lives in one place instead of two.
	.flip       (vid_flip),
	.video_rotated (),

	.FB_EN     (FB_EN),     .FB_FORMAT (FB_FORMAT),
	.FB_WIDTH  (FB_WIDTH),  .FB_HEIGHT (FB_HEIGHT),
	.FB_BASE   (FB_BASE),   .FB_STRIDE (FB_STRIDE),
	.FB_VBL    (FB_VBL),    .FB_LL     (FB_LL),

	.DDRAM_CLK      (DDRAM_CLK),      .DDRAM_BUSY (DDRAM_BUSY),
	.DDRAM_BURSTCNT (DDRAM_BURSTCNT), .DDRAM_ADDR (DDRAM_ADDR),
	.DDRAM_DIN      (DDRAM_DIN),      .DDRAM_BE   (DDRAM_BE),
	.DDRAM_WE       (DDRAM_WE),       .DDRAM_RD   (DDRAM_RD)
);
`else
// No framebuffer, so nothing in this core uses DDR3. sys_top wires the DDRAM_*
// ports unconditionally (they are outside its `ifdef MISTER_FB), so they must
// still be driven to something definite rather than left floating.
assign DDRAM_CLK      = clk_sys;
assign DDRAM_BURSTCNT = 8'd0;
assign DDRAM_ADDR     = 29'd0;
assign DDRAM_DIN      = 64'd0;
assign DDRAM_BE       = 8'd0;
assign DDRAM_WE       = 1'b0;
assign DDRAM_RD       = 1'b0;
`endif


assign AUDIO_L = audio_l;
assign AUDIO_R = audio_r;

////////////////////   SDRAM   ///////////////////

// SDRAM init pulse.
//
// rtl/sdram.sv begins its power-up sequence on the FALLING EDGE of `init`
// (`if(init_old & ~init) reset <= 5'h1f;`). Driving that directly from
// ~pll_locked is unsafe here because
// clk_sys is itself an output of that PLL: until the PLL locks there is no
// clock, so the controller can never sample init while it is HIGH, and by
// the time clocking starts init is already low. The falling edge is missed,
// the SDRAM is never initialised, it never acknowledges a request, and the
// 68000 stalls forever on its first ROM fetch waiting for DTACK.
//
// Instead hold init high for 256 clocks AFTER the PLL reports lock, then
// drop it. That guarantees a clean falling edge observed by a running
// clock, and also gives the SDRAM its required post-power-up settling time.
reg        sdram_init = 1'b1;
reg  [7:0] sdram_init_cnt = 8'd0;
always @(posedge clk_sys) begin
	if (!pll_locked) begin
		sdram_init_cnt <= 8'd0;
		sdram_init     <= 1'b1;
	end else if (sdram_init_cnt != 8'hFF) begin
		sdram_init_cnt <= sdram_init_cnt + 8'd1;
	end else begin
		sdram_init     <= 1'b0;          // falling edge, clock definitely running
	end
end

// The sdram_* port nets are declared above the rbisland_top instance, which
// connects to them long before this point.

sdram sdram
(
	.SDRAM_CLK  (SDRAM_CLK),
	.SDRAM_CKE  (SDRAM_CKE),
	.SDRAM_A    (SDRAM_A),
	.SDRAM_BA   (SDRAM_BA),
	.SDRAM_DQ   (SDRAM_DQ),
	.SDRAM_DQML (SDRAM_DQML),
	.SDRAM_DQMH (SDRAM_DQMH),
	.SDRAM_nCS  (SDRAM_nCS),
	.SDRAM_nCAS (SDRAM_nCAS),
	.SDRAM_nRAS (SDRAM_nRAS),
	.SDRAM_nWE  (SDRAM_nWE),

	.init       (sdram_init),
	.clk        (clk_sys),

	.addr0 (sdram_addr0), .wrl0 (sdram_wrl0), .wrh0 (sdram_wrh0),
	.din0  (sdram_din0),  .dout0 (sdram_dout0),
	.req0  (sdram_req0),  .ack0  (sdram_ack0),

	.addr1 (sdram_addr1), .wrl1 (sdram_wrl1), .wrh1 (sdram_wrh1),
	.din1  (sdram_din1),  .dout1 (sdram_dout1),
	.req1  (sdram_req1),  .ack1  (sdram_ack1),

	.addr2 (sdram_addr2), .wrl2 (sdram_wrl2), .wrh2 (sdram_wrh2),
	.din2  (sdram_din2),  .dout2 (sdram_dout2),
	.req2  (sdram_req2),  .ack2  (sdram_ack2),

	// ---- burst extension, TIED OFF for the Rainbow Islands build --------
	// This build takes the default parameters (LINEAR_MAP = 0,
	// RT_PRIORITY = 0), so the controller is bit-identical to the vendored
	// one for ports 0-2 and this instance issues no bursts at all.
	//
	// These are tied EXPLICITLY rather than left unconnected on purpose. An
	// unconnected input is undriven, so len2 would be X and `len2 > 1`
	// would be X -- which `if` treats as false, so it would appear to work
	// while making the burst decision on an undefined value. req3 left
	// floating is worse: `ack3 != req3` is then X forever and the port
	// neither runs nor cleanly idles.
	.len2  (4'd1),                       // 1 = legacy single access
	.addr3 (24'd0), .len3 (4'd1),
	.req3  (1'b0),  .ack3 (),            // idle: req3 == ack3's power-up 0
	.burst_dout (), .burst_dout_valid ()
);

endmodule
