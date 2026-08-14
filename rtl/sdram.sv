//
// sdram.sv
//
// sdram controller implementation
// Copyright (c) 2018 Sorgelig
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
// ----------------------------------------------------------------------
// Originally pulled in verbatim from MiSTer-devel/Arcade-Jackal_MiSTer
// (rtl/ram_rom/sdram.sv), the canonical Sorgelig 3-port SDRAM controller
// used across most MiSTer arcade cores, targeting a single MT48LC16M16
// (or compatible) SDRAM chip on the DE10-Nano/MiSTer main board.
//
// Three independent request/ack ports (0/1/2), each byte-maskable
// (wrl/wrh) and word-addressed (addr[24:1], i.e. a 24-bit word address ->
// 32MB of byte-addressable space).
//
// ======================================================================
// BURST EXTENSION (Volfied) -- what changed and why
// ======================================================================
//
// Volfied's playfield is a 512KB bitmap that cannot fit in block RAM, so it
// lives in SDRAM and has to be scanned out in real time: 320 words per line
// x 240 lines x 60Hz = 4.61M reads/s. The stock controller retires ONE
// access every 7 clocks, so at the 48MHz clk_sys this core runs SDRAM at
// that is 6.86M accesses/s TOTAL. Scanout alone would take 67% of the whole
// memory system, on top of 68000 program fetches, 68000 bitmap read/write
// and PC090OJ sprite fetches. It does not fit. Hence bursts.
//
// THE BLOCKER NOBODY WROTE DOWN. Setting BURST_LENGTH in the mode register
// is NOT sufficient and on its own is actively wrong here, because of how
// the vendored controller wires the address:
//
//     STATE_START: SDRAM_A <= a[13:1];                 // ROW  = LOW  bits
//     STATE_CONT:  SDRAM_A <= {dqm, 2'b10, a[22:14]};  // COL  = HIGH bits
//
// The row comes from the LOW 13 bits of the word address and the column
// from the HIGH 9. A burst -- of any kind, mode-register or page-mode --
// increments the COLUMN, so consecutive burst beats would return words
// 8192 apart. Word 0 and word 1 are not even in the same row, they are in
// the same column of two different rows. Any burst work that does not fix
// this first produces a controller that bursts perfectly and returns
// garbage.
//
// So LINEAR_MAP was added:
//
//     LINEAR_MAP = 0   row = a[13:1],  col = a[22:14]   legacy, bit-identical
//     LINEAR_MAP = 1   row = a[22:10], col = a[9:1]     512 consecutive words
//                                                       share one row
//
// The mapping is purely internal -- it is the only place a word address is
// translated to (bank,row,col), and it is used for both writes and reads --
// so it is a bijection change that no client can observe, EXCEPT that
// sim/tb_rom_path.sv's chip_key() models it and must agree. Rainbow Islands
// builds keep LINEAR_MAP = 0 and are unaffected down to the pin.
//
// THE SECOND TRAP: BURST TERMINATE. The obvious design -- mode register
// BURST_LENGTH = 8, then CMD_BURST_TERMINATE to cut short the single-word
// accesses ports 0-2 make -- is ILLEGAL on this part. JEDEC and the Micron
// datasheet both state BURST TERMINATE may not be applied to a burst with
// auto-precharge, and every access this controller issues sets A10 = 1.
// The fix would be to drop auto-precharge and precharge explicitly, which
// costs states on the single-access path that ports 0-2 use for everything.
//
// This implementation instead leaves the mode register at BURST_LENGTH = 1
// and does PAGE-MODE reads: one ACTIVE followed by N back-to-back READ
// commands walking the column, A10 = 0 on all but the last and A10 = 1 on
// the last so the bank auto-precharges when the burst finishes. That is
// legal, needs no BURST TERMINATE anywhere, and leaves ports 0 and 1
// executing the exact command sequence they execute today.
//
//   8-word page-mode burst: ~16 clocks -> 2.0 clocks/word
//   8 single accesses:       56 clocks -> 7.0 clocks/word
//
// Scanout therefore drops from 67% of the memory system to ~19%.
//
// PORT SUMMARY after this change:
//   port 0   single access, r/w   68000 program ROM + bitmap r/w  (unchanged)
//   port 1   single access, r/w   PC080SN tile ROM               (unchanged)
//   port 2   single access OR burst read, len2 = 1 is bit-identical to before
//   port 3   burst read only      NEW -- Volfied bitmap scanout
//
// Burst data does NOT come out on dout0/1/2. It streams on burst_dout with
// burst_dout_valid, one word per beat, in address order. Only one burst can
// be in flight at a time, so the two burst-capable ports share that bus and
// each knows the data is its own because it is waiting on its own ack.
//
// REFRESH IS UNCHANGED AND STILL WINS. The refresh request is still tested
// first in the IDLE chain, so a pending refresh preempts a new burst; only
// an already-running burst delays it, by at most ~16 clocks. Note for the
// record (NOT changed here, and pre-existing): rfs_cnt's 850-clock period is
// 17.7us at 48MHz against the 7.8us this part wants, mitigated by the
// rfs2 half-count path that forces a refresh roughly every 425 clocks
// (8.85us). That is still ~13% over spec and it predates this work -- it is
// flagged, not fixed, because changing refresh cadence on a shipping
// baseline is its own change with its own test.
// ----------------------------------------------------------------------

