/*  Core uPD78C11 (familia NEC uPD7810) — LLE del C-Chip de Taito (TC0030CMD).
    Parte de JTCORES. GPLv3.

    ============================================================================================
    POR QUE EXISTE
    ============================================================================================
    jtframe NO tiene ningun core de la familia 78xx, y sin el, el set ORIGINAL de Operation Wolf
    es INJUGABLE: el C-Chip es DUENO DE LOS INPUTS (monedas por PB, gatillo/start por PC).
    Con este core se corren las ROM REALES -> correcto POR CONSTRUCCION, sin adivinar nada.
    Ver research/CCHIP-LLE-PLAN.md.

    ============================================================================================
    LO QUE HAY QUE ENTENDER ANTES DE TOCAR ESTO
    ============================================================================================
    1) ⭐⭐ EL FLAG 'SK' (SKIP) ES EL CORAZON DE LA ISA, no un detalle.
       El uPD7810 casi NO tiene saltos condicionales. Las comparaciones (EQI, NEI, GTI, LTI, ONA,
       BIT, SKN...) NO saltan: ACTIVAN EL FLAG SK, y entonces LA INSTRUCCION SIGUIENTE NO SE
       EJECUTA -- solo se avanza el PC su longitud. Por eso EQI/NEI son de las mas usadas.
       -> Para saltarla basta con saber su LONGITUD: de ahi la tabla upd7810_len.vh.

    2) DECODIFICADOR DE DOS NIVELES: 7 PREFIJOS (48 4C 4D 60 64 70 74). El primer byte solo
       elige la tabla; la instruccion real es el SEGUNDO byte. Se usan desde la 2a instruccion
       del arranque, asi que no son un caso raro.

    3) Las tablas de LONGITUD y DECODIFICACION estan GENERADAS desde las fuentes de MAME
       (tools/upd7810_gen.py). Son ~2000 numeros cada una: a mano serian erratas seguras.
       *** NO SE EDITAN A MANO. ***

    4) Core FUNCIONAL, NO cycle-exact: el C-Chip es un coprocesador que habla con el 68000 por
       RAM COMPARTIDA CON HANDSHAKE y no esta en el camino critico del video. Basta con que sea
       correcto y lo bastante rapido. Timers/serie/AD no se implementan (opwolf no depende de
       ellos); los registros especiales que solo se configuran se guardan sin efecto.

    5) ⭐ VALIDACION: NO se mira "si el juego arranca". El testbench vuelca el PC de CADA
       instruccion y se DIFFEA contra la traza real del depurador de MAME (1.218.766
       instrucciones). EL PRIMER PUNTO DE DIVERGENCIA ES, LITERALMENTE, EL BUG.
*/

module upd7810(
    input             rst,
    input             clk,
    input             cen,

    // bus de memoria: sincrono, 1 ciclo de latencia en lectura (como una BRAM)
    output reg [15:0] addr,
    output reg [ 7:0] dout,
    output reg        we,
    input      [ 7:0] din,

    // puertos
    input      [ 7:0] pa_in,
    input      [ 7:0] pb_in,
    input      [ 7:0] pc_in,
    output reg [ 7:0] pa_out,
    output reg [ 7:0] pb_out,
    output reg [ 7:0] pc_out,

    input             intf1,        // IRQ externa (vblank del 68000) -> vector 0x0010

    // traza (simulacion): un pulso por instruccion, con su PC
    output reg        trace_stb,
    output reg [15:0] trace_pc,
    output reg        undef         // opcode NO implementado: para el sim y dilo
);

`include "upd7810_len.vh"
`include "upd7810_cyc.vh"

// bits del PSW
localparam CY=0, F1=1, L0=2, L1=3, HC=4, SK=5, ZF=6, F7=7;

// registros
reg [ 7:0] v, a, b, c, d, e, h, l, psw;
reg [15:0] ea, sp, pc;
reg [ 7:0] v2,a2,b2,c2,d2,e2,h2,l2;   // banco alternativo (EXX)
reg [15:0] ea2;
reg        ien;      // interrupciones habilitadas (EI/DI). OJO: no llamarlo 'iff': es palabra reservada en SV
reg [ 7:0] mkl, mkh, anm, eom;   // registros especiales (solo los que usa el C-Chip)
reg [ 7:0] ma, mb, mc;           // MODO/DIRECCION de puerto (1=entrada, 0=salida). MAME: al leer un
                                 // puerto, los bits de SALIDA devuelven el LATCH, no el pin:
                                 //   RP(PB)= (pb_in & mb) | (pb_out & ~mb)   (idem PA/PC)
                                 // PB esta MEZCLADO (moneda=entrada, contadores 4/5=salida). Ignorar
                                 // esto devolvia el pin en los bits de salida -> COIN ERROR. El bug es
                                 // INVISIBLE a la traza de PCs (solo cambia el DATO leido), por eso
                                 // paso las 152k del attract. Ver upd7810.cpp RP()/device_reset.
reg        irq_pend;

// FSM
localparam [4:0] FETCH=0, FETCH_W=1, PFX_W=2, OPR=3, OPR_W=4, EXEC=5,
                 LD_W=6, PUSH1=7, PUSH2=8, POP1=9, POP2=10, JUMP=11, SKIPI=12,
                 LD16A=13, LD16B=14, ST16A=15, MEMOP=16, CALTRD=17, MEMOPA=18,
                 MEMOPW=19, MEMOPI=20, BLK=21, POPSW=22;
reg [ 4:0] st;
reg [ 7:0] op, op2;
reg [ 2:0] oplen, nfetch;
reg [ 7:0] o0, o1;             // bytes de operando, en orden
reg [15:0] tmp;
reg [ 1:0] immn;               // operandos ya leidos (0,1,2)
reg [ 2:0] rdst;               // registro destino para las cargas
reg [ 7:0] pushv_h, pushv_l;
reg [ 1:0] retsel;             // 0=nada 1=RET 2=RETI
reg [ 2:0] m16;                // par destino de las cargas/almacenamientos de 16 bits (5=PC, para CALT)
reg [15:0] calt;               // direccion en la tabla de vectores de CALT
reg [ 2:0] bitn;               // bit a testear en BIT n,wa
reg [ 1:0] memop;              // 1=BIT 2=EQIW 3=ANIW
reg [ 3:0] ax_op;              // operacion de la ALU contra memoria (EQAX/NEAX/ADDX/SUBX)

// ⭐⭐ CYCLE-TIMING (GAPS §G-32) — sin esto la CPU va ~13x DEMASIADO RAPIDA y rompe el rebote de
//   entradas del firmware ("coge varias pulsaciones", coin/IO error). El uPD7810 gasta 'cycles'
//   ciclos-maquina por instruccion (tabla de MAME), y CADA ciclo-maquina son 3 periodos de reloj
//   (upd7810.h: execute_cycles_to_clocks = cycles*3). El reloj del C-Chip es 12 MHz = 'cen', asi
//   que cada instruccion debe durar 'cycles*3' pulsos de cen. 'used' = pulsos ya consumidos por la
//   instruccion en curso; 'want' = su objetivo. En FETCH se RELLENA con pulsos muertos hasta 'want'
//   antes de arrancar la siguiente. La secuencia de PCs NO cambia -> el diff de traza sigue OK.
reg [ 7:0] used, want;
`ifdef SIMULATION
integer dbg_sumu=0, dbg_sumw=0, dbg_cnt=0;   // DEBUG cycle-timing: real vs objetivo
`endif

