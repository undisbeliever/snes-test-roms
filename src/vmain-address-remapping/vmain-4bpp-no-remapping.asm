// A demonstration of a 4bpp tile buffer with no VMAIN remapping.
//
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define ROM_NAME = "VMAIN 4BPP NO REMAP"


constant BITS_PER_PIXEL = 4

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



// Set a pixel in the 4bpp no remapping tile buffer
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
    //             ... = ((yPos & 0xf8) << 7) | ((xPos & 0xf8) << 2) | ((yPos & 7) << 1)

    tya
    assert(TILEMAP_WIDTH * TILE_SIZE_IN_BYTES / 8 == 0x100 >> 1)
    and.w   #0xf8
    xba
    lsr
    sta.b   _tmp

    assert(TILE_SIZE_IN_BYTES / 8 == 1 << 2)
    txa
    and.w   #0xf8
    asl
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

    lda.b   pixelColour
    bit.b   #1 << 2
    _DrawBit(16)

    lda.b   pixelColour
    bit.b   #1 << 3
    _DrawBit(17)

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