module sdram
#(
	// See the BURST EXTENSION block above. 0 = legacy Sorgelig row/column
	// split, bit-identical to the vendored controller. 1 = burst-friendly
	// linear mapping, REQUIRED for any port that issues len > 1.
	parameter bit LINEAR_MAP  = 1'b0,

	// IDLE arbitration order after refresh.
	//   0  port 3 (burst), then 0, 1, 2      -- legacy order for 0/1/2
	//   1  port 3 (burst), then 2, 1, 0      -- real-time first:
	//                                           scanout > sprites > CPU
	// Volfied needs 1: scanout and sprite fetch both have a hard scanline
	// deadline and the 68000 does not -- it just waits on DTACK.
	parameter bit RT_PRIORITY = 1'b0,

	// Bounded-latency guard for port 0 under RT_PRIORITY. Strict priority gives
	// the real-time ports what they need but leaves port 0 with UNBOUNDED wait:
	// volfied_bitmap.sv issues 41 back-to-back bursts of 8 at line start, and
	// sim/tb_volfied_boot.sv measured AS_n low for 669 clocks against a 656-clock
	// prefetch window -- i.e. a 68000 access that arrives during a prefetch waits
	// out the WHOLE prefetch. The 68000 ran at ~1/3 speed as a result (226 clocks
	// per MOVE.W (A0)+,(A1)+ iteration against its native 72 at 8 MHz).
	//
	// After this many consecutive grants to other ports while port 0 is waiting,
	// port 0 is promoted ahead of everything except refresh, for one access.
	//
	// This is a LATENCY fix, not a bandwidth one: the real-time ports use well
	// under half of each 3051-clock line, so there was always room for the CPU --
	// strict priority simply never handed it over. At the default of 2 the CPU
	// gets one single access per two bursts, costing scanout ~8 clocks per pair
	// and pushing a line's prefetch from ~656 to ~820 clocks. Still ample.
	//
	// Only has effect when RT_PRIORITY = 1. Rainbow Islands builds with
	// RT_PRIORITY = 0, where every reference below folds away at elaboration and
	// the netlist is unchanged.
	parameter [2:0] STARVE_LIMIT = 3'd2
)
(

	// interface to the MT48LC16M16 chip
	inout  reg [15:0] SDRAM_DQ,   // 16 bit bidirectional data bus
	output reg [12:0] SDRAM_A,    // 13 bit multiplexed address bus
	output reg        SDRAM_DQML, // byte mask
	output reg        SDRAM_DQMH, // byte mask
	output reg  [1:0] SDRAM_BA,   // two banks
	output            SDRAM_nCS,  // a single chip select
	output reg        SDRAM_nWE,  // write enable
	output reg        SDRAM_nRAS, // row address select
	output reg        SDRAM_nCAS, // columns address select
	output            SDRAM_CLK,
	output            SDRAM_CKE,

	// cpu/chipset interface
	input             init,			// init signal after FPGA config to initialize RAM
	input             clk,			// sdram is accessed at up to 128MHz

	input      [24:1] addr0,
	input             wrl0,
	input             wrh0,
	input      [15:0] din0,
	output     [15:0] dout0,
	input             req0,
	// EXPLICIT POWER-UP VALUE on all four acks. The vendored controller left
	// these uninitialised, which is invisible on hardware (Cyclone V
	// registers power up to 0, and the req/ack toggle protocol only cares
	// that the two start EQUAL) but is not invisible in simulation: a 4-state
	// simulator starts them at X, `ack != req` evaluates to X, `if (X)` is
	// false, and the controller never accepts the first request from that
	// port. A bench then hangs or -- worse -- a `wait (ack == req)` falls
	// straight through and the test measures nothing while reporting a pass.
	// Costs nothing, and makes the simulation agree with the hardware.
	output reg        ack0 = 1'b0,

	input      [24:1] addr1,
	input             wrl1,
	input             wrh1,
	input      [15:0] din1,
	output     [15:0] dout1,
	input             req1,
	output reg        ack1 = 1'b0,

	input      [24:1] addr2,
	input             wrl2,
	input             wrh2,
	input      [15:0] din2,
	output     [15:0] dout2,
	input             req2,
	output reg        ack2 = 1'b0,
	// Words to read in this access, 1..8. Tie to 4'd1 for the legacy
	// single-access behaviour, which is then bit-identical to the vendored
	// controller. Ignored when the access is a write.
	input       [3:0] len2,

	// ---- port 3: burst read only (Volfied bitmap scanout) ----------------
	// addr3 must be aligned to len3 so the column walk cannot leave the row
	// (512 columns / 8 = 64 exactly, so an 8-aligned start is always safe).
	input      [24:1] addr3,
	input       [3:0] len3,       // 1..8
	input             req3,
	output reg        ack3 = 1'b0,

	// ---- streaming burst data (ports 2 and 3) -----------------------------
	// One word per beat, in ascending address order, starting the cycle
	// burst_dout_valid first rises. ack for the port is toggled on the beat
	// that carries the LAST word, so a client may use either the last valid
	// or the ack edge as its completion signal.
	output reg [15:0] burst_dout,
	output reg        burst_dout_valid
);

