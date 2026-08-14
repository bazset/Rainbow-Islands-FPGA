// ALU del uPD78C11 — EXTRAIDA A SU PROPIO FICHERO PARA PODER VERIFICARLA AISLADA.
//
// ⭐ POR QUE: el golden (traza de MAME) es del ATTRACT, SIN moneda ni gatillo. Todo el codigo que
//    procesa ENTRADAS (rebote, contador de monedas, temporizadores de nivel) usa instrucciones que
//    LA TRAZA NUNCA EJERCITA -> el diff contra el golden NO las valida.
//    Se verifican EXHAUSTIVAMENTE contra un modelo de la semantica de MAME:
//        research/cchip/tb_alu.v  +  tools/upd7810_alu_vectors.py   (2M casos)
//    Ver GOTCHAS §I4: "un oraculo solo valida el codigo que EJECUTA".
localparam A_ADDNC=4'd0, A_AN=4'd1,   A_XR=4'd2,  A_OR=4'd3,   A_ADINC=4'd4, A_GT=4'd5,
           A_SUINB=4'd6, A_LT=4'd7,   A_ADD=4'd8, A_ON=4'd9,   A_ADC=4'd10,
           A_OFF=4'd11,  A_SUB=4'd12, A_NE=4'd13, A_SBB=4'd14, A_EQ=4'd15;

// Resultado de 9 bits: bit8 = ACARREO / PRESTAMO.
// ⚠⚠ DOS BUGS QUE COSTARON EL BRING-UP DEL ORIGINAL (entradas erraticas, escenario en bucle):
//   1) ADC/SBB NO fijaban el CY -> toda la aritmetica MULTI-BYTE salia mal (contadores de monedas,
//      rebote del gatillo, temporizadores que hacen avanzar el nivel).
//   2) ADINC(4) y SUINB(6) NO EXISTIAN: caian en el 'default' y NO HACIAN NADA.
// ⚠ Estas instrucciones NO las cubre el golden: la traza de MAME es del ATTRACT, sin moneda ni
//   gatillo, asi que el codigo que procesa ENTRADAS nunca se validó. Ver GOTCHAS §I4.
function [8:0] alu_full; input [3:0] o; input [7:0] x; input [7:0] y; input cyin;
    case( o )
        A_AN:    alu_full = {1'b0, x & y};
        A_XR:    alu_full = {1'b0, x ^ y};
        A_OR:    alu_full = {1'b0, x | y};
        A_ON,
        A_OFF:   alu_full = {1'b0, x & y};                    // solo testean bits
        A_ADD,
        A_ADDNC,
        A_ADINC: alu_full = {1'b0,x} + {1'b0,y};
        A_ADC:   alu_full = {1'b0,x} + {1'b0,y} + {8'd0,cyin};
        A_SUB,
        A_SUINB,
        A_LT, A_NE, A_EQ:
                 alu_full = {1'b0,x} - {1'b0,y};
        A_SBB:   alu_full = {1'b0,x} - {1'b0,y} - {8'd0,cyin};
        A_GT:    alu_full = {1'b0,x} - {1'b0,y} - 9'd1;       // GT: x-y-1; salta si NO hay prestamo
        default: alu_full = {1'b0, x};
    endcase
endfunction

function [7:0] alu_res; input [3:0] o; input [7:0] x; input [7:0] y; input cyin;
    alu_res = alu_full(o,x,y,cyin);                            // se trunca a los 8 bits bajos
endfunction

function alu_cy; input [3:0] o; input [7:0] x; input [7:0] y; input cyin;
    alu_cy = (alu_full(o,x,y,cyin) & 9'h100) != 9'd0;
endfunction

// MEDIO ACARREO (HC). MAME lo fija en ZHC_ADD/ZHC_SUB y EL DAA DEPENDE DE EL:
//    suma:  HC = (resultado & 15) <  (x & 15)
//    resta: HC = (resultado & 15) >  (x & 15)
function alu_hc; input [3:0] o; input [7:0] x; input [7:0] y; input cyin;
    reg [3:0] rl, xl;
    begin
        rl = alu_res(o,x,y,cyin) & 8'h0f;
        xl = x & 8'h0f;
        case( o )
            A_ADD, A_ADDNC, A_ADINC, A_ADC: alu_hc = rl < xl;
            A_SUB, A_SUINB, A_SBB,
            A_GT,  A_LT,    A_NE,    A_EQ:  alu_hc = rl > xl;
            default: alu_hc = 0;
        endcase
    end
endfunction

// ¿escribe el resultado?  Las de comparacion (GT/LT/ON/OFF/NE/EQ) NO.
function alu_writes; input [3:0] o;
    alu_writes = (o==A_AN)||(o==A_XR)||(o==A_OR)||(o==A_ADD)||(o==A_ADC)||(o==A_SUB)||
                 (o==A_SBB)||(o==A_ADDNC)||(o==A_ADINC)||(o==A_SUINB);
endfunction

// ¿toca el CY?  Las logicas y los tests de bits NO.
function alu_cyf; input [3:0] o;
    alu_cyf = !((o==A_AN)||(o==A_XR)||(o==A_OR)||(o==A_ON)||(o==A_OFF));
endfunction

// ¿ACTIVA EL FLAG SK?  ⚠ ADDNC/ADINC/SUINB TAMBIEN saltan (si NO hay acarreo/prestamo).
function alu_skip; input [3:0] o; input [7:0] x; input [7:0] y; input cyin;
    case( o )
        A_GT:    alu_skip = !alu_cy(o,x,y,cyin);              // SKIP_NC
        A_LT:    alu_skip =  alu_cy(o,x,y,cyin);              // SKIP_CY
        A_NE:    alu_skip = x != y;
        A_EQ:    alu_skip = x == y;
        A_ON:    alu_skip = (x & y) != 0;
        A_OFF:   alu_skip = (x & y) == 0;
        A_ADDNC,
        A_ADINC,
        A_SUINB: alu_skip = !alu_cy(o,x,y,cyin);              // SKIP_NC
        default: alu_skip = 0;
    endcase
endfunction