wire [15:0] hl16 = {h,l};
wire [15:0] w16  = {o1,o0};                 // inmediato de 16 bits (little endian)
// ⚠ "working area": la pagina la da el REGISTRO V, no es 0xFF fijo.
//   (MAME: 'PAIR ea = m_va' -> ea = {V, offset}.) Funcionaba de casualidad porque el arranque
//   hace MVI V,$FF; con otro V habria escrito en la pagina equivocada.
wire [15:0] wa   = {v, o0};

function is_prefix; input [7:0] o;
    is_prefix = o==8'h48||o==8'h4c||o==8'h4d||o==8'h60||o==8'h64||o==8'h70||o==8'h74;
endfunction

function [2:0] len_of; input [7:0] p; input [7:0] s;
    case( p )
        8'h48: len_of = oplen_48(s);  8'h4c: len_of = oplen_4c(s);
        8'h4d: len_of = oplen_4d(s);  8'h60: len_of = oplen_60(s);
        8'h64: len_of = oplen_64(s);  8'h70: len_of = oplen_70(s);
        8'h74: len_of = oplen_74(s);  default: len_of = oplen_xx(p);
    endcase
endfunction

// Los ciclos de una instruccion con PREFIJO se leen de la funcion HOJA de su sub-tabla
// (cyc_48/cyc_64/...) DIRECTAMENTE en PFX_W. Un wrapper 'cyc_of' que llamase a esas funciones
// devolvia 0 dentro de una asignacion no-bloqueante en Verilator, asi que no se usa.

function [7:0] rd_r; input [2:0] i;
    case(i) 3'd0:rd_r=v; 3'd1:rd_r=a; 3'd2:rd_r=b; 3'd3:rd_r=c;
            3'd4:rd_r=d; 3'd5:rd_r=e; 3'd6:rd_r=h; default:rd_r=l; endcase
endfunction

// escritura de registro por indice
task wr_r; input [2:0] i; input [7:0] x;
    case(i) 3'd0:v<=x; 3'd1:a<=x; 3'd2:b<=x; 3'd3:c<=x;
            3'd4:d<=x; 3'd5:e<=x; 3'd6:h<=x; default:l<=x; endcase
endtask

// flags de suma/resta de 8 bits
task setf; input [8:0] r;
    begin psw[ZF] <= r[7:0]==8'd0; psw[CY] <= r[8]; end
endtask
task setz; input [7:0] r;
    begin psw[ZF] <= r==8'd0; end
endtask

// ============================================================================================
// ⭐ ALU GENERICA — las tablas 0x60 (r,r') y 0x74 (r,imm) son LA MISMA ALU:
//      op2[6:3] = OPERACION   op2[2:0] = REGISTRO   op2[7] = SENTIDO (1: A op= r | 0: r op= A)
//   Codigos (derivados de la tabla de MAME, no supuestos):
//      1=AN  2=XR  3=OR  5=GT  7=LT  8=ADD  9=ON  10=ADC  11=OFF  12=SUB  13=NE  14=SBB  15=EQ
//   Implementarla asi tumba DECENAS de instrucciones de golpe en vez de una a una.
//   ⚠ Las de comparacion (GT/LT/ON/OFF/NE/EQ) NO escriben resultado: solo activan SK y flags.
// ============================================================================================
`include "upd7810_alu.vh"

// Ajuste del DAA, traducido de MAME (upd7810_opcodes.cpp: DAA)
function [7:0] daa_adj; input [7:0] av; input hcf; input cyf;
    reg [3:0] lo, hi;
    begin
        lo = av[3:0]; hi = av[7:4];
        daa_adj = 8'h00;
        if( !hcf ) begin
            if( lo < 4'd10 ) begin
                if( !(hi < 4'd10 && !cyf) ) daa_adj = 8'h60;
            end else begin
                daa_adj = (hi < 4'd9 && !cyf) ? 8'h06 : 8'h66;
            end
        end else if( lo < 4'd3 ) begin
            daa_adj = (hi < 4'd10 && !cyf) ? 8'h06 : 8'h66;
        end
    end
endfunction

// Flags de una RESTA (ZHC_SUB de MAME): las comparaciones EQI/NEI/LTI las usan.
//   Z  = resultado cero            CY = PRESTAMO (before < imm)
//   HC = medio prestamo
// (ojo: 'before' es palabra reservada en SystemVerilog -> bef/im)
task sub_flags; input [7:0] bef; input [7:0] im;
    begin
        psw[ZF] <= (bef == im);
        psw[CY] <= (bef <  im);
        psw[HC] <= ((bef-im) & 8'h0f) > (bef & 8'h0f);
    end
endtask

// En SIMULACION, un opcode sin implementar NO puede fallar en silencio: lo dice y para.
// (Sin esto, el C-Chip se iria por las ramas y estarias depurando "el original no arranca".)
`ifdef SIMULATION
reg undef_l=0;
always @(posedge clk) begin
    undef_l <= undef;
    if( undef && !undef_l )
        $display("### uPD7810: OPCODE NO IMPLEMENTADO  op=%02X op2=%02X  PC=%04X", op, op2, trace_pc);
end
`endif

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        pc<=0; sp<=0; psw<=0; ien<=0; st<=FETCH; we<=0; trace_stb<=0; irq_pend<=0;
        addr<=0; dout<=0;   // ⚠ addr DEBE resetearse: si no, la 1a lectura es X y el decodificador se vuelve loco
        undef<=0; mkl<=8'hff; mkh<=8'hff; anm<=0; eom<=0; retsel<=0;
        ma<=8'hff; mb<=8'hff; mc<=8'hff;   // reset: todos los puertos a ENTRADA (MAME device_reset)
        used<=0; want<=0;    // cycle-timing: la 1a instruccion arranca sin espera (want=0)
        v<=0;a<=0;b<=0;c<=0;d<=0;e<=0;h<=0;l<=0; ea<=0;
        pa_out<=8'hff; pb_out<=8'hff; pc_out<=8'hff;
    end else begin
        if( intf1 ) irq_pend <= 1;
        if( cen ) begin
        trace_stb <= 0;
        we        <= 0;
        used      <= used + 8'd1;   // cuenta este pulso para la instruccion en curso (cycle-timing)
        case( st )
        // -------------------------------------------------- FETCH
        FETCH: begin
            // ⭐ CYCLE-TIMING: rellena con pulsos muertos hasta que la instruccion ANTERIOR haya
            //   consumido sus 'want' (=cycles*3) pulsos. Solo entonces se arranca la siguiente. La
            //   IRQ NO cuenta como instruccion (MAME no le cobra ciclos): no toca 'used'/'want'.
            if( used < want ) begin
                // esperando: no se hace nada (used sigue incrementandose arriba)
            end else if( irq_pend && ien && !mkl[3] ) begin  // INTF1 (MKL bit3 la enmascara)
                irq_pend <= 0; ien <= 0;
                // MAME: SP--; WM(SP,PSW); SP--; WM(SP,PCH); SP--; WM(SP,PCL);
                //       PSW &= ~(SK|L0|L1); PC = vector;
                addr     <= sp - 16'd1; dout <= psw; we <= 1;   // 1o el PSW
                sp       <= sp - 16'd1;
                psw[SK]  <= 0; psw[L0] <= 0; psw[L1] <= 0;
                pushv_h  <= pc[15:8]; pushv_l <= pc[7:0];
                tmp      <= 16'h0010;                   // vector de INTF1
                st       <= PUSH1;
                retsel   <= 0;
            end else begin
                trace_pc <= pc; trace_stb <= 1;         // una linea de traza por instruccion
                addr <= pc; pc <= pc + 16'd1; st <= FETCH_W;
`ifdef SIMULATION
                // 'used' aqui = cen que consumio la instruccion ANTERIOR; 'want' = su objetivo.
                dbg_sumu <= dbg_sumu + used;
                dbg_sumw <= dbg_sumw + want;
                dbg_cnt  <= dbg_cnt + 1;
                if( dbg_cnt==5000 ) begin
                    $display("CYCDBG: 5000 instr  real=%0d cen  want=%0d cen  (x100)",
                             dbg_sumu*100/5000, dbg_sumw*100/5000);
                    dbg_cnt<=0; dbg_sumu<=0; dbg_sumw<=0;
                end
