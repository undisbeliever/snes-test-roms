// A test that reads and displays 12 bits from controller port 1 every visible scanline.
//
// SPDX-FileCopyrightText: © 2024 Marcus Rowe <undisbeliever@gmail.com>
// SPDX-License-Identifier: Zlib
//
// Copyright © 2024 Marcus Rowe <undisbeliever@gmail.com>
//
// This software is provided 'as-is', without any express or implied warranty.
// In no event will the authors be held liable for any damages arising from the
// use of this software.
//
// Permission is granted to anyone to use this software for any purpose, including
// commercial applications, and to alter it and redistribute it freely, subject to
// the following restrictions:
//
//    1. The origin of this software must not be misrepresented; you must not
//       claim that you wrote the original software. If you use this software in
//       a product, an acknowledgment in the product documentation would be
//       appreciated but is not required.
//
//    2. Altered source versions must be plainly marked as such, and must not be
//       misrepresented as being the original software.
//
//    3. This notice may not be removed or altered from any source distribution.


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "JOYPAD RAPID READ"
define VERSION = 0


architecture wdc65816-strict

include "../common.inc"

createCodeBlock(code,       0x808000, 0x80ffaf)

createRamBlock(zeropage,        0x00,     0xff)
createRamBlock(stack,       0x7e1f00, 0x7e1fff)


include "../reset_handler.inc"
include "../break_handler.inc"
include "../dma_forceblank.inc"

// This test does not use interrupts
constant NmiHandler = BreakHandler.ISR


// BG1 & BG2 use the same tilemap and tiles
constant VRAM_BG12_TILES_WADDR = 0x1000
constant VRAM_BG12_MAP_WADDR   = 0x0000


constant N_BITS = 12;
constant SPACING_BETWEEN_BITS = 12
constant TOTAL_WIDTH = (N_BITS - 1) * SPACING_BETWEEN_BITS + 2

constant BG1_X_OFFSET = -(256 - TOTAL_WIDTH) / 2
constant BG2_X_OFFSET = BG1_X_OFFSET - 4 * SPACING_BETWEEN_BITS


allocate(zpTmpByte, zeropage, 1)

// Offset between the BGxVOFS register and the data I want to display on the scanline.
allocate(vofsOffset, zeropage, 1)


// DB = 0x80
au()
iu()
code()
function Main {
    rep     #$30
    sep     #$20
a8()
i16()

    stz.w   NMITIMEN


    // Set PPU registers


    lda.b   #INIDISP.force | 0xf
    sta.w   INIDISP

    lda.b   #(VRAM_BG12_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG1SC
    sta.w   BG2SC

    lda.b   #((VRAM_BG12_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg1.shift) | ((VRAM_BG12_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg2.shift)
    sta.w   BG12NBA

    lda.b   #SETINI.overscan
    sta.w   SETINI

    lda.b   #TM.bg1 | TM.bg2
    sta.w   TM


    lda.b   #BG1_X_OFFSET
    sta.w   BG1HOFS
    lda.b   #BG1_X_OFFSET >> 16
    sta.w   BG1HOFS

    lda.b   #BG2_X_OFFSET
    sta.w   BG2HOFS
    lda.b   #BG2_X_OFFSET >> 16
    sta.w   BG2HOFS



    ldx.w   #VRAM_BG12_MAP_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg_Tilemap)


    ldx.w   #VRAM_BG12_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg_Tiles)

    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Palette)


    sep     #$30
a8()
i8()

    MainLoop:
        // Wait until VBlank
        -
            assert(HVBJOY.vBlank == 0x80)
            bit.w   HVBJOY
            bpl     -

        // Enable the display
        lda.b   #0x0f
        sta.w   INIDISP

        lda.b   #-1
        sta.b   vofsOffset

        // Wait until the start of scanline 0
        -
            assert(HVBJOY.vBlank == 0x80)
            bit.w   HVBJOY
            bmi     -


        ScanlineLoop:
            // Latch the joypad
            lda.b   #JOYSER0.latch
            sta.w   JOYSER0
            stz.w   JOYSER0


            variable _i = 0
            while _i < 7 {
                lda.w   JOYSER0
                lsr
                rol.b   zpTmpByte
                _i = _i + 1
            }
            lda.w   JOYSER0
            lsr
            lda.b   zpTmpByte
            rol
            clc
            adc.b   vofsOffset
            tay


            variable _i = 0
            while _i < 3 {
                lda.w   JOYSER0
                lsr
                rol.b   zpTmpByte
                _i = _i + 1
            }

            lda.w   JOYSER0
            lsr
            lda.b   zpTmpByte
            and.b   #0b111
            rol
            // carry clear
            adc.b   vofsOffset

            // Wait for H-Blank
            -
                assert(HVBJOY.hBlank == 0x40)
                bit.w   HVBJOY
                bvc     -

            sta.w   BG2VOFS
            stz.w   BG2VOFS

            sty.w   BG1VOFS
            stz.w   BG1VOFS

            dec.b   vofsOffset

            assert(HVBJOY.vBlank == 0x80)
            bit.w   HVBJOY
            bpl     ScanlineLoop

        jmp     MainLoop
}



namespace Resources {
    insert Bg_Tiles,       "../../gen/test-patterns/scanline-bit-pattern.2bpp"
    insert Bg_Tilemap,     "../../gen/test-patterns/scanline-bit-pattern.tilemap"

    Palette:
        dw  0, 0, ToPalette( 6,  6,  0), ToPalette(31, 31,  0)  // B (yellow)
        dw  0, 0, ToPalette( 0,  8,  0), ToPalette( 0, 24,  0)  // Y (green)
        dw  0, 0, ToPalette( 6,  0,  6), ToPalette(31,  0, 31)  // select
        dw  0, 0, ToPalette( 6,  0,  6), ToPalette(31,  0, 31)  // start
        dw  0, 0, ToPalette( 6,  6,  6), ToPalette(31, 31, 31)  // up
        dw  0, 0, ToPalette( 6,  6,  6), ToPalette(31, 31, 31)  // down
        dw  0, 0, ToPalette( 6,  6,  6), ToPalette(31, 31, 31)  // left
        dw  0, 0, ToPalette( 6,  6,  6), ToPalette(31, 31, 31)  // right

        // Shifting BG2 4 lines saves me 4 rol instructions
        dw  0, 0, 0, 0
        dw  0, 0, 0, 0
        dw  0, 0, 0, 0
        dw  0, 0, 0, 0

        dw  0, 0, ToPalette( 8,  0,  0), ToPalette(31,  0,  0)  // A (red)
        dw  0, 0, ToPalette( 0,  0,  8), ToPalette( 6,  6, 31)  // X (blue)
        dw  0, 0, ToPalette( 6,  4,  6), ToPalette(25, 20, 25)  // L
        dw  0, 0, ToPalette( 6,  4,  6), ToPalette(25, 20, 25)  // R

    constant Palette.size = pc() - Palette
    assert(Palette.size == 16 * 4 * 2)
}

finalizeMemory()