assign SDRAM_nCS = 0;
assign SDRAM_CKE = 1;
assign {SDRAM_DQMH,SDRAM_DQML} = SDRAM_A[12:11];

localparam RASCAS_DELAY   = 3'd2; // tRCD=20ns -> 2 cycles@85MHz
localparam BURST_LENGTH   = 3'd0; // 0=1, 1=2, 2=4, 3=8, 7=full page
                                  // DELIBERATELY LEFT AT 1. Bursts here are
                                  // page-mode (N back-to-back READ commands),
                                  // not mode-register bursts -- see the header
                                  // for why the mode-register route needs an
                                  // illegal BURST TERMINATE.
localparam ACCESS_TYPE    = 1'd0; // 0=sequential, 1=interleaved
localparam CAS_LATENCY    = 3'd2; // 2/3 allowed
localparam OP_MODE        = 2'd0; // only 0 (standard operation) allowed
localparam NO_WRITE_BURST = 1'd1; // 0=write burst enabled, 1=only single access write

localparam MODE = { 3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH};

// State counter widened from 3 to 4 bits: a full 8-word page-mode burst
// runs to state 15 (see BURST_TAIL below). States 0..6 are unchanged, so a
// single access still occupies exactly the same states it always did.
localparam STATE_IDLE  = 4'd0;             // state to check the requests
localparam STATE_START = STATE_IDLE+1'd1;  // state in which a new command is started
localparam STATE_CONT  = STATE_START+RASCAS_DELAY;
localparam STATE_READY = STATE_CONT+CAS_LATENCY+1'd1;
localparam STATE_LAST  = STATE_READY;      // last state of a SINGLE access

