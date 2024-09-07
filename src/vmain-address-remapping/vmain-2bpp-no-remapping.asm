// A demonstration of a 2bpp tile buffer with no VMAIN remapping.
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


define ROM_NAME = "VMAIN 2BPP NO REMAP"


constant BITS_PER_PIXEL = 2

constant TILE_SIZE_IN_BYTES = BITS_PER_PIXEL * 8


include "_vmain-tile-buffer-demo.inc"



// Write a single bit to the tile buffer
//
// ASSUMES: inputs are in bounds
//
// REQUIRES: 8 bit A, 16 bit Index, DP = 0, DB = 0x7e
//
// INPUT: Y = buffer index
// INPUT: X = index into `ShiftTable` and `InverseShiftTable`
// INPUT: zero flag = bit value
//
// PARAM: offset = the offset (within `tileBuffer`) for the current bit.
macro _DrawBit(evaluate offset) {
    assert8a()
    assert16i()

    beq     Zero_{#}
        // Draw a 1 bit
        // tileBuffer[Y + offset] |= ShiftTable[x]

        lda.w   tileBuffer + {offset},y
        ora.l   ShiftTable,x
        sta.w   tileBuffer + {offset},y

        bra     EndIf_{#}
    Zero_{#}:
        // Draw a 0 bit
        // tileBuffer[Y + offset] &= InverseShiftTable[x]

        lda.w   tileBuffer + {offset},y
        and.l   InverseShiftTable,x
        sta.w   tileBuffer + {offset},y
    EndIf_{#}:
}



// Set a pixel in the 2bpp tile buffer
//
// ASSUMES: inputs are in bounds
//
// REQUIRES: 8 bit A, 16 bit Index, DP = 0, DB = 0x7e
//
// INPUT: X = x-position (MUST BE < BUFFER_WIDTH_PX)
//        Y = y-position (MUST BE < BUFFER_HEIGHT_PX)
//        SetPixel.pixelColour = pixel colour (zeropage byte, unmodified by this function)
//
// KEEP: pixelColour
a8()
i16()
code()
function SetPixel {
constant _tmp   = zpTmp0


    // Clear high byte of index registers
    sep     #$10
i8()
    rep     #$30
a16()
i16()

    // bufferIndex (Y) = (yPos / 8 * TILEMAP_WIDTH * TILE_SIZE_IN_BYTES) | (xPos / 8 * TILE_SIZE_IN_BYTES) | ((yPos % 8) * 2)
    //             ... = ((yPos & 0xf8) << 6) | ((xPos & 0xf8) << 1) | ((yPos & 7) << 1)

    tya
    assert(TILEMAP_WIDTH * TILE_SIZE_IN_BYTES / 8 == 0x100 >> 2)
    and.w   #0xf8
    xba
    lsr
    lsr
    sta.b   _tmp

    assert(TILE_SIZE_IN_BYTES / 8 == 1 << 1)
    txa
    and.w   #0xf8
    asl
    ora.b   _tmp
    sta.b   _tmp

    tya
    and.w   #7
    asl
    ora.b   _tmp

    tay


    // bit shift index (X) = X & 7
    txa
    and.w   #7
    tax


    sep     #$20
a8()

    // Y = tileBuffer index
    // X = bit shift index

    lda.b   pixelColour
    bit.b   #1 << 0
    _DrawBit(0)

    lda.b   pixelColour
    bit.b   #1 << 1
    _DrawBit(1)

    rts
}


ShiftTable:
    db  1 << 7
    db  1 << 6
    db  1 << 5
    db  1 << 4
    db  1 << 3
    db  1 << 2
    db  1 << 1
    db  1 << 0


InverseShiftTable:
    db  ~(1 << 7)
    db  ~(1 << 6)
    db  ~(1 << 5)
    db  ~(1 << 4)
    db  ~(1 << 3)
    db  ~(1 << 2)
    db  ~(1 << 1)
    db  ~(1 << 0)



// Transfer the tile buffer to VRAM
//
// REQUIRES: Force blank
// REQUIRES: 8 bit A, 16 bit Index, DP = 0, DB = 0x7e
a8()
i16()
code()
function TransferTileBufferToVram {

    lda.b   #VMAIN.increment.by1 | VMAIN.incrementMode.high
    sta.w   VMAIN

    ldx.w   #VRAM_BG1_TILES_WADDR
    stx.w   VMADD


    lda.b   #DMAP.direction.toPpu | DMAP.transfer.two
    sta.w   DMAP0

    lda.b   #VMDATA
    sta.w   BBAD0

    ldx.w   #tileBuffer
    stx.w   A1T0
    lda.b   #tileBuffer >> 16
    sta.w   A1B0

    ldx.w   #tileBuffer.size
    stx.w   DAS0


    lda.b   #MDMAEN.dma0
    sta.w   MDMAEN

    rts
}



