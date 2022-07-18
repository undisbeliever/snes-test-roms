// Tests if the `SETINI` (`$2133`) register reads the data bus too early.
//
// This test uses HDMA to write `0x02` to COLDATA ($2132) immediately followed
// by a write of `0x00` to `SETINI` ($2133).  If the SETINI register reads the
// data bus too early then the previous value on the data-bus (`0x02`) will
// briefly activate the "OBJ Interlace" flag and the PPU will output glitched
// sprite tiles.
//
// You may need to reset your console a few times for the glitch to appear.
//
// The sprite glitch appears ~60% of the time on my 3-chip 2/1/3 SFC console and
// ~30% of the time on my 1-chip SFC console.
//
//
// Copyright (c) 2021, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define ROM_NAME = "SETINI EARLY RD OBJI"
define VERSION = 1
define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan


architecture wdc65816-strict

include "../common.inc"

createCodeBlock(code,       0x808000, 0x80ffaf)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)

include "../reset_handler.inc"
include "../break_handler.inc"
include "../dma_forceblank.inc"



// BG2-4 uses WADDR 0
constant VRAM_OBJ_TILES_WADDR = 0x6000
constant VRAM_BG1_TILES_WADDR = 0x1000
constant VRAM_BG1_MAP_WADDR   = 0x1400



// This demo does not use VBlank Interrupts.
constant NmiHandler = BreakHandler



// Setup and initialize the PPU
// REQUIRES: 8 bit A, 16 bit Index, DB access registers
// MODIFIES: enables force-blank
macro SetupPpu() {
    assert8a()
    assert16i()

    stz.w   NMITIMEN


    // Set PPU registers

    lda.b   #INIDISP.force | 0xf
    sta.w   INIDISP

    lda.b   #1
    sta.w   BGMODE

    lda.b   #(VRAM_BG1_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG1SC

    lda.b   #(VRAM_BG1_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg1.shift
    sta.w   BG12NBA

    // BG2-BG4 have a TILE & MAP WADDR of 0 (as set by ResetRegisters)

    lda.b   #OBSEL.size.s32_64 | (VRAM_OBJ_TILES_WADDR / OBSEL.base.walign) << OBSEL.base.shift
    sta.w   OBSEL

    lda.b   #TM.bg1 | TM.obj
    sta.w   TM


    // Load OBJ palette
    lda.b   #128
    sta.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Obj_Palette)

    // Load OAM
    stz.w   OAMADDL
    stz.w   OAMADDH
    Dma.ForceBlank.ToOam(Resources.Obj_Oam)

    // Reset OAM hi table
    ldx.w   #0x0100
    stx.w   OAMADD

    lda.b   #0
    sta.w   OAMDATA
    sta.w   OAMDATA



    // Transfer tiles and map to VRAM

    ldx.w   #VRAM_BG1_MAP_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg1_Tilemap)


    ldx.w   #VRAM_OBJ_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Obj_Tiles)


    ldx.w   #VRAM_BG1_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Tiles_4bpp)


    // Transfer palette to CGRAM
    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Palette_4bpp)
}



// Setup HDMA transfer
// REQUIRES: 8 bit A, 16 bit Index, DB access registers
macro SetupHdma() {
    assert8a()
    assert16i()


    stz.w   HDMAEN


    lda.b   #DMAP.direction.toPpu | DMAP.addressing.absolute | DMAP.transfer.two
    sta.w   DMAP0

    assert(COLDATA + 1 == SETINI)
    lda.b   #COLDATA
    sta.w   BBAD0

    ldx.w   #HdmaTable
    stx.w   A1T0

    lda.b   #HdmaTable >> 16
    sta.w   A1B0


    lda.b   #HDMAEN.dma0
    sta.w   HDMAEN
}



au()
iu()
code()
function Main {
    rep     #$30
    sep     #$20
a8()
i16()
    sei

    SetupPpu()

    SetupHdma()


    lda.b   #0xf
    sta.w   INIDISP


    MainLoop:
        bra     MainLoop
}



namespace Resources {
    insert Bg1_Tilemap,  "../../gen/example-backgrounds/bricks-tilemap.bin"

    insert Tiles_4bpp,   "../../gen/example-backgrounds/bricks-4bpp-tiles.tiles"
    insert Palette_4bpp, "../../gen/example-backgrounds/bricks-4bpp-tiles.pal"

    insert Obj_Tiles,    "../../gen/example-backgrounds/obj-4bpp-tiles.tiles"
    insert Obj_Palette,  "../../gen/example-backgrounds/obj-4bpp-tiles.pal"
    insert Obj_Oam,      "../../gen/example-backgrounds/obj-oam.bin"
}



HdmaTable:
    variable n = 0
    while n < 256 {
        db  1
            // COLDATA
            // (corrupts sprite tiles if data-bus is read early)
            db  SETINI.objInterlace

            // SETINI
            db  0

        n = n + 1
    }
    db  0