// Extra states after the final beat of a burst, covering tRP for the
// auto-precharge the last READ triggered. tRP is 20ns = 1 clock at 48MHz;
// 2 is carried for margin and costs nothing measurable (2 clocks on a
// ~16-clock burst that moves 8 words).
localparam BURST_TAIL  = 4'd2;

reg  [3:0] state;
reg [22:1] a;
reg [15:0] data;
reg        we;
reg  [1:0] ba = 0;
reg  [1:0] dqm;
reg        active = 0;
reg  [3:0] ram_req = 0;
wire [2:0] wr = {wrl2|wrh2,wrl1|wrh1,wrl0|wrh0};

reg [15:0] dout;


assign dout0 = dout;
assign dout1 = dout;
assign dout2 = dout;


// LOCAL DEVIATION FROM UPSTREAM (MiSTer-devel/Arcade-Jackal_MiSTer). Upstream
// declares these AFTER the access manager below, which reads all three. Quartus
// tolerates that by creating implicit nets and merging them with the real
// declarations, but ModelSim rejects the file outright, so it cannot be
// compiled into a testbench as-is. `mode` is [1:0] and `reset` is [4:0], so an
// implicit 1-bit net is not merely cosmetic -- a tool resolving the merge the
// other way would truncate both. Only the declarations moved; no logic changed.
// Keep this move when syncing from upstream.
localparam MODE_NORMAL = 2'b00;
localparam MODE_RESET  = 2'b01;
localparam MODE_LDM    = 2'b10;
localparam MODE_PRE    = 2'b11;

reg [1:0] mode;
reg [4:0] reset=5'h1f;

// ---- burst bookkeeping -------------------------------------------------
// burst_n   : total words this access will read (1 = plain single access,
//             which takes the ordinary 0..6 path and never sets bursting)
// bursting  : this access is a multi-word page-mode read
// burst_col : column presented on the NEXT READ command
// beats     : words still to be delivered on burst_dout
reg  [3:0] burst_n;
reg        bursting;
reg  [8:0] burst_col;
reg  [3:0] beats;

// ---- port 0 starvation guard (see STARVE_LIMIT) ------------------------
// starve_cnt counts consecutive grants to OTHER ports taken while port 0 had
// a request outstanding. It saturates rather than wraps: wrapping would drop
// it back under the limit and hand the CPU straight back into starvation,
// which is the exact failure this exists to stop.
reg  [2:0] starve_cnt;
wire       port0_pending = (ack0 != req0);
wire       port0_urgent  = RT_PRIORITY && port0_pending &&
                           (starve_cnt >= STARVE_LIMIT);

