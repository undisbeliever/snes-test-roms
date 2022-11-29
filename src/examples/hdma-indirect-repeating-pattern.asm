// Test ROM showing how to use HDMA indirect mode to repeat a scanline pattern multiple times.
//
// This test ROM was used to generate a screenshot for the SNESdev wiki.
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "HDMA REPEATING DATA"
define VERSION = 1


architecture wdc65816-strict


include "../common.inc"


createCodeBlock(code,       0x808000, 0x80ffaf)

createRamBlock(zeropage,    0x000000, 0x0000ff)
createRamBlock(lowram,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)
createRamBlock(wram7e,      0x7e2000, 0x7effff)


include "../reset_handler.inc"
include "../break_handler.inc"
include "../dma_forceblank.inc"


constant VRAM_BG1_MAP_WADDR   = 0x0000
constant VRAM_BG1_TILES_WADDR = 0x1000



// Setup the HDMA registers.
//
// Uses DMA channel 7.
//
// REQUIRES: 8 bit A, 16 bit Index, DB = 0x80, DP = 0
// REQUIRES: HDMA disabled
a8()
i16()
code()
function SetupHdma {
    // HDMA to `BG1HOFS`
    lda.b   #DMAP.direction.toPpu | DMAP.addressing.indirect | DMAP.transfer.writeTwice
    sta.w   DMAP7

    lda.b   #BG1HOFS
    sta.w   BBAD7

    // HDMA table address
    ldx.w   #IndirectHdmaTable
    stx.w   A1T7
    lda.b   #IndirectHdmaTable >> 16
    sta.w   A1B7

    // HDMA indirect bank
    lda.b   #SineTable >> 16
    sta.w   DASB7

    rts
}



// VBlank routine.
//
// REQUIRES: 8 bit A, 16 bit Index, DB = 0x80, DP = 0
macro VBlank() {
    // Enable HDMA.
    // HDMA should be enabled during VBlank.
    // There is no need to write to `HDMAEN` on every VBlank, it can be written to on a single VBlank.
    lda.b   #HDMAEN.dma7
    sta.w   HDMAEN
}

include "../vblank_interrupts.inc"



// Setup PPU registers and load data to the PPU.
//
// REQUIRES: 8 bit A, 16 bit Index, DB = 0x80, DP = 0
// REQUIRES: In force-blank
a8()
i16()
code()
function SetupPpu {
    lda.b   #BGMODE.mode0
    sta.w   BGMODE

    lda.b   #(VRAM_BG1_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG1SC

    lda.b   #(VRAM_BG1_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg1.shift
    sta.w   BG12NBA


    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Bg1_Palette)


    ldx.w   #VRAM_BG1_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg1_Tiles)

    ldx.w   #VRAM_BG1_MAP_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg1_Tilemap)


    lda.b   #TM.bg1
    sta.w   TM

    rts
}



au()
iu()
code()
function Main {
    rep     #$30
    sep     #$20
a8()
i16()
    // Setup PPU
    lda.b   #INIDISP.force | 0x0f
    sta.w   INIDISP

    jsr     SetupPpu
    jsr     SetupHdma

    EnableVblankInterrupts()

    jsr     WaitFrame

    lda.b   #0x0f
    sta.w   INIDISP


    MainLoop:
        jsr     WaitFrame
        jmp     MainLoop
}



// Array of `BG1HOFS` values for every scanline
SineTable:
    // Sine wave, calculated using python:
    // >>> import math
    // >>> [ round(16.5 * math.sin(math.radians(i * 360 / 48))) for i in range(48) ]
    dw  0, 2, 4, 6, 8, 10, 12, 13, 14, 15, 16, 16, 16, 16, 16, 15, 14, 13, 12, 10, 8, 6, 4, 2, 0, -2, -4, -6, -8, -10, -12, -13, -14, -15, -16, -16, -16, -16, -16, -15, -14, -13, -12, -10, -8, -6, -4, -2

constant SineTable.size = pc() - SineTable

assert(SineTable.size == 48 * 2)



// Indirect HDMA Table for the `BG1HOFS` register (one register, write twice transfer pattern).
IndirectHdmaTable:
    db  0x80 | 48       // 48 scanlines, repeat
        // Word address to BG1HOFS data
        dw  SineTable

    db  0x80 | 48       // 48 scanlines, repeat
        dw  SineTable

    db  0x80 | 48       // 48 scanlines, repeat
        dw  SineTable

    db  0x80 | 48       // 48 scanlines, repeat
        dw  SineTable

    db  0x80 | 48       // 48 scanlines, repeat
        dw  SineTable

    db  0               // End HDMA table
                        // Not required.  HDMA ends at the Vertical Blanking Period.


// Resources
// =========

namespace Resources {
    insert Bg1_Palette,  "../../gen/hdma-hoffset-examples/vertical-bar-2bpp.palette"
    insert Bg1_Tiles,   "../../gen/hdma-hoffset-examples/vertical-bar-2bpp.2bpp"
    insert Bg1_Tilemap, "../../gen/hdma-hoffset-examples/vertical-bar-2bpp.tilemap"
}




