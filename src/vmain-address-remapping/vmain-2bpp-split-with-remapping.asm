// A demonstration of a 2bpp split-bitplane tile buffer with VMAIN remapping.
//
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define ROM_NAME = "VMAIN 2BPP SP REMAP"


constant BITS_PER_PIXEL = 2


include "_vmain-tile-buffer-demo.inc"


// Split the tileBuffer in two
constant tileBuffer_bitplane0.size = tileBuffer.size / 2
constant tileBuffer_bitplane1.size = tileBuffer.size / 2

constant tileBuffer_bitplane0 = tileBuffer
constant tileBuffer_bitplane1 = tileBuffer + tileBuffer.size / 2


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
// PARAM: buffer = the buffer to write to
macro _DrawBit(buffer) {
    assert8a()
    assert16i()

    beq     Zero_{#}
        // Draw a 1 bit
        // buffer[Y] |= ShiftTable[x]

        lda.w   {buffer},y
        ora.l   ShiftTable,x
        sta.w   {buffer},y

        bra     EndIf_{#}

    Zero_{#}:
        // Draw a 0 bit
        // buffer[Y] &= InverseShiftTable[x]

        lda.w   {buffer},y
        and.l   InverseShiftTable,x
        sta.w   {buffer},y
    EndIf_{#}:
}



// Set a pixel in the 2bpp split-bitplane VMAIN remapped tile buffer
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


    // Clear the high byte of both index registers
    sep     #$10
i8()
    rep     #$30
a16()
i16()

    // bufferIndex (Y) = (yPos * BUFFER_WIDTH_PX / 8) | (xPos / 8)
    //             ... = (yPos << 5) | (xPos >> 3)

    assert(BUFFER_WIDTH_PX / 8 == 0x100 >> 3)
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

    // Y = buffer index
    // X = bit shift index

    lda.b   pixelColour
    bit.b   #1 << 0
    _DrawBit(tileBuffer_bitplane0)

    lda.b   pixelColour
    bit.b   #1 << 1
    _DrawBit(tileBuffer_bitplane1)

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

    // Transfer bitplane 0
    lda.b   #VMAIN.remap._8bits | VMAIN.increment.by1 | VMAIN.incrementMode.low
    sta.w   VMAIN

    ldx.w   #VRAM_BG1_TILES_WADDR
    stx.w   VMADD


    lda.b   #DMAP.direction.toPpu | DMAP.transfer.one
    sta.w   DMAP0

    lda.b   #VMDATAL
    sta.w   BBAD0

    ldx.w   #tileBuffer_bitplane0
    stx.w   A1T0
    lda.b   #tileBuffer_bitplane0 >> 16
    sta.w   A1B0

    ldx.w   #tileBuffer_bitplane0.size
    stx.w   DAS0


    lda.b   #MDMAEN.dma0
    sta.w   MDMAEN



    // Transfer bitplane 1
    lda.b   #VMAIN.remap._8bits | VMAIN.increment.by1 | VMAIN.incrementMode.high
    sta.w   VMAIN

    ldx.w   #VRAM_BG1_TILES_WADDR
    stx.w   VMADD

    // DMAP0 is at the correct value

    lda.b   #VMDATAH
    sta.w   BBAD0

    // A1T0 & A1BO point to the correct address
    assert(tileBuffer_bitplane0 + tileBuffer_bitplane0.size == tileBuffer_bitplane1)

    ldx.w   #tileBuffer_bitplane1.size
    stx.w   DAS0


    lda.b   #MDMAEN.dma0
    sta.w   MDMAEN


    rts
}


