// A simple demo that uses VMAIN to draw an entire Mode 7 tilemap row
// in a single DMA transfer.
//
// SPDX-FileCopyrightText: © 2022 Marcus Rowe <undisbeliever@gmail.com>
// SPDX-License-Identifier: Zlib
//
// Copyright © 2022 Marcus Rowe <undisbeliever@gmail.com>
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
define ROM_NAME = "MODE7 TILEMAP ROWS"
define VERSION = 1


architecture wdc65816-strict


include "../common.inc"


createCodeBlock(code,       0x808000, 0x80ffaf)

createRamBlock(lowram,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)
createRamBlock(wram7e,      0x7e2000, 0x7effff)


include "../reset_handler.inc"
include "../break_handler.inc"
include "../dma_forceblank.inc"



constant MODE7_TILEMAP_WIDTH = 128
constant MODE7_TILEMAP_HEIGHT = 128


constant ROWS_TO_TRANSFER = 28

assert(ROWS_TO_TRANSFER < MODE7_TILEMAP_WIDTH)


constant MODE7_MATRIX_A = 0x0100
constant MODE7_MATRIX_B = 0
constant MODE7_MATRIX_C = 0
constant MODE7_MATRIX_D = 0x0100



// If this variable is zero, draw the next row on the next VBlank
//
// (byte flag)
allocate(transferRowOnZero, lowram, 1)


// VRAM word address of the next mode-7 row to transfer.
//
// (VRAM word address)
allocate(rowVramWaddr, lowram, 2)


// The tileId of the row to draw.
//
// (byte)
allocate(rowTile, lowram, 1)



// VBlank routine
//
// REQUIRES: 8 bit A, 16 bit Index, DB = registers, DP = 0
macro VBlank() {
    assert8a()
    assert16i()


    lda.w   transferRowOnZero
    bne     NoTransfer

        // Transfer one MODE7 tilemap row to VRAM
        lda.b   #VMAIN.incrementMode.low | VMAIN.increment.by1
        sta.w   VMAIN


        ldx.w   rowVramWaddr
        stx.w   VMADD


        // Transfer `MODE7_TILEMAP_HEIGHT` copies of the `rowTile` byte to the mode 7 tilemap
        lda.b   #DMAP.direction.toPpu | DMAP.transfer.one | DMAP.fixed
        sta.w   DMAP0

        lda.b   #VMDATAL
        sta.w   BBAD0

        ldx.w   #rowTile
        stx.w   A1T0
        lda.b   #rowTile >> 16
        sta.w   A1B0

        ldx.w   #MODE7_TILEMAP_WIDTH
        stx.w   DAS0

        lda.b   #MDMAEN.dma0
        sta.w   MDMAEN

        // A is non-zero
        sta.w   transferRowOnZero

    NoTransfer:
}

include "../vblank_interrupts.inc"



au()
iu()
code()
function Main {
    sei

    rep     #$30
    sep     #$20
a8()
i16()
    phk
    plb
// DB = 0x80


    // Force blank
    lda.b   #INIDISP.force | 0xf
    sta.w   INIDISP



    // Setup variables
    ldx.w   #0
    stx.w   rowVramWaddr

    lda.b   #1
    sta.w   rowTile

    stz.w   transferRowOnZero



    // Setup PPU registers

    // Mode 7
    lda.b   #BGMODE.mode7
    sta.w   BGMODE

    stz.w   M7SEL


    // Initialize Mode 7 matrix
    lda.b   #MODE7_MATRIX_A
    sta.w   M7A
    lda.b   #MODE7_MATRIX_A >> 8
    sta.w   M7A
    lda.b   #MODE7_MATRIX_B
    sta.w   M7B
    lda.b   #MODE7_MATRIX_B >> 8
    sta.w   M7B
    lda.b   #MODE7_MATRIX_C
    sta.w   M7C
    lda.b   #MODE7_MATRIX_C >> 8
    sta.w   M7C
    lda.b   #MODE7_MATRIX_D
    sta.w   M7D
    lda.b   #MODE7_MATRIX_D >> 8
    sta.w   M7D

    stz.w   M7X
    stz.w   M7X
    stz.w   M7Y
    stz.w   M7Y


    stz.w   BG1HOFS
    stz.w   BG1HOFS

    lda.b   #-1
    sta.w   BG1VOFS
    sta.w   BG1VOFS


    // Enable BG1
    lda.b   #TM.bg1
    sta.w   TM


    // Clear Mode 7 Tilemap
    ldx.w   #0
    ldy.w   #MODE7_TILEMAP_WIDTH * MODE7_TILEMAP_WIDTH
    jsr     Dma.ForceBlank.ClearVramL


    // Transfer tiles and palette to VRAM
    ldx.w   #0
    stx.w   VMADD
    Dma.ForceBlank.ToVramH(Resources.Mode7Tiles)


    // Transfer palette to CGRAM
    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Palette)


    EnableVblankInterrupts()

    jsr     WaitFrame

    // Enable screen, full brightness (still in VBlank)
    lda.b   #15
    sta.w   INIDISP



    MainLoop:
        jsr     WaitFrame
        jsr     WaitFrame
        jsr     WaitFrame
        jsr     WaitFrame
        jsr     WaitFrame
        jsr     WaitFrame
        jsr     WaitFrame
        jsr     WaitFrame


        // Advance to the next row
        rep     #$30
    a16()
        lda.w   rowVramWaddr
        clc
        adc.w   #MODE7_TILEMAP_WIDTH
        cmp.w   #MODE7_TILEMAP_WIDTH * ROWS_TO_TRANSFER
        bcc     +
            lda.w   #0
        +
        sta.w   rowVramWaddr

        sep     #$20
    a8()
        // carry set if `rowVramWaddr` has been reset
        bcc     ++
            // `rowVramWaddr` has been reset, draw a different tile
            lda.w   rowTile
            inc
            cmp.b   #Resources.N_TILES
            bcc     +
                lda.b   #0
            +
            sta.w   rowTile
        +

        stz.w   transferRowOnZero


        jmp     MainLoop
}



// Resources
// =========

namespace Resources {


Palette:
    dw  ToPalette( 0,  0 ,  0)
    dw  ToPalette(31, 31,  31)
    dw  ToPalette(31,  0 ,  0)
    dw  ToPalette( 0, 31 ,  0)
    dw  ToPalette( 0,  0 , 31)

constant Palette.size = pc() - Palette


constant N_TILES = Palette.size / 2



Mode7Tiles:
    variable _i = 0
    while _i < N_TILES {
        fill 64, _i

        _i = _i + 1
    }
constant Mode7Tiles.size = pc() - Mode7Tiles

assert(Mode7Tiles.size == 8 * 8 * N_TILES)

}


