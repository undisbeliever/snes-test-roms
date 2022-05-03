// A demonstration of a Mode 7 tile buffer with no VMAIN remapping.
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define ROM_NAME = "VMAIN MODE7 NO REMAP"


define MODE7

constant MODE7_MATRIX_A = 0x0080
constant MODE7_MATRIX_B = 0
constant MODE7_MATRIX_C = 0
constant MODE7_MATRIX_D = 0x0080


include "_vmain-tile-buffer-demo.inc"



// Set a pixel in the mode 7 tile buffer
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


    rep     #$30
a16()
i16()
    // bufferIndex (Y) = (yPos / 8 * BUFFER_WIDTH_PX / 8 * TILE_SIZE_IN_BYTES) | (xPos / 8 * TILE_SIZE_IN_BYTES) | ((yPos % 8) * 8) | (xPos / 8)
    //             ... = ((yPos & 0x78) << 8) | ((xPos & 0x78) << 3) | ((yPos & 7) << 3) | (xPos & 7)


    tya
    assert(BUFFER_WIDTH_PX / 8 * TILE_SIZE_IN_BYTES / 8 == 0x100 >> 1)
    and.w   #0x78
    xba
    lsr
    sta.b   _tmp

    assert(TILE_SIZE_IN_BYTES / 8 == 1 << 3)
    txa
    and.w   #0x78
    asl
    asl
    asl
    ora.b   _tmp
    sta.b   _tmp

    assert(8 == 1 << 3)
    tya
    and.w   #7
    asl
    asl
    asl
    ora.b   _tmp
    sta.b   _tmp

    txa
    and.w   #7
    ora.b   _tmp

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

    lda.b   #0

    ldy.b   #0
    YLoop:
        sta.b   _tmp

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
            inc
            dex
            bne     XLoop

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

    // Access Mode 7 tiles
    lda.b   #VMAIN.increment.by1 | VMAIN.incrementMode.high
    sta.w   VMAIN

    ldx.w   #0
    stx.w   VMADD


    lda.b   #DMAP.direction.toPpu | DMAP.transfer.one
    sta.w   DMAP0

    lda.b   #VMDATAH
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


