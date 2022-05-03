// A demonstration of a 4bpp tile buffer with VMAIN remapping, writing two bytes at a time.
//
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define ROM_NAME = "VMAIN 4BPP NO REMAP W"


constant BITS_PER_PIXEL = 4


include "_vmain-tile-buffer-demo.inc"



// Set a pixel in the 4bpp VMAIN remapped tile buffer
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
constant _tmp         = zpTmp0
constant _tableIndex1 = zpTmp1


    // Clear high byte of index registers
    sep     #$10
i8()
    rep     #$30
a16()
i16()

    // bufferIndex (Y) = (yPos * BUFFER_WIDTH_PX / 8 * BITS_PER_PIXEL) | (xPos / 8 * BITS_PER_PIXEL)
    //             ... = (yPos << 7) | ((xPos & 0xf8) >> 1)

    assert(BUFFER_WIDTH_PX / 8 * BITS_PER_PIXEL == 0x100 >> 1)
    tya
    xba
    lsr
    sta.b   _tmp

    assert(8 / BITS_PER_PIXEL == 1 << 1)
    txa
    and.w   #0xf8
    lsr
    ora.b   _tmp

    tay


    // tableIndex0 = (((X & 7) << 2) | (pixelColour & 3)) * 2
    // tableIndex1 = (((X & 7) << 2) | ((pixelColour >> 2) & 3)) * 2
    sep     #$20
a8()
    // Set high byte of A to 0
    tdc

    txa
    and.b   #7
    asl
    asl
    sta.b   _tmp

    lda.b   pixelColour
    and.b   #3
    ora.b   _tmp
    asl
    tax


    lda.b   pixelColour
    lsr
    lsr
    and.b   #3
    ora.b   _tmp
    asl

    rep     #$30
a16()

    sta.b   _tableIndex1


    lda.w   tileBuffer + 0,y
    and.l   MaskTable,x
    ora.l   PlotTable,x
    sta.w   tileBuffer + 0,y


    ldx.b   _tableIndex1

    lda.w   tileBuffer + 2,y
    and.l   MaskTable,x
    ora.l   PlotTable,x
    sta.w   tileBuffer + 2,y


    sep     #$20
a8()

    rts
}



// Table of bits to set for each sub-x position and bit-pair.
//
// Index format: xxxpp0
//      xxx = xpos
//       pp = pixel value of bitplane pairs 0&1 or 3&4.
PlotTable:
variable _s = 0
while _s < 8 {
    variable _c = 0
    while _c < 4 {
        db  ((_c >> 0) & 1) << (7 - _s)
        db  ((_c >> 1) & 1) << (7 - _s)

        _c = _c + 1
    }

    _s = _s + 1
}


// Table of bits to set for each sub-x position and bit-pair.
//
// Index format is the same as `PlotTable`
MaskTable:
variable _s = 0
while _s < 8 {
    variable _c = 0
    while _c < 4 {
        db  ~(1 << (7 - _s))
        db  ~(1 << (7 - _s))

        _c = _c + 1
    }

    _s = _s + 1
}



// Transfer the tile buffer to VRAM
//
// REQUIRES: Force blank
// REQUIRES: 8 bit A, 16 bit Index, DP = 0, DB = 0x7e
a8()
i16()
code()
function TransferTileBufferToVram {

    // Transfer 4bpp tileBuffer to VRAM (with remapping)
    lda.b   #VMAIN.remap._9bits | VMAIN.increment.by1 | VMAIN.incrementMode.high
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


