// A demonstration of a 1bpp tile buffer with VMAIN remapping.
//
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define ROM_NAME = "VMAIN 1BPP REMAPPING"


constant BITS_PER_PIXEL = 1


include "_vmain-tile-buffer-demo.inc"



// Set a pixel in the 1bpp VMAIN remapped tile buffer
//
// ASSUMES: inputs are in bounds
//
// REQUIRES: 8 bit A, 16 bit Index, DP = 0, DB = 0x7e
//
// INPUT: X = x-position (MUST BE < BUFFER_WIDTH_PX)
//        Y = y-position (MUST BE < BUFFER_HEIGHT_PX)
//        SetPixel.pixelColour = pixel colour (zeropage byte flag, unmodified by this function)
//
// KEEP: pixelColour
a8()
i16()
code()
function SetPixel {
constant _tmp   = zpTmp0


    // Clear the high byte of both index registers
    sep     #$10
i8()
    rep     #$30
a16()
i16()

    // bufferIndex (Y) = (yPos * BUFFER_WIDTH_PX / 8 * BITS_PER_PIXEL) | (xPos / 8)
    //             ... = (yPos << 5) | (xPos >> 3)

    assert(BUFFER_WIDTH_PX / 8 * BITS_PER_PIXEL == 0x100 >> 3)
    tya
    xba
    lsr
    lsr
    lsr
    sta.b   _tmp

    assert(8 == 1 << 3)
    txa
    lsr
    lsr
    lsr
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
    beq     Zero
        // Draw a 1 bit
        // tileBuffer[Y] = tileBuffer[Y] | ShiftTable[x]

        lda.w   tileBuffer,y
        ora.l   ShiftTable,x
        sta.w   tileBuffer,y

        bra     EndIf
    Zero:
        // Draw a 0 bit
        // tileBuffer[Y] = tileBuffer[Y] & InverseShiftTable[x]

        lda.w   tileBuffer,y
        and.l   InverseShiftTable,x
        sta.w   tileBuffer,y
    EndIf:

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

    // Transfer bitplane 0 to VRAM (with remapping)
    lda.b   #VMAIN.remap._8bits | VMAIN.increment.by1 | VMAIN.incrementMode.low
    sta.w   VMAIN

    ldx.w   #VRAM_BG1_TILES_WADDR
    stx.w   VMADD


    lda.b   #DMAP.direction.toPpu | DMAP.transfer.one
    sta.w   DMAP0

    lda.b   #VMDATAL
    sta.w   BBAD0

    ldx.w   #tileBuffer
    stx.w   A1T0
    lda.b   #tileBuffer >> 16
    sta.w   A1B0

    ldx.w   #tileBuffer.size
    stx.w   DAS0


    lda.b   #MDMAEN.dma0
    sta.w   MDMAEN



    // Fill bitplane 1 with zeros
    lda.b   #VMAIN.remap._8bits | VMAIN.increment.by1 | VMAIN.incrementMode.high
    sta.w   VMAIN

    ldx.w   #VRAM_BG1_TILES_WADDR
    stx.w   VMADD


    lda.b   #DMAP.direction.toPpu | DMAP.fixed | DMAP.transfer.one
    sta.w   DMAP0

    lda.b   #VMDATAH
    sta.w   BBAD0

    ldx.w   #Resources.ZeroByte
    stx.w   A1T0
    lda.b   #Resources.ZeroByte >> 16
    sta.w   A1B0

    ldx.w   #tileBuffer.size
    stx.w   DAS0


    lda.b   #MDMAEN.dma0
    sta.w   MDMAEN

    rts
}



namespace Resources {

ZeroByte:
    db  0
}


