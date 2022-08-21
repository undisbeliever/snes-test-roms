// A simple test to see what happens to VRAM writes outside of the
// Vertical Blanking period.
//
// Test output:
//   * WHITE: VRAM writes are ignored
//   * RED tiles: VRAM writes change VRAM (and/or corrupt VRAM)
//   * BLANK: Test crashed
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "VRAM MID SCANLINE TEST"
define VERSION = 0

architecture wdc65816-strict

include "../common.inc"

createCodeBlock(code,       0x808000, 0x80ffaf)

createRamBlock(lowram,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)


include "../reset_handler.inc"
include "../break_handler.inc"
include "../dma_forceblank.inc"


constant VRAM_BG1_TILES_WADDR = 0x1000
constant VRAM_BG1_MAP_WADDR   = 0x0000


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

    // Setup PPU

    lda.b   #INIDISP.force | 0x0f
    sta.w   INIDISP

    jsr     ClearVramOamAndCgram

    lda.b   #BGMODE.mode0
    sta.w   BGMODE

    lda.b   #TM.bg1
    sta.w   TM

    lda.b   #(VRAM_BG1_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG1SC

    lda.b   #(VRAM_BG1_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg1.shift
    sta.w   BG12NBA


    // Transfer tiles to VRAM
    ldx.w   #VRAM_BG1_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Tiles_2bpp)


    // Transfer palettes to CGRAM
    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Palette)


    // Enable display, full brightness.
    lda.b   #0x0f
    sta.w   INIDISP



    MainLoop:
        // Wait until VBlank
        assert(HVBJOY.vBlank == 0x80)
        -
            lda.w   HVBJOY
            bpl     -


        lda.b   #VMAIN.increment.by1 | VMAIN.incrementMode.high
        sta.w   VMAIN

        // Wait until VBlank ends
        assert(HVBJOY.vBlank == 0x80)
        -
            lda.w   HVBJOY
            bmi     -

        constant LOOP_COUNT = 3072
        assert(LOOP_COUNT * 10 < 1340 / 8 * 200)
        ldy.w   #0x1234
        ldx.w   #LOOP_COUNT
        CorruptionLoop:
            sty.w   VMDATA

            dex
            bne     CorruptionLoop


        // Assert not in VBlank
        assert(HVBJOY.vBlank == 0x80)
        lda.w   HVBJOY
        bpl     +
            brk     #HVBJOY
        +


        jmp     MainLoop
}


namespace Resources {


Tiles_2bpp:
    fill    16, 0xffff
constant Tiles_2bpp.size = pc() - Tiles_2bpp


Palette:
    variable i = 0
    while i < 256 {
        if i == 3 {
            dw  ToPalette(31, 31, 31)
        } else {
            dw  ToPalette(31, 0, 0)
        }
        i = i + 1
    }
constant Palette.size = pc() - Palette
}

finalizeMemory()