// Last state of the current access. A single access ends at STATE_LAST
// exactly as before; a burst of N ends N-1 beats later plus the tRP tail.
wire [3:0] state_last = bursting ? (STATE_READY + burst_n - 4'd1 + BURST_TAIL)
                                 : STATE_LAST;

// The READ command is repeated on states STATE_CONT .. STATE_CONT+burst_n-1.
wire       issue_read  = active && !we && (state >= STATE_CONT) &&
                         (state < (STATE_CONT + burst_n));
// ...and it is the final one (the one that carries auto-precharge) here.
wire       last_read   = active && !we && (state == (STATE_CONT + burst_n - 4'd1));
// Data for the READ issued at state k lands at state k+3, matching the
// single-access controller's STATE_READY = STATE_CONT+CAS_LATENCY+1.
wire       capture_win = bursting && (state >= STATE_READY) &&
                         (state < (STATE_READY + burst_n));

// Row and column extraction. See the LINEAR_MAP note in the header -- this
// is the ONLY place a word address becomes (row, column), which is why
// changing it is invisible to every client.
wire [12:0] row_addr = LINEAR_MAP ? a[22:10] : a[13:1];
wire  [8:0] col_addr = LINEAR_MAP ? a[9:1]   : a[22:14];

// access manager
always @(posedge clk) begin
	reg [9:0] rfs_cnt;
	reg rfs, rfs2;

	rfs_cnt <= rfs_cnt + 1'd1;
	if (rfs_cnt == 850) begin
		rfs <= 1;
		rfs_cnt <= 0;
	end

	if (rfs_cnt == 425) rfs2 <= 1;

	if(state == STATE_IDLE && mode == MODE_NORMAL) begin
		if (rfs) begin
			rfs <= 0;
			rfs2 <= 0;
			rfs_cnt <= 0;
			we <= 0;
			dqm <= 2'b00;
			active <= 0;
			bursting <= 0;
			burst_n <= 4'd1;
			state <= STATE_START;
		end
		// PORT 0 promoted, but ONLY after it has been passed over
		// STARVE_LIMIT times in a row. Refresh still outranks it -- a missed
		// refresh loses the whole array, which no latency argument beats.
		// One single access, then the counter clears and normal priority
		// resumes, so the real-time ports never lose two slots running.
		//
		// Safe to interleave: grants happen only at STATE_IDLE, so a burst has
		// always fully retired by the time we get here. Slipping a CPU access
		// between two bursts just delays the next one, and volfied_bitmap.sv
		// already waits on sc_ack before issuing it.
		else if (port0_urgent) begin
			{ba,a} <= addr0;
			data <= din0;
			we <= wr[0];
			dqm <= wr[0] ? ~{wrh0,wrl0} : 2'b00;
			ram_req[0] <= 1;
			burst_n <= 4'd1;
			bursting <= 0;
			starve_cnt <= 3'd0;
			active <= 1;
			rfs <= rfs2;
			state <= STATE_START;
		end
		// PORT 3 (burst read) leads the normal chain in both priority modes:
		// it is the only client with a hard real-time deadline it cannot
		// recover from -- a late scanline is a visibly torn line, whereas a
		// late 68000 just spends longer in DTACK. (That argument holds per
		// access but not without limit, which is what the guard above caps.)
		else if (ack3 != req3) begin
			if (RT_PRIORITY && port0_pending && starve_cnt != 3'd7)
				starve_cnt <= starve_cnt + 3'd1;
			{ba,a} <= addr3;
			we <= 0;
			dqm <= 2'b00;
			active <= 1;
			ram_req[3] <= 1;
			burst_n <= (len3 == 4'd0) ? 4'd1 : len3;
			// Port 3 ALWAYS takes the burst path, even at len3 = 1, so its
			// data always arrives on burst_dout and never on the shared
			// dout. A one-word "burst" costs 2 extra clocks for the tRP
			// tail; port 3 is scanout, which always asks for 8, so that
			// case exists only to keep the interface from having two modes.
			bursting <= 1'b1;
			burst_col <= LINEAR_MAP ? addr3[9:1] : addr3[22:14];
			beats <= (len3 == 4'd0) ? 4'd1 : len3;
			rfs <= rfs2;
			state <= STATE_START;
		end
		else if (RT_PRIORITY ? (ack2 != req2) : (ack0 != req0)) begin
			if (RT_PRIORITY) begin
				{ba,a} <= addr2;
				data <= din2;
				we <= wr[2];
				dqm <= wr[2] ? ~{wrh2,wrl2} : 2'b00;
				ram_req[2] <= 1;
				burst_n <= (wr[2] || len2 == 4'd0) ? 4'd1 : len2;
				bursting <= !wr[2] && (len2 > 4'd1);
				burst_col <= LINEAR_MAP ? addr2[9:1] : addr2[22:14];
				beats <= (wr[2] || len2 == 4'd0) ? 4'd1 : len2;
				if (port0_pending && starve_cnt != 3'd7)
					starve_cnt <= starve_cnt + 3'd1;
			end else begin
				{ba,a} <= addr0;
				data <= din0;
				we <= wr[0];
				dqm <= wr[0] ? ~{wrh0,wrl0} : 2'b00;
				ram_req[0] <= 1;
				burst_n <= 4'd1;
				bursting <= 0;
			end
			active <= 1;
			rfs <= rfs2;
			state <= STATE_START;
		end
		else if (ack1 != req1) begin
			if (RT_PRIORITY && port0_pending && starve_cnt != 3'd7)
				starve_cnt <= starve_cnt + 3'd1;
			{ba,a} <= addr1;
			data <= din1;
			we <= wr[1];
			dqm <= wr[1] ? ~{wrh1,wrl1} : 2'b00;
			active <= 1;
			ram_req[1] <= 1;
			burst_n <= 4'd1;
			bursting <= 0;
			rfs <= rfs2;
			state <= STATE_START;
		end
		else if (RT_PRIORITY ? (ack0 != req0) : (ack2 != req2)) begin
			if (RT_PRIORITY) begin
				{ba,a} <= addr0;
				data <= din0;
				we <= wr[0];
				dqm <= wr[0] ? ~{wrh0,wrl0} : 2'b00;
				ram_req[0] <= 1;
				burst_n <= 4'd1;
				bursting <= 0;
				// Served by normal priority, so the guard was not needed --
				// clear it either way, or the count would carry across into
				// the next contention and fire early.
				starve_cnt <= 3'd0;
			end else begin
				{ba,a} <= addr2;
				data <= din2;
				we <= wr[2];
				dqm <= wr[2] ? ~{wrh2,wrl2} : 2'b00;
				ram_req[2] <= 1;
				burst_n <= (wr[2] || len2 == 4'd0) ? 4'd1 : len2;
				bursting <= !wr[2] && (len2 > 4'd1);
				burst_col <= LINEAR_MAP ? addr2[9:1] : addr2[22:14];
				beats <= (wr[2] || len2 == 4'd0) ? 4'd1 : len2;
			end
			active <= 1;
			rfs <= rfs2;
			state <= STATE_START;
		end
	end

	// Walk the column for the NEXT read command in the burst. Aligned starts
	// mean this can never carry out of the 9-bit column into a different row
	// (see the addr3 port comment).
	if (issue_read) burst_col <= burst_col + 9'd1;

	// ---- burst data streaming -------------------------------------------
	// One beat per capture state. ack is toggled on the LAST beat, so a
	// client that only watches ack still sees completion exactly once, and a
	// client that consumes burst_dout gets every word.
	burst_dout_valid <= 1'b0;
	if (capture_win) begin
		burst_dout       <= SDRAM_DQ;
		burst_dout_valid <= 1'b1;
		beats            <= beats - 4'd1;
		if (beats == 4'd1) begin
			if (ram_req[3]) ack3 <= req3;
			else if (ram_req[2]) ack2 <= req2;
		end
	end

	// Single-access completion. Unchanged from the vendored controller
	// except for being held off while a burst is running -- a burst reports
	// through the beat counter above instead.
	if(state == STATE_READY && ram_req && !bursting) begin
		dout <= SDRAM_DQ;
		active <= 0;
		ram_req <= 0;
		if (ram_req[0]) ack0 <= req0;
		else if (ram_req[1]) ack1 <= req1;
		else if (ram_req[2]) ack2 <= req2;
		else if (ram_req[3]) ack3 <= req3;
	end

	// A burst releases the bus only after its tRP tail.
	if (bursting && state == state_last) begin
		active   <= 0;
		ram_req  <= 0;
		bursting <= 0;
	end

	if(mode != MODE_NORMAL || state != STATE_IDLE || reset) begin
		state <= state + 1'd1;
		if(state == state_last) state <= STATE_IDLE;
	end
end


// initialization
// (MODE_* / mode / reset are declared above the access manager -- see the
// local-deviation note there.)
always @(posedge clk) begin
	reg init_old=0;
	init_old <= init;

	if(init_old & ~init) reset <= 5'h1f;
	else if(state == STATE_LAST) begin
		if(reset != 0) begin
			reset <= reset - 5'd1;
			if(reset == 14)     mode <= MODE_PRE;
			else if(reset == 3) mode <= MODE_LDM;
			else                mode <= MODE_RESET;
		end
		else mode <= MODE_NORMAL;
	end
end

localparam CMD_NOP             = 3'b111;
localparam CMD_ACTIVE          = 3'b011;
localparam CMD_READ            = 3'b101;
localparam CMD_WRITE           = 3'b100;
localparam CMD_BURST_TERMINATE = 3'b110;   // never issued -- see header
localparam CMD_PRECHARGE       = 3'b010;
localparam CMD_AUTO_REFRESH    = 3'b001;
localparam CMD_LOAD_MODE       = 3'b000;

// SDRAM state machines
always @(posedge clk) begin
	if(state == STATE_START) SDRAM_BA <= (mode == MODE_NORMAL) ? ba : 2'b00;

	SDRAM_DQ <= 'Z;

	// Command. The single-access cases are exactly the vendored ones; the
	// read case is now driven by issue_read so it repeats for a burst
	// instead of firing once at STATE_CONT.
	if (mode == MODE_NORMAL) begin
		if (state == STATE_START)
			{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= active ? CMD_ACTIVE : CMD_AUTO_REFRESH;
		else if (active && we && state == STATE_CONT)
			{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE, SDRAM_DQ} <= {CMD_WRITE, data};
		else if (issue_read)
			{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_READ;
		else
			{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_NOP;
	end
	else if (mode == MODE_LDM && state == STATE_START)
		{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_LOAD_MODE;
	else if (mode == MODE_PRE && state == STATE_START)
		{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_PRECHARGE;
	else
		{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_NOP;

	// Address.
	//   STATE_START            row
	//   read/write command     {DQM, A10 = auto-precharge, A9 = 0, column}
	//
	// A10 CARRIES AUTO-PRECHARGE and that is the whole reason a burst can be
	// done at all without BURST TERMINATE: it is 0 for every READ but the
	// last, keeping the row open for the next column, and 1 on the last so
	// the bank closes itself. A single access sets it on its only READ and
	// so behaves exactly as before.
	if(mode == MODE_NORMAL) begin
		if (state == STATE_START)
			SDRAM_A <= row_addr;
		else if (active && we && state == STATE_CONT)
			SDRAM_A <= {dqm, 2'b10, col_addr};
		else if (issue_read)
			SDRAM_A <= {dqm, last_read, 1'b0, bursting ? burst_col : col_addr};
	end
	else if(mode == MODE_LDM && state == STATE_START) SDRAM_A <= MODE;
	else if(mode == MODE_PRE && state == STATE_START) SDRAM_A <= 13'b0010000000000;
	else SDRAM_A <= 0;
end

// synthesis translate_off
// A burst whose column walk leaves the row returns data from the START of
// the same row instead of the next row -- silently, and only for the beats
// past the boundary. Clients are required to align; this catches one that
// does not, in simulation, where it is cheap to find.
always @(posedge clk) begin
	if (mode == MODE_NORMAL && state == STATE_START && bursting) begin
		if (!LINEAR_MAP)
			$fatal(1, "sdram: burst requested with LINEAR_MAP=0 -- consecutive words are in different rows");
		// Widened deliberately: a 9-bit add would WRAP instead of exceeding
		// 0x1FF, so the check would pass on exactly the case it exists to
		// catch.
		if (({1'b0, a[9:1]} + {6'd0, burst_n} - 10'd1) > 10'h1FF)
			$fatal(1, "sdram: burst at col %0d len %0d crosses the row boundary", a[9:1], burst_n);
	end
end
// synthesis translate_on

altddio_out
#(
	.extend_oe_disable("OFF"),
	.intended_device_family("Cyclone V"),
	.invert_output("OFF"),
	.lpm_hint("UNUSED"),
	.lpm_type("altddio_out"),
	.oe_reg("UNREGISTERED"),
	.power_up_high("OFF"),
	.width(1)
)
sdramclk_ddr
(
	.datain_h(1'b0),
	.datain_l(1'b1),
	.outclock(clk),
	.dataout(SDRAM_CLK),
	.aclr(1'b0),
	.aset(1'b0),
	.oe(1'b1),
	.outclocken(1'b1),
	.sclr(1'b0),
	.sset(1'b0)
);

endmodule
