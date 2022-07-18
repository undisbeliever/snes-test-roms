// A simple test to demonstrate brightness 0 is not black on a SNES console.
//
// Copyright (c) 2021, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "INIDISP BRIGHTNESS 0"
define VERSION = 1

architecture wdc65816-strict

include "../common.inc"

createCodeBlock(code,       0x808000, 0x80ffaf)

createRamBlock(stack,       0x7e1f80, 0x7e1fff)


include "../reset_handler.inc"
include "../break_handler.inc"
include "../dma_forceblank.inc"



// Mode 0
constant VRAM_BG1_MAP_WADDR   = 0x0000
constant VRAM_BG1_TILES_WADDR = 0x1000



// This demo does not use VBlank Interrupts.
constant NmiHandler = BreakHandler



au()
iu()
code()
function Main {
    rep     #$30
    sep     #$20
a8()
i16()
    // Setup PPU registers

    // Enable Force-Blank
    lda.b   #INIDISP.force | 0
    sta.w   INIDISP


    // Mode 0
    stz.w   BGMODE

    lda.b   #TM.bg1
    sta.w   TM

    lda.b   #(VRAM_BG1_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG1SC

    lda.b   #(VRAM_BG1_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg1.shift
    sta.w   BG12NBA


    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Palette)

    ldx.w   #VRAM_BG1_MAP_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg1_Tilemap)

    ldx.w   #VRAM_BG1_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg1_Tiles)



    // Enable display, 0 brightness
    lda.b   #0
    sta.w   INIDISP



    MainLoop:
        wai
        bra     MainLoop
}



namespace Resources {


// Palette
// Colour 0:    white
// Colours 1-3: black
Palette:
    dw  0xffff, 0x0000, 0x0000, 0x0000
constant Palette.size = pc() - Palette


// BG 1 tiles
// 2bpp
// Tile 0: all pixels colour 0
// Tile 1: all pixels colour 1
Bg1_Tiles:
    fill 16, 0x00
    fill 16, 0xff
constant Bg1_Tiles.size = pc() - Bg1_Tiles


// BG 1 tilemap
// Checkerboard pattern
Bg1_Tilemap:
    variable x = 0
    variable y = 0

    while y < 32 {
        x = 0;
        while x < 32 {
            dw  (y ^ x) & 1

            x = x + 1
        }

        y = y + 1
    }
constant Bg1_Tilemap.size = pc() - Bg1_Tilemap

assert(Bg1_Tilemap.size == 2048)

}


finalizeMemory()

