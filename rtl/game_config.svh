`ifndef GAME_CONFIG_SVH
`define GAME_CONFIG_SVH
`define GAME_RAINBOW        0
`define GAME_RAINBOW_EXTRA  1
`define GAME_RASTAN         2
`define GAME_CADASH         3
`define GAME_VOLFIED        4
`define CFG_ROM_BASE(g)        24'h000000
`define CFG_ROM_TOP(g)         (((g) == `GAME_RASTAN) ? 24'h05FFFF : 24'h07FFFF)
`define CFG_WORK_RAM_BASE(g)   24'h10C000
`define CFG_WORK_RAM_TOP(g)    24'h10FFFF
`define CFG_PALETTE_BASE(g)    24'h200000
`define CFG_PALETTE_TOP(g)     24'h200FFF
`define CFG_EXT_RAM_BASE(g)    (((g) == `GAME_RASTAN) ? 24'hFF0000 : 24'h201000)
`define CFG_EXT_RAM_TOP(g)     (((g) == `GAME_RASTAN) ? 24'hFF0000 : 24'h203FFF)
`define CFG_DSWA_BASE(g)       (((g) == `GAME_RASTAN) ? 24'h390008 : 24'h390000)
`define CFG_DSWB_BASE(g)       (((g) == `GAME_RASTAN) ? 24'h39000A : 24'h3B0000)
`define CFG_P1_BASE(g)         24'h390000
`define CFG_P2_BASE(g)         24'h390002
`define CFG_SPECIAL_BASE(g)    24'h390004
`define CFG_SYSTEM_BASE(g)     24'h390006
`define CFG_SPRCTRL_BASE(g)    (((g) == `GAME_RASTAN) ? 24'h380000 : 24'h3A0000)
`define CFG_WATCHDOG_BASE(g)   24'h3C0000
`define CFG_CIU_BASE(g)        24'h3E0000
`define CFG_CCHIP_MEM_BASE(g)  (((g) == `GAME_RASTAN) ? 24'hFE0000 : 24'h800000)
`define CFG_CCHIP_ASIC_BASE(g) (((g) == `GAME_RASTAN) ? 24'hFE0800 : 24'h800800)
`define CFG_TILEMAP_BASE(g)    24'hC00000
`define CFG_YSCROLL_BASE(g)    24'hC20000
`define CFG_XSCROLL_BASE(g)    24'hC40000
`define CFG_VCUCTRL_BASE(g)    24'hC50000
`define CFG_SPRITERAM_BASE(g)  24'hD00000
`define CFG_VBL_IRQ_LEVEL(g)   (((g) == `GAME_RASTAN) ? 3'd5 : 3'd4)
`define CFG_Y_OFFSET(g)        (((g) == `GAME_RASTAN) ? 9'd8   : 9'd16)
`define CFG_V_VISIBLE(g)       (((g) == `GAME_RASTAN) ? 10'd240 : 10'd224)
`define CFG_GFX_SWAP_BELOW(g)  (((g) == `GAME_RASTAN) ? 25'h000000 : 25'h080000)
`define CFG_OBJ_SWAP_BELOW(g)  (((g) == `GAME_RASTAN) ? 25'h000000 : 25'h080000)
`define CFG_HAS_CCHIP(g)       (((g) == `GAME_RASTAN) ? 1'b0 : 1'b1)
`define CFG_HAS_MSM5205(g)     (((g) == `GAME_RASTAN) ? 1'b1 : 1'b0)
`define CFG_VOLFIED_ROM_BASE        24'h000000
`define CFG_VOLFIED_ROM_TOP         24'h0FFFFF
`define CFG_VOLFIED_WORK_RAM_BASE   24'h100000
`define CFG_VOLFIED_WORK_RAM_TOP    24'h103FFF
`define CFG_VOLFIED_SPRITERAM_BASE  24'h200000
`define CFG_VOLFIED_BITMAP_BASE     24'h400000
`define CFG_VOLFIED_BITMAP_TOP      24'h47FFFF
`define CFG_VOLFIED_PALETTE_BASE    24'h500000
`define CFG_VOLFIED_PALETTE_TOP     24'h503FFF
`define CFG_VOLFIED_VIDMASK_BASE    24'h600000
`define CFG_VOLFIED_SPRCTRL_BASE    24'h700000
`define CFG_VOLFIED_VIDCTRL_BASE    24'hD00000
`define CFG_VOLFIED_CIU_BASE        24'hE00000
`define CFG_VOLFIED_CCHIP_MEM_BASE  24'hF00000
`define CFG_VOLFIED_CCHIP_ASIC_BASE 24'hF00800
`define CFG_PALETTE_ENTRIES(g) (((g) == `GAME_VOLFIED) ? 14'd8192 : 14'd2048)
`define CFG_HAS_BITMAP(g)      (((g) == `GAME_VOLFIED) ? 1'b1 : 1'b0)
`define CFG_HAS_TILEMAP(g)     (((g) == `GAME_VOLFIED) ? 1'b0 : 1'b1)
`define CFG_HAS_YM2203(g)      (((g) == `GAME_VOLFIED) ? 1'b1 : 1'b0)
`define CFG_ROT270(g)          (((g) == `GAME_VOLFIED) ? 1'b1 : 1'b0)
`define CFG_HS_BLK0_BASE(g)  (((g) == `GAME_VOLFIED)       ? 24'h100200 : \
                              ((g) == `GAME_RAINBOW_EXTRA) ? 24'h10D0D2 : 24'h10D0CC)
`define CFG_HS_BLK0_LEN(g)   (((g) == `GAME_VOLFIED)       ? 16'h0026   : 16'h0032)
`define CFG_HS_BLK0_FIRST(g)  8'h00
`define CFG_HS_BLK0_LAST(g)  (((g) == `GAME_VOLFIED)       ? 8'h50      : \
                              ((g) == `GAME_RAINBOW_EXTRA) ? 8'h33      : 8'h32)

`define CFG_HS_BLK1_BASE(g)  (((g) == `GAME_VOLFIED)       ? 24'h000000 : \
                              ((g) == `GAME_RAINBOW_EXTRA) ? 24'h10E1B6 : 24'h10E1F2)
`define CFG_HS_BLK1_LEN(g)   (((g) == `GAME_VOLFIED)       ? 16'h0000   : 16'h0004)
`define CFG_HS_BLK1_FIRST(g)  8'h00
`define CFG_HS_BLK1_LAST(g)   8'h00
`define CFG_HS_TOTAL(g)      (((g) == `GAME_VOLFIED) ? 16'd38 : 16'd54)
`define CFG_HS_BASE(g)         `CFG_HS_BLK0_BASE(g)
`define CFG_HS_LEN(g)          `CFG_HS_BLK0_LEN(g)
`define CFG_CCHIP_CLK_NUM(g)   (((g) == `GAME_VOLFIED) ? 6'd10 : 6'd12)
`define CFG_SPR_COLBANK_W(g)   (((g) == `GAME_VOLFIED) ? 5'd9  : 5'd7)
`endif