`endif
                used <= 8'd1;                            // este pulso = ciclo 1 de la nueva instruccion
            end
        end
        FETCH_W: begin
            op <= din;
            if( is_prefix(din) ) begin
                addr <= pc; pc <= pc + 16'd1; st <= PFX_W;
                // 'want' se fija en PFX_W (el coste real esta en la sub-tabla del prefijo)
            end else begin
                op2 <= 0; oplen <= oplen_xx(din); nfetch <= 3'd1; immn <= 2'd0;
                if( psw[SK] && din!=8'h72 ) begin
                    st   <= SKIPI;
                    want <= 8'd3 * cycs_xx(din);        // instruccion SALTADA -> cycles_skip*3
                end else begin
                    st   <= OPR;
                    want <= 8'd3 * cyc_xx(din);         // instruccion NORMAL  -> cycles*3
                end
            end
        end
        PFX_W: begin
            op2 <= din; oplen <= len_of(op,din); nfetch <= 3'd2; immn <= 2'd0;
            st  <= psw[SK] ? SKIPI : OPR;
            // ⚠ CYCLE-TIMING para instrucciones con PREFIJO. Se llama a la funcion HOJA de la
            //   sub-tabla DIRECTAMENTE (no via un wrapper cyc_of/cycs_of): un wrapper que llama a
            //   otra funcion dentro de una asignacion NO-BLOQUEANTE devuelve 0 en Verilator (el
            //   mismo cyc_of en un $display da el valor correcto). Con esto want queda bien.
            case( op )
                8'h48: want <= 8'd3 * (psw[SK] ? cycs_48(din) : cyc_48(din));
                8'h4c: want <= 8'd3 * (psw[SK] ? cycs_4c(din) : cyc_4c(din));
                8'h4d: want <= 8'd3 * (psw[SK] ? cycs_4d(din) : cyc_4d(din));
                8'h60: want <= 8'd3 * (psw[SK] ? cycs_60(din) : cyc_60(din));
                8'h64: want <= 8'd3 * (psw[SK] ? cycs_64(din) : cyc_64(din));
                8'h70: want <= 8'd3 * (psw[SK] ? cycs_70(din) : cyc_70(din));
                default: want <= 8'd3 * (psw[SK] ? cycs_74(din) : cyc_74(din)); // 0x74
            endcase
        end

        // -------------------------------------------------- SKIP (el condicional del 7810)
        SKIPI: begin
            pc      <= pc + {13'd0,oplen} - {13'd0,nfetch};
            psw[SK] <= 0;
            st      <= FETCH;
        end

        // -------------------------------------------------- operandos
        // Los operandos se leen EN ORDEN: el 1o va a o0, el 2o a o1 (inmediato de 16 bits =
        // {o1,o0}, little endian). 'immn' cuenta los ya leidos: hacerlo con nfetch/oplen a mano
        // es una fuente de erratas porque el punto de partida cambia si hay prefijo (2) o no (1).
        OPR: if( nfetch==oplen ) st <= EXEC;
             else begin addr <= pc; pc <= pc+16'd1; st <= OPR_W; end
        OPR_W: begin
            if( immn==2'd0 ) o0 <= din; else o1 <= din;
            immn   <= immn + 2'd1;
            nfetch <= nfetch + 3'd1;
            st     <= OPR;
        end

        // -------------------------------------------------- EJECUCION
        EXEC: begin
            st <= FETCH;                       // por defecto: siguiente instruccion
            if( is_prefix(op) ) begin
                case( op )
                // ---- 0x48: bit / rotaciones / skip sobre flags / EA<->memoria
                8'h48: case( op2 )
                    8'h0a: psw[SK] <=  psw[CY];                      // SK  CY
                    8'h1a: psw[SK] <= ~psw[CY];                      // SKN CY
                    8'h0c: psw[SK] <=  psw[ZF];                      // SK  Z
                    8'h1c: psw[SK] <= ~psw[ZF];                      // SKN Z
                    8'h0b: psw[SK] <=  psw[HC];                      // SK  HC
                    8'h2a: psw[CY] <= 0;                             // CLC
                    8'h2f: ea <= a * c;                              // MUL C  -> EA = A*C
                    // Desplazamientos/rotaciones sobre A(1) B(2) C(3): el registro va en op2[2:0]
                    8'h01: begin a <= {1'b0, a[7:1]};                // SLRC A
                                 psw[CY] <= a[0]; end
                    8'h21,8'h22,8'h23: begin                         // SLR r (desp. der. logico)
                                 wr_r(op2[2:0], {1'b0, rd_r(op2[2:0])>>1});
                                 psw[CY] <= rd_r(op2[2:0]) & 8'd1; end
                    // ⭐⭐ AQUI VIVIA EL BUG DEL C-CHIP (localizado 2026-07-16, BEAR-VS-WOLF §9).
                    //   El registro NO es op2[2:0]. El encoding de SLL/RLL es 0x_5/0x_6/0x_7 -> A/B/C,
                    //   asi que op2[2:0] da 5,6,7 = E,H,L: REGISTROS EQUIVOCADOS. Hay que RESTAR 4
                    //   (5-4=1=A, 6-4=2=B, 7-4=3=C). En SLR/RLR (0x_1/0x_2/0x_3) op2[2:0] SI da 1,2,3
                    //   directamente -> por eso el fallo era EXCLUSIVO de SLL y RLL.
                    //   Cadena del fallo: 'SLL A' (48 25) desplazaba E en vez de A -> el indice de la
                    //   tabla de saltos NO se duplicaba -> TABLE (48 A8) leia la tabla DESALINEADA un
                    //   byte (25 D9 en vez de D9 25) -> JB saltaba a 0xD925 en vez de 0x25D9 -> fuera
                    //   de ROM -> el decoder devuelve 8'hff = JR -1 = salta a si misma -> bucle
                    //   infinito -> el C-Chip deja de refrescar RAM[1005] -> mueren gatillo, granada,
                    //   coin y start a la vez. Invisible al oraculo del attract (152.335 PCs OK).
                    8'h25,8'h26,8'h27: begin                         // SLL r (desp. izq. logico)
                                 wr_r(op2[2:0]-3'd4, rd_r(op2[2:0]-3'd4)<<1);
                                 psw[CY] <= rd_r(op2[2:0]-3'd4)>>7; end
                    8'h31,8'h32,8'h33: begin                         // RLR r (rota der. POR CY)
                                 wr_r(op2[2:0], (rd_r(op2[2:0])>>1) | (psw[CY] ? 8'h80 : 8'h00));
                                 psw[CY] <= rd_r(op2[2:0]) & 8'd1; end
                    // ⚠ MISMO BUG que SLL: 0x35/0x36/0x37 = RLL A/B/C, pero op2[2:0] da 5,6,7 (E,H,L).
                    //   Restar 4. (MAME: 48 35 = RLL_A, 48 36 = RLL_B, 48 37 = RLL_C.)
                    8'h35,8'h36,8'h37: begin                         // RLL r (rota izq. POR CY)
                                 wr_r(op2[2:0]-3'd4, (rd_r(op2[2:0]-3'd4)<<1) | {7'd0,psw[CY]});
                                 psw[CY] <= rd_r(op2[2:0]-3'd4)>>7; end
                    8'ha4: ea <= {ea[14:0], 1'b0};                   // DSLL EA
                    8'ha8: begin addr <= pc + {8'd0,a} + 16'd1;      // TABLE: BC <- (PC+A+1)
                                 m16 <= 3'd3; st <= LD16A; end
                    8'h49,8'h54: psw[SK] <= 0;                       // SKIT (timers/serie: no usados)
                    8'h82: begin addr<={d,e}; st<=LD16A; m16<=3'd4; end  // LDEAX (DE) -> EA
                    8'h83: begin addr<=hl16;  st<=LD16A; m16<=3'd4; end  // LDEAX (HL) -> EA
                    8'h84: begin addr<={d,e}; st<=LD16A; m16<=3'd4;      // LDEAX (DE+) -> EA
                                 {d,e} <= {d,e} + 16'd2; end
                    8'h93: begin addr<=hl16;  st<=ST16A; m16<=3'd4;      // STEAX (HL) <- EA
                                 dout<=ea[7:0]; we<=1; end
                    8'h95: begin addr<=hl16;  st<=ST16A; m16<=3'd4;      // STEAX (HL+) <- EA
                                 dout<=ea[7:0]; we<=1;
                                 {h,l} <= hl16 + 16'd2; end
                    default: undef <= 1;
                endcase
                // ---- 0x4C: MOV A,sr   (registros especiales de LECTURA)
                8'h4c: case( op2 )
                    // MAME RP(): bits de ENTRADA (modo=1) devuelven el pin; bits de SALIDA (modo=0)
                    // devuelven el latch de salida. Ver la nota en la declaracion de ma/mb/mc.
                    8'hc0: a <= (pa_in & ma) | (pa_out & ~ma);
                    8'hc1: a <= (pb_in & mb) | (pb_out & ~mb);       // PB <- IN0 (MONEDAS; bits 4/5 salida=contadores)
                    8'hc2: a <= (pc_in & mc) | (pc_out & ~mc);       // PC <- IN1 (gatillo/start)
                    8'hc8: a <= anm;                                 // MOV A,ANM
                    8'he1,8'he2,8'he3: a <= 8'h00;                    // CR1/CR2/CR3 (A/D): no usados
                    8'he0: ;   // CR0 (A/D): en la tabla del 7810 de MAME es 'illegal2' = NO-OP.
                               // ⚠ NO poner A a 0: hay que hacer LO MISMO QUE EL ORACULO o la
                               //    traza diverge. El A/D no se usa en opwolf.
                    default: undef <= 1;
                endcase
                // ---- 0x4D: MOV sr,A   (registros especiales de ESCRITURA)
                8'h4d: case( op2 )
                    8'hc0: pa_out <= a;
                    8'hc1: pb_out <= a;                              // contadores de monedas
                    8'hc2: pc_out <= a;
                    8'hd2: ma <= a;                                  // MA: direccion de PA
                    8'hd3: mb <= a;                                  // MB: direccion de PB (bits 4/5=salida -> contadores)
                    8'hd4: mc <= a;                                  // MC: direccion de PC
                    8'hcc,8'hd0,8'hd1,8'hd7: ;                        // ETMM/MM/MCC/MF: no afectan a la lectura de puertos
                    default: undef <= 1;
                endcase
                // ---- 0x60: ALU GENERICA entre A y r (los dos sentidos). Ver la cabecera de la ALU.
                //      op2[7]=1 -> A op= r      op2[7]=0 -> r op= A
                8'h60: begin
                    // op2[7]=1 -> A op= r    |    op2[7]=0 -> r op= A
                    if( op2[7] ) begin
                        if( alu_writes(op2[6:3]) )
                            a <= alu_res(op2[6:3], a, rd_r(op2[2:0]), psw[CY]);
                        setz(   alu_res (op2[6:3], a, rd_r(op2[2:0]), psw[CY]) );
                        psw[SK] <= alu_skip(op2[6:3], a, rd_r(op2[2:0]), psw[CY]);
                        if( alu_cyf(op2[6:3]) ) begin
                            psw[CY] <= alu_cy(op2[6:3], a, rd_r(op2[2:0]), psw[CY]);
                            psw[HC] <= alu_hc(op2[6:3], a, rd_r(op2[2:0]), psw[CY]);
                        end
                    end else begin
                        if( alu_writes(op2[6:3]) )
                            wr_r(op2[2:0], alu_res(op2[6:3], rd_r(op2[2:0]), a, psw[CY]));
                        setz(   alu_res (op2[6:3], rd_r(op2[2:0]), a, psw[CY]) );
                        psw[SK] <= alu_skip(op2[6:3], rd_r(op2[2:0]), a, psw[CY]);
                        if( alu_cyf(op2[6:3]) ) begin
                            psw[CY] <= alu_cy(op2[6:3], rd_r(op2[2:0]), a, psw[CY]);
                            psw[HC] <= alu_hc(op2[6:3], rd_r(op2[2:0]), a, psw[CY]);
                        end
                    end
                end
                // ---- 0x74: la MISMA ALU pero con INMEDIATO.  op2[7]=0 -> r op= imm
                8'h74: casez( op2 )
                    8'b0???_????: begin                                  // op r,xx
                        if( alu_writes(op2[6:3]) )
                            wr_r(op2[2:0], alu_res(op2[6:3], rd_r(op2[2:0]), o0, psw[CY]));
                        setz(   alu_res (op2[6:3], rd_r(op2[2:0]), o0, psw[CY]) );
                        psw[SK] <= alu_skip(op2[6:3], rd_r(op2[2:0]), o0, psw[CY]);
                        if( alu_cyf(op2[6:3]) ) begin
                            psw[CY] <= alu_cy(op2[6:3], rd_r(op2[2:0]), o0, psw[CY]);
                            psw[HC] <= alu_hc(op2[6:3], rd_r(op2[2:0]), o0, psw[CY]);
                        end
                    end
                    // ---- operaciones de 16 bits sobre EA
                    8'haf: begin psw[SK] <= ea >  hl16; end              // DGT  EA,HL
                    8'hbf: begin psw[SK] <= ea <  hl16; end              // DLT  EA,HL
                    8'hc6: ea <= ea + {d,e};                             // DADD EA,DE
                    8'hc7: ea <= ea + hl16;                              // DADD EA,HL
                    8'hdf: begin psw[SK] <= (ea & hl16)==16'd0; end      // DOFF EA,HL
                    8'hed: begin psw[SK] <= ea != {b,c}; end             // DNE  EA,BC
                    8'h88: begin addr<=wa; ax_op<=A_AN; st<=MEMOPA; end  // ANAW wa: A &= (wa)
                    8'h98: begin addr<=wa; ax_op<=A_OR; st<=MEMOPA; end  // ORAW wa: A |= (wa)
                    default: undef <= 1;
                endcase
                // ---- 0x64: MVI sr,xx
                8'h64: case( op2 )
                    8'h00: pa_out <= o0;                             // MVI PA,xx
                    8'h01: pb_out <= o0;                             // MVI PB,xx
                    8'h05: ;                                         // MVI PF,xx
                    8'h06: mkh <= o0;
                    8'h07: mkl <= o0;                                // MKL: mascara de IRQ (bit3=INTF1)
                    8'h20: pa_out <= pa_out + o0;                    // ADINC PA,xx
                    8'h72: pc_out <= pc_out - o0;                    // SBI PC,xx
                    8'h77: mkl    <= mkl - o0;                       // SBI MKL,xx
                    8'h80: anm <= o0;                                // MVI ANM,xx
                    8'h83: eom <= o0;                                // MVI EOM,xx
                    8'h9b: eom <= eom | o0;                          // ORI EOM,xx
                    default: undef <= 1;
                endcase
                // ---- 0x70: accesos a memoria ABSOLUTA (direccion de 16 bits en el opcode)
                8'h70: case( op2 )
                    8'h69: begin addr<=w16; st<=LD_W;  rdst<=3'd1; end   // MOV A,(w)
                    8'h6b: begin addr<=w16; st<=LD_W;  rdst<=3'd3; end   // MOV C,(w)
                    8'h79: begin addr<=w16; dout<=a; we<=1; end          // MOV (w),A
                    8'h0f: begin addr<=w16; st<=LD16A; m16<=3'd1; end    // LSPD (w) -> SP
                    8'h1f: begin addr<=w16; st<=LD16A; m16<=3'd3; end    // LBCD (w) -> BC
                    8'h2f: begin addr<=w16; st<=LD16A; m16<=3'd2; end    // LDED (w) -> DE
                    8'h3f: begin addr<=w16; st<=LD16A; m16<=3'd0; end    // LHLD (w) -> HL
                    8'h0e: begin addr<=w16; st<=ST16A; m16<=3'd1;        // SSPD (w) <- SP
                                 dout<=sp[7:0]; we<=1; end
                    8'h2e: begin addr<=w16; st<=ST16A; m16<=3'd2;        // SDED (w) <- DE
                                 dout<=e; we<=1; end
                    8'h3e: begin addr<=w16; st<=ST16A; m16<=3'd0;        // SHLD (w) <- HL
                                 dout<=l; we<=1; end
                    8'h41: begin setf({1'b0,ea[7:0]}+{1'b0,a});          // EADD EA,A
                                 ea <= ea + {8'd0,a}; end
                    8'h1e: begin addr<=w16; st<=ST16A; m16<=3'd3;        // SBCD (w) <- BC
                                 dout<=c; we<=1; end
                    8'h7a: begin addr<=w16; dout<=b; we<=1; end          // MOV (w),B
                    8'h7b: begin addr<=w16; dout<=c; we<=1; end          // MOV (w),C
                    8'h7d: begin addr<=w16; dout<=e; we<=1; end          // MOV (w),E
                    // ⭐ ALU CONTRA MEMORIA — las usa el codigo de NIVEL de la EPROM (por eso solo
                    //    aparecen al EMPEZAR UNA PARTIDA, no en el attract).
                    8'hfa: begin addr<={d,e}; ax_op<=A_EQ;  st<=MEMOPA; end          // EQAX (DE)
                    8'hfb: begin addr<=hl16;  ax_op<=A_EQ;  st<=MEMOPA; end          // EQAX (HL)
                    8'hfd: begin addr<=hl16;  ax_op<=A_EQ;  st<=MEMOPA;              // EQAX (HL+)
                                 {h,l} <= hl16 + 16'd1; end
                    8'hff: begin addr<=hl16;  ax_op<=A_EQ;  st<=MEMOPA;              // EQAX (HL-)
                                 {h,l} <= hl16 - 16'd1; end
                    8'hed: begin addr<=hl16;  ax_op<=A_NE;  st<=MEMOPA;              // NEAX (HL+)
                                 {h,l} <= hl16 + 16'd1; end
                    8'hc3: begin addr<=hl16;  ax_op<=A_ADD; st<=MEMOPA; end          // ADDX (HL)
                    8'he4: begin addr<={d,e}; ax_op<=A_SUB; st<=MEMOPA;              // SUBX (DE+)
                                 {d,e} <= {d,e} + 16'd1; end
                    default: undef <= 1;
                endcase
                default: undef <= 1;
                endcase
            end else begin
                casez( op )
                8'h00: ;                                             // NOP
                8'hba: ien <= 0;                                     // DI
                8'haa: ien <= 1;                                     // EI
                8'h08,8'h09,8'h0a,8'h0b,8'h0c,8'h0d,8'h0e,8'h0f:     // MOV A,r
                       a <= rd_r(op[2:0]);
                8'h18,8'h19,8'h1a,8'h1b,8'h1c,8'h1d,8'h1e,8'h1f:     // MOV r,A
                       wr_r(op[2:0], a);
                8'h68,8'h69,8'h6a,8'h6b,8'h6c,8'h6d,8'h6e,8'h6f:     // MVI r,xx
                       wr_r(op[2:0], o0);
                // ⭐ INR/DCR: NO modifican CY, pero ACTIVAN SK si hay acarreo/prestamo.
                //   Asi es como el 7810 sale de los bucles:  "MVI B,n / DCR B / JR atras"
                //   -> el JR se SALTA cuando B pasa de 0 a FF.  (MAME: SKIP_CY y luego restaura CY.)
                //   Sin esto el bucle de espera del arranque NO TERMINA JAMAS: fue la primera
                //   divergencia contra la traza golden (instruccion 58).
                8'h41,8'h42,8'h43: begin                             // INR r  (A,B,C)
                       wr_r(op[2:0], rd_r(op[2:0])+8'd1);
                       setz( rd_r(op[2:0])+8'd1 );
                       psw[SK] <= rd_r(op[2:0])==8'hff; end          // acarreo
                8'h51,8'h52,8'h53: begin                             // DCR r  (A,B,C)
                       wr_r(op[2:0], rd_r(op[2:0])-8'd1);
                       setz( rd_r(op[2:0])-8'd1 );
                       psw[SK] <= rd_r(op[2:0])==8'h00; end          // prestamo
                8'h04: sp <= w16;                                    // LXI SP,w
                8'h14: {b,c} <= w16;                                 // LXI BC,w
                8'h24: {d,e} <= w16;                                 // LXI DE,w
                8'h34: {h,l} <= w16;                                 // LXI HL,w
                8'h44: ea    <= w16;                                 // LXI EA,w
                8'h54: begin pc <= w16; end                          // JMP w
                8'hc0,8'hc1,8'hc2,8'hc3,8'hc4,8'hc5,8'hc6,8'hc7,     // JR: relativo 6 bits CON SIGNO
                8'hc8,8'hc9,8'hca,8'hcb,8'hcc,8'hcd,8'hce,8'hcf,
                8'hd0,8'hd1,8'hd2,8'hd3,8'hd4,8'hd5,8'hd6,8'hd7,
                8'hd8,8'hd9,8'hda,8'hdb,8'hdc,8'hdd,8'hde,8'hdf,
                8'he0,8'he1,8'he2,8'he3,8'he4,8'he5,8'he6,8'he7,
                8'he8,8'he9,8'hea,8'heb,8'hec,8'hed,8'hee,8'hef,
                8'hf0,8'hf1,8'hf2,8'hf3,8'hf4,8'hf5,8'hf6,8'hf7,
                8'hf8,8'hf9,8'hfa,8'hfb,8'hfc,8'hfd,8'hfe,8'hff:
                       pc <= pc + {{10{op[5]}}, op[5:0]};
                // ⭐⭐ ALU CON INMEDIATO, GENERICA (16 instrucciones en un solo case).
                //   Patron sacado de la tabla de MAME: opcodes 0x_6 / 0x_7 con bit7=0
                //        alu_op = {op[6:4], op[0]}   destino = A   origen = inmediato
                //   07=ANI 16=XRI 17=ORI 26=ADINC 27=GTI 36=SUINB 37=LTI 46=ADI 47=ONI
                //   56=ACI 57=OFFI 66=SUI 67=NEI 76=SBI 77=EQI
                //   ⚠ LAS COMPARACIONES SON RESTAS DE VERDAD: ademas de SK fijan Z, CY (PRESTAMO)
                //     y HC. Ignorar el CY costo la 2a divergencia contra el golden
                //     ('MOV A,CR0 / EQI A,$80 / SKN CY': 0-0x80 da PRESTAMO -> el SKN CY NO salta).
                8'b0???_011?: begin
                    if( alu_writes({op[6:4],op[0]}) )
                        a <= alu_res({op[6:4],op[0]}, a, o0, psw[CY]);
                    setz(   alu_res ({op[6:4],op[0]}, a, o0, psw[CY]) );
                    psw[SK] <= alu_skip({op[6:4],op[0]}, a, o0, psw[CY]);
                    if( alu_cyf({op[6:4],op[0]}) ) begin
                        psw[CY] <= alu_cy({op[6:4],op[0]}, a, o0, psw[CY]);
                        psw[HC] <= alu_hc({op[6:4],op[0]}, a, o0, psw[CY]);
                    end
                end
                // ⭐ LDAX / STAX: familia COMPLETA (la EPROM del juego usa todas las variantes).
                //   op[3:0]:  9=(BC)  A=(DE)  B=(HL)  C=(DE+)  D=(HL+)  E=(DE-)  F=(HL-)
                8'h29: begin addr<={b,c}; st<=LD_W; rdst<=3'd1; end  // LDAX (BC)
                8'h2a: begin addr<={d,e}; st<=LD_W; rdst<=3'd1; end  // LDAX (DE)
                8'h2b: begin addr<=hl16;  st<=LD_W; rdst<=3'd1; end  // LDAX (HL)
                8'h2c: begin addr<={d,e}; st<=LD_W; rdst<=3'd1;      // LDAX (DE+)
                            {d,e} <= {d,e} + 16'd1; end
                8'h2d: begin addr<=hl16;  st<=LD_W; rdst<=3'd1;      // LDAX (HL+)
                            {h,l} <= hl16 + 16'd1; end
                8'h2e: begin addr<={d,e}; st<=LD_W; rdst<=3'd1;      // LDAX (DE-)
                            {d,e} <= {d,e} - 16'd1; end
                8'h2f: begin addr<=hl16;  st<=LD_W; rdst<=3'd1;      // LDAX (HL-)
                            {h,l} <= hl16 - 16'd1; end
                8'h39: begin addr<={b,c}; dout<=a; we<=1; end        // STAX (BC)
                8'h3a: begin addr<={d,e}; dout<=a; we<=1; end        // STAX (DE)
                8'h3b: begin addr<=hl16;  dout<=a; we<=1; end        // STAX (HL)
                8'h3c: begin addr<={d,e}; dout<=a; we<=1;            // STAX (DE+)
                            {d,e} <= {d,e} + 16'd1; end
                8'h3d: begin addr<=hl16;  dout<=a; we<=1;            // STAX (HL+)
                            {h,l} <= hl16 + 16'd1; end
                8'h3e: begin addr<={d,e}; dout<=a; we<=1;            // STAX (DE-)
                            {d,e} <= {d,e} - 16'd1; end
                8'h3f: begin addr<=hl16;  dout<=a; we<=1;            // STAX (HL-)
                            {h,l} <= hl16 - 16'd1; end
                8'h01: begin addr<=wa; st<=LD_W; rdst<=3'd1; end     // LDAW wa
                8'h32: {h,l} <= hl16 + 16'd1;                        // INX HL
                8'h13: {b,c} <= {b,c} - 16'd1;                       // DCX BC
                8'h11: begin                                          // EXX (BC/DE/HL <-> banco 2)
                       b<=b2; c<=c2; d<=d2; e<=e2; h<=h2; l<=l2;
                       b2<=b;  c2<=c;  d2<=d;  e2<=e;  h2<=h;  l2<=l; end
                8'h10: begin v<=v2; a<=a2; ea<=ea2;                   // EXA (VA/EA <-> banco 2)
                       v2<=v; a2<=a; ea2<=ea; end
                8'h50: begin h<=h2; l<=l2; h2<=h; l2<=l; end          // EXH (HL <-> HL')
                8'h23: {d,e} <= {d,e} - 16'd1;                        // DCX DE
                8'ha8: ea <= ea + 16'd1;                              // INX EA
                8'ha9: ea <= ea - 16'd1;                              // DCX EA
                8'hb9: begin st<=POP1; retsel<=2'd1; psw[SK]<=1; end  // RETS (RET y SALTA la sig.)
                8'h21: pc <= {b,c};                                   // JB  (salta a BC)
                // CALF: llamada CORTA dentro de la pagina 0x0800-0x0FFF.
                //   destino = {0x08 + (op & 7), imm}   (MAME: w.b.h = 0x08 + (OP & 0x07))
                8'h78,8'h79,8'h7a,8'h7b,8'h7c,8'h7d,8'h7e,8'h7f: begin
                       pushv_h <= pc[15:8]; pushv_l <= pc[7:0];
                       tmp     <= {4'h0, 1'b1, op[2:0], o0};
                       st      <= PUSH1; retsel <= 0; end
                // SOFTI: interrupcion software. ⚠ Apila el PSW ADEMAS del PC (la IRQ normal NO).
                8'h72: begin addr <= sp-16'd1; dout <= psw; we <= 1;
                       sp      <= sp - 16'd1;
                       pushv_h <= pc[15:8]; pushv_l <= pc[7:0];
                       tmp     <= 16'h0060;                   // vector de SOFTI
                       st      <= PUSH1; retsel <= 0; end
                // BLOCK: copia (HL)->(DE) byte a byte, DE++/HL++/C--, y se REPITE ella misma
                //   (MAME hace PC-- hasta que C pasa de 0 a 0xFF).
                8'h31: begin addr <= hl16; st <= BLK; end
                8'h49: begin addr<={b,c}; dout<=o0; we<=1; end        // MVIX (BC),xx
                8'h4a: begin addr<={d,e}; dout<=o0; we<=1; end        // MVIX (DE),xx
                // ---- direccionamiento INDEXADO (base + registro/inmediato)
                8'hac: begin addr<=hl16+{8'd0,a};  st<=LD_W; rdst<=3'd1; end  // LDAX (HL+A)
                8'hab: begin addr<={d,e}+{8'd0,o0};st<=LD_W; rdst<=3'd1; end  // LDAX (DE+xx)
                8'had: begin addr<=hl16+{8'd0,b};  st<=LD_W; rdst<=3'd1; end  // LDAX (HL+B)
                8'haf: begin addr<=hl16+{8'd0,o0}; st<=LD_W; rdst<=3'd1; end  // LDAX (HL+xx)
                8'hbb: begin addr<={d,e}+{8'd0,o0};dout<=a; we<=1; end        // STAX (DE+xx)
                8'hbd: begin addr<=hl16+{8'd0,b};  dout<=a; we<=1; end        // STAX (HL+B)
                8'hbc: begin addr<=hl16+{8'd0,a};  dout<=a; we<=1; end        // STAX (HL+A)
                8'hbf: begin addr<=hl16+{8'd0,o0}; dout<=a; we<=1; end        // STAX (HL+xx)
                8'hae: begin addr<=hl16+ea;        st<=LD16A; m16<=3'd4; end  // LDAX (HL+EA)
                8'hbe: begin addr<=hl16+ea;        st<=ST16A; m16<=3'd4;      // STAX (HL+EA)
                            dout<=ea[7:0]; we<=1; end
                8'h61: begin                                          // DAA (ajuste decimal BCD)
                       // MAME: el ajuste depende de HC, del nibble bajo, del alto y del CY.
                       // ⚠ El CY viejo se MANTIENE (PSW |= old_cy), no se limpia.
                       a <= a + daa_adj(a, psw[HC], psw[CY]);
                       psw[ZF] <= (a + daa_adj(a, psw[HC], psw[CY]))==8'd0;
                       psw[CY] <= psw[CY] |
                            ((({1'b0,a} + {1'b0,daa_adj(a, psw[HC], psw[CY])}) & 9'h100)!=0);
                       end
                8'h40: begin pushv_h<=pc[15:8]; pushv_l<=pc[7:0];    // CALL w
                            tmp<=w16; st<=PUSH1; retsel<=0; end
                8'hb8: begin st<=POP1; retsel<=2'd1; end             // RET
                8'h62: begin st<=POP1; retsel<=2'd2; end             // RETI
                8'hb0,8'hb1,8'hb2,8'hb3,8'hb4: begin                 // PUSH rp
                       case(op[2:0])
                         3'd0: {pushv_h,pushv_l} <= {v,a};
                         3'd1: {pushv_h,pushv_l} <= {b,c};
                         3'd2: {pushv_h,pushv_l} <= {d,e};
                         3'd3: {pushv_h,pushv_l} <= {h,l};
                         default:{pushv_h,pushv_l} <= ea;
                       endcase
                       tmp <= 16'hffff;                              // marca: no hay salto
                       st  <= PUSH1; retsel <= 0; end
                8'ha0,8'ha1,8'ha2,8'ha3,8'ha4: begin                 // POP rp
                       rdst <= op[2:0]; st <= POP1; retsel <= 2'd3; end
                8'ha5: ea <= {b,c};                                  // DMOV EA,BC
                8'ha6: ea <= {d,e};                                  // DMOV EA,DE
                8'ha7: ea <= hl16;                                   // DMOV EA,HL
                8'hb5: {b,c} <= ea;                                  // DMOV BC,EA
                8'hb6: {d,e} <= ea;                                  // DMOV DE,EA
                8'hb7: {h,l} <= ea;                                  // DMOV HL,EA
                // JRE: salto relativo de 9 bits CON SIGNO. El bit0 del OPCODE es el signo.
                8'h4e: pc <= pc + {8'd0, o0};
                8'h4f: pc <= pc + {8'd0, o0} - 16'd256;
                // CALT: llamada por TABLA de vectores en 0x0080 (indice = 5 bits del opcode)
                8'h80,8'h81,8'h82,8'h83,8'h84,8'h85,8'h86,8'h87,
                8'h88,8'h89,8'h8a,8'h8b,8'h8c,8'h8d,8'h8e,8'h8f,
                8'h90,8'h91,8'h92,8'h93,8'h94,8'h95,8'h96,8'h97,
                8'h98,8'h99,8'h9a,8'h9b,8'h9c,8'h9d,8'h9e,8'h9f: begin
                       pushv_h <= pc[15:8]; pushv_l <= pc[7:0];
                       tmp     <= 16'hfffe;                          // marca: el destino se LEE de la tabla
                       calt    <= {9'd0, op[4:0], 1'b0} + 16'h0080;  // 0x80 + 2*idx
                       st      <= PUSH1; retsel <= 0; end
                8'h63: begin addr<=wa; dout<=a; we<=1; end           // STAW wa
                8'h02: sp <= sp + 16'd1;                             // INX SP
                8'h03: sp <= sp - 16'd1;                             // DCX SP
                8'h12: {b,c} <= {b,c} + 16'd1;                       // INX BC
                8'h22: {d,e} <= {d,e} + 16'd1;                       // INX DE
                8'h33: {h,l} <= hl16 - 16'd1;                        // DCX HL
                8'h4b: begin addr<=hl16; dout<=o0; we<=1; end        // MVIX (HL),xx
                // Operaciones que LEEN de 'wa' y luego actuan (necesitan un ciclo de memoria)
                8'h58,8'h59,8'h5a,8'h5b,8'h5c,8'h5d,8'h5e,8'h5f: begin  // BIT n,wa
                       addr<=wa; bitn<=op[2:0]; memop<=2'd1; st<=MEMOP; end
                // ⭐ ALU sobre (wa) con inmediato: 8 instrucciones en un case.
                //   05=ANIW 15=ORIW 25=GTIW 35=LTIW 45=ONIW 55=OFFIW 65=NEIW 75=EQIW
                8'b0???_0101: begin addr<=wa; ax_op<={op[6:4],1'b1}; st<=MEMOPW; end
                8'h71: begin addr<=wa; dout<=o1; we<=1; end          // MVIW wa,xx
                8'h20: begin addr<=wa; ax_op<=A_ADD; st<=MEMOPI; end // INRW wa  (+1)
                8'h30: begin addr<=wa; ax_op<=A_SUB; st<=MEMOPI; end // DCRW wa  (-1)
                default: undef <= 1;                                 // <-- opcode SIN implementar
                endcase
            end
        end

        // BLOCK: (DE) <- (HL); DE++, HL++, C--.  Si C NO ha dado la vuelta, se REPITE (pc-1).
        BLK: begin
            addr  <= {d,e};
            dout  <= din;
            we    <= 1;
            {d,e} <= {d,e} + 16'd1;
            {h,l} <= hl16  + 16'd1;
            c     <= c - 8'd1;
            if( c == 8'h00 ) psw[CY] <= 1;          // se acabo (C pasa a 0xFF)
            else begin
                psw[CY] <= 0;
                pc      <= pc - 16'd1;              // vuelve a ejecutar el BLOCK
            end
            st <= FETCH;
        end

        // ⭐ ALU sobre (wa) con inmediato: 'din' es (wa), 'o1' el inmediato.
        //    Solo las logicas/aritmeticas ESCRIBEN de vuelta; las comparaciones solo activan SK.
        MEMOPW: begin
            setz(   alu_res (ax_op, din, o1, psw[CY]) );
            psw[SK] <= alu_skip(ax_op, din, o1, psw[CY]);
            if( alu_cyf(ax_op) ) begin
                psw[CY] <= alu_cy(ax_op, din, o1, psw[CY]);
                psw[HC] <= alu_hc(ax_op, din, o1, psw[CY]);
            end
            if( alu_writes(ax_op) ) begin
                dout <= alu_res(ax_op, din, o1, psw[CY]);   // addr sigue apuntando a (wa)
                we   <= 1;
            end
            st <= FETCH;
        end

        // INRW/DCRW (wa): incrementa/decrementa la posicion de memoria
        MEMOPI: begin
            dout <= ax_op==A_ADD ? din + 8'd1 : din - 8'd1;
            we   <= 1;
            setz( ax_op==A_ADD ? din + 8'd1 : din - 8'd1 );
            psw[SK] <= ax_op==A_ADD ? (din==8'hff) : (din==8'h00);   // SK en acarreo/prestamo
            st <= FETCH;
        end

        // ⭐ ALU CONTRA MEMORIA: 'din' es el operando de memoria; A es el otro.
        MEMOPA: begin
            if( alu_writes(ax_op) ) a <= alu_res(ax_op, a, din, psw[CY]);
            setz(   alu_res (ax_op, a, din, psw[CY]) );
            psw[SK] <= alu_skip(ax_op, a, din, psw[CY]);
            if( alu_cyf(ax_op) ) begin
                psw[CY] <= alu_cy(ax_op, a, din, psw[CY]);
                psw[HC] <= alu_hc(ax_op, a, din, psw[CY]);
            end
            st <= FETCH;
        end

        // CALT: ya apilado el retorno, ahora se LEE el vector de la tabla (0x80 + 2*idx)
        CALTRD: begin addr <= calt; m16 <= 3'd5; st <= LD16A; end

        // -------------------------------------------------- BIT / EQIW / ANIW: leen de 'wa'
        MEMOP: begin
            case( memop )
                2'd1: begin psw[SK] <= din[bitn]; st <= FETCH; end             // BIT n,wa
                2'd2: begin sub_flags(din, o1); psw[SK] <= (din==o1);          // EQIW wa,xx
                            st <= FETCH; end
                default: begin dout <= din & o1; we <= 1;                      // ANIW wa,xx
                            setz(din & o1); st <= FETCH; end                   // (addr sigue en wa)
            endcase
        end

        // -------------------------------------------------- lectura de memoria (1 byte)
        LD_W: begin
            wr_r(rdst, din);
            st <= FETCH;
        end

        // -------------------------------------------------- lectura/escritura de 16 bits
        // (LHLD/LSPD/LDED/LBCD/LDEAX  y  SHLD/SSPD/SDED/STEAX). Little-endian: bajo primero.
        // m16: 0=HL 1=SP 2=DE 3=BC 4=EA
        LD16A: begin tmp[7:0] <= din; addr <= addr + 16'd1; st <= LD16B; end
        LD16B: begin
            case( m16 )
                3'd0: {h,l} <= {din, tmp[7:0]};
                3'd1: sp    <= {din, tmp[7:0]};
                3'd2: {d,e} <= {din, tmp[7:0]};
                3'd3: {b,c} <= {din, tmp[7:0]};
                3'd5: pc    <= {din, tmp[7:0]};      // CALT: destino leido de la tabla
                default: ea <= {din, tmp[7:0]};
            endcase
            st <= FETCH;
        end
        ST16A: begin        // el byte bajo ya se escribio al lanzar la instruccion
            addr <= addr + 16'd1;
            case( m16 )
                3'd0: dout <= h;
                3'd1: dout <= sp[15:8];
                3'd2: dout <= d;
                3'd3: dout <= b;
                default: dout <= ea[15:8];
            endcase
            we <= 1;
            st <= FETCH;
        end

        // -------------------------------------------------- PUSH (2 bytes, SP decreciente)
        PUSH1: begin addr <= sp-16'd1; dout <= pushv_h; we <= 1; st <= PUSH2; end
        PUSH2: begin
            // ⚠ NO se puede pedir la lectura de la tabla del CALT EN ESTE MISMO ciclo: 'addr' se
            //   sobrescribiria y el byte bajo del retorno se escribiria EN LA TABLA en vez de en la
            //   pila (sintoma: el RET vuelve a una direccion corrida). Hace falta un estado aparte.
            addr <= sp-16'd2; dout <= pushv_l; we <= 1; sp <= sp-16'd2;
            if( tmp==16'hfffe )      st <= CALTRD;                   // CALT
            else begin
                if( tmp!=16'hffff ) pc <= tmp;                       // CALL/IRQ saltan; PUSH no
                st <= FETCH;
            end
        end

        // -------------------------------------------------- POP (2 bytes)
        POP1: begin addr <= sp; st <= POP2; end
        POP2: begin
            tmp[7:0] <= din;
            addr     <= sp + 16'd1;
            sp       <= sp + 16'd2;
            st       <= JUMP;
        end
        JUMP: begin
            case( retsel )
                2'd1: pc <= {din, tmp[7:0]};                          // RET
                2'd2: begin pc <= {din, tmp[7:0]};                    // RETI: falta el PSW
                            addr <= sp; end
                default: case( rdst )                                 // POP rp
                    3'd0: {v,a} <= {din, tmp[7:0]};
                    3'd1: {b,c} <= {din, tmp[7:0]};
                    3'd2: {d,e} <= {din, tmp[7:0]};
                    3'd3: {h,l} <= {din, tmp[7:0]};
                    default: ea <= {din, tmp[7:0]};
                endcase
            endcase
            st <= retsel==2'd2 ? POPSW : FETCH;      // RETI: aun queda el PSW por desapilar
        end

        // RETI: restaura los FLAGS que la interrupcion habia apilado
        POPSW: begin
            psw <= din;
            sp  <= sp + 16'd1;
            st  <= FETCH;
        end

        default: st <= FETCH;
        endcase
        end
    end
end

endmodule
