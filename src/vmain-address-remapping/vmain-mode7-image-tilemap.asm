// A demonstration of a simple fullscreen 128x112px chunky pixel image buffer
// created by storing the image data in the mode 7 tilemap.
//
// As the mode 7 tilemap is a 128x128px contiguous grid, there is no need
// for `VMAIN` address remapping and the whole image can be transferred
// to VRAM in a single DMA transfer.
//
// To turn the tilemap into pixels on the screen the Mode 7 tiles is filled
// with solid tiles for each of the 256 colours.
//
// To turn the tilemap into visible pixels, the Mode 7 tile data is filled with
// solid tiles representing each of the 256 colours.
//
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define ROM_NAME = "VMAIN MODE7 TM IMAGE"


define MODE7

define CUSTOM_MODE7_MATRIX

constant MODE7_MATRIX_A = 0x0400
constant MODE7_MATRIX_B = 0
constant MODE7_MATRIX_C = 0
constant MODE7_MATRIX_D = 0x0400


include "_vmain-tile-buffer-demo.inc"


assert(BUFFER_WIDTH_PX  == M7_TILEMAP_WIDTH)
assert(BUFFER_HEIGHT_PX <= M7_TILEMAP_HEIGHT)


constant imageBuffer = tileBuffer
constant imageBuffer.size = tileBuffer.size


// Set a pixel in the image buffer
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
    // bufferIndex (Y) = ((yPos % M7_TILEMAP_HEIGHT) * M7_TILEMAP_WIDTH) | (xPos % M7_TILEMAP_WIDTH)
    //             ... = ((yPos & 0x7F) << 7) | (xPos & 0x7F)


    tya
    assert(M7_TILEMAP_WIDTH == 0x100 >> 1)
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

    // Y = imageBuffer index

    lda.b   pixelColour
    sta.w   imageBuffer,y

    rts
}



// Generate the Mode 7 tile data in VRAM.
//
// REQUIRES: Force-blank
// REQUIRES: 8 bit A, 16 bit Index, DP = 0, DB access registers
//
// Uses DMA channel 0
a8()
i16()
code()
function GenerateTileData {
constant _tile = zpTmp0

    // Access Mode 7 tiles
    lda.b   #VMAIN.increment.by1 | VMAIN.incrementMode.high
    sta.w   VMAIN

    ldx.w   #0
    stx.w   VMADD


    // Prep DMA registers (fixed transfer to VMDATAH)

    lda.b   #DMAP.fixed | DMAP.direction.toPpu | DMAP.transfer.one
    sta.w   DMAP0

    lda.b   #VMDATAH
    sta.w   BBAD0

    ldx.w   #_tile
    stx.w   A1T0
    assert(_tile >> 16 == 0)
    stz.w   A1B0


    // for _tile = 0 to 255:
    //    Transfer TILE_SIZE_IN_BYTES copies of _tile to VRAM

    stz.b   _tile

    lda.b   #MDMAEN.dma0

    Loop:
        ldx.w   #TILE_SIZE_IN_BYTES
        stx.w   DAS0

        sta.w   MDMAEN

        inc.b   _tile
        bne     Loop

    rts
}



// Transfer the image buffer to the Mode 7 tilemap in VRAM.
//
// REQUIRES: Force blank
// REQUIRES: 8 bit A, 16 bit Index, DP = 0, DB = 0x7e
//
// Uses DMA channel 0
a8()
i16()
code()
function TransferImageBufferToVram {

    // Access Mode 7 tilemap
    lda.b   #VMAIN.increment.by1 | VMAIN.incrementMode.low
    sta.w   VMAIN

    ldx.w   #0
    stx.w   VMADD


    lda.b   #DMAP.direction.toPpu | DMAP.transfer.one
    sta.w   DMAP0

    lda.b   #VMDATAL
    sta.w   BBAD0

    ldx.w   #imageBuffer
    stx.w   A1T0
    lda.b   #imageBuffer >> 16
    sta.w   A1B0

    ldx.w   #imageBuffer.size
    stx.w   DAS0


    lda.b   #MDMAEN.dma0
    sta.w   MDMAEN

    rts
}



constant GenerateTilemap = GenerateTileData
constant TransferTileBufferToVram = TransferImageBufferToVram


