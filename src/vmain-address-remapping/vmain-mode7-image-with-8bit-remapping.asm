// A demonstration of a Mode 7 tile buffer with 8 bit VMAIN remapping.
//
// Special thanks to nocash, for mentioning `VMAIN` remapping can be
// used with Mode 7 tiles in `fullsnes.txt`.
//
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


define ROM_NAME = "VMAIN MODE7 REMAP 8"

define MODE7

constant MODE7_MATRIX_A = 0x0080
constant MODE7_MATRIX_B = 0
constant MODE7_MATRIX_C = 0
constant MODE7_MATRIX_D = 0x0080


include "_vmain-tile-buffer-demo.inc"


assert(BUFFER_WIDTH_PX  == M7_TILEMAP_WIDTH)
assert(BUFFER_HEIGHT_PX <= M7_TILEMAP_HEIGHT)



// Set a pixel in the mode 7 tile buffer
//
// ASSUMES: inputs are in bounds
//
// REQUIRES: 8 bit A, 16 bit Index, DP = 0, DB = 0x7e
//
// INPUT: X = x-position (MUST BE < M7_TILEMAP_WIDTH)
//        Y = y-position (MUST BE < M7_TILEMAP_HEIGHT)
//        SetPixel.pixelColour = pixel colour (zeropage byte, unmodified by this function)
//
// KEEP: pixelColour
a8()
i16()
code()
function SetPixel {
constant _tmp   = zpTmp0


    rep     #$30
a16()
i16()
    // bufferIndex (Y) = ((yPos % 128) * BUFFER_WIDTH_PX) | (xPos % BUFFER_WIDTH_PX)
    //             ... = ((yPos & 0x7F) << 7) | (xPos & 0x7F)

    tya
    assert(BUFFER_WIDTH_PX == 0x100 >> 1)
    and.w   #0x7F
    xba
    lsr
    sta.b   _tmp

    txa
    and.w   #0x7F
    ora.b   _tmp
    sta.b   _tmp

    tay


    sep     #$20
a8()

    // Y = tileBuffer index

    lda.b   pixelColour
    sta.w   tileBuffer,y

    rts
}



// Generate the Mode7 tilemap in VRAM.
//
// REQUIRES: Force-blank
// REQUIRES: 8 bit A, 16 bit Index, DP = 0, DB access registers
a8()
i16()
code()
function GenerateTilemap {
constant _tmp   = zpTmp0

    // Access Mode 7 tilemap
    lda.b   #VMAIN.increment.by1 | VMAIN.incrementMode.low
    sta.w   VMAIN


    sep     #$30
i8()

    stz.b   _tmp

    ldy.b   #0
    YLoop:
        rep     #$20
    a16()
        // VMADD = y * M7_TILEMAP_WIDTH
        assert(M7_TILEMAP_WIDTH == 0x100 >> 1)
        tya
        xba
        lsr
        sta.w   VMADD

        sep     #$20
    a8()

        lda.b   _tmp

        ldx.b   #BUFFER_WIDTH_PX / 8

        XLoop:
            sta.w   VMDATAL

            clc
            adc.b   #4

            dex
            bne     XLoop


        lda.b   _tmp
        inc
        bit.b   #%00000100
        beq     +
            clc
            adc.b   #%00111100
        +
        sta.b   _tmp

        iny
        cpy.b   #BUFFER_HEIGHT_PX / 8
        bcc     YLoop

    rep     #$10
i16()
    rts
}



// Transfer the Mode 7 tile buffer to VRAM
//
// REQUIRES: Force blank
// REQUIRES: 8 bit A, 16 bit Index, DP = 0, DB = 0x7e
a8()
i16()
code()
function TransferTileBufferToVram {

    // Access Mode 7 tiles (with remapping)
    lda.b   #VMAIN.remap._8bits | VMAIN.increment.by32 | VMAIN.incrementMode.high
    sta.w   VMAIN


    lda.b   #DMAP.direction.toPpu | DMAP.transfer.one
    sta.w   DMAP0

    lda.b   #VMDATAH
    sta.w   BBAD0

    ldx.w   #tileBuffer
    stx.w   A1T0
    lda.b   #tileBuffer >> 16
    sta.w   A1B0


    ldx.w   #BUFFER_WIDTH_PX
    lda.b   #MDMAEN.dma0

    variable _y = 0
    while _y < BUFFER_HEIGHT_PX {
        ldy.w   #((_y & 0xe0) << 7) | (_y & 0x1f)
        sty.w   VMADD

        stx.w   DAS0

        sta.w   MDMAEN

        _y = _y + 1
    }

    rts
}


