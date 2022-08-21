// A vertically scrolling demo that displays a map that is more than 64 tiles tall,
// updating two tilemap rows at a time.
//
// This demo is preformed on a background that is two tilemaps wide and one tilemap
// tall (64x32 tiles).
//
// Due to the non-contiguous nature of a 64 tile wide tilemap, the transfer to VRAM
// requires 4 DMA transfers.  This demo uses two DMA channels to transfer the
// buffer in two `MDMAEN` writes.  See the `VBlank()` macro for more details.
//
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "VMAIN VERTICAL SCROLLING 2R"
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


// VRAM Map
constant VRAM_BG1_MAP_WADDR   = 0x0000  // 64x32
constant VRAM_BG1_TILES_WADDR = 0x1000



// The size of a single tilemap (BG1 is 2 tilemaps wide)
constant TILEMAP_WIDTH = 32
constant TILEMAP_HEIGHT = 32
constant TILEMAP_WORD_SIZE = TILEMAP_WIDTH * TILEMAP_HEIGHT



// If this value is zero, the `tilemapRowBuffer` will be transferred to VRAM on the next VBlank interrupt.
// (byte flag)
allocate(transferTilemapRowBufferOnZero, lowram, 1)


constant N_ROWS_TO_TRANSFER = 2
constant ROW_BUFFER_WIDTH = 64

// A buffer holding two rows of tilemap cells.
//
// (64x2 grid of tilemap words)
allocate(tilemapRowBuffer, lowram, N_ROWS_TO_TRANSFER * ROW_BUFFER_WIDTH * 2)
constant tilemapRowBuffer.size = N_ROWS_TO_TRANSFER * ROW_BUFFER_WIDTH * 2


// The VRAM word address to transfer `tilemapRowBuffer` to.
//
// (VRAM word address)
allocate(tilemapRowVramWaddr, lowram, 2)


// The index within the map data for the last transferred row.
//
// NOTE: This index is incremented before the Map Data is read as
//       to keep it in sync with `tilemapRowVramWaddr`.
//
// (word index into `Map.Data`)
allocate(tilemapRowMapPos, lowram, 2)



// Shadow variable of the BG1 Horizontal Offset register
// (uint16)
allocate(bg1_hofs, lowram, 2)

// Shadow variable of the BG1 Vertical Offset register
// (uint16)
allocate(bg1_vofs, lowram, 2)



// Camera Y position.
//
// (uint16)
allocate(cameraYpos, lowram, 2)

// Used to determine if the next row is to be uploaded to VRAM
// (byte)
allocate(maskedCameraYpos, lowram, 1)



// Initialize the tilemap row transfer subsystem.
//
// REQUIRES: 8 bit A, 16 bit Index, DB = REGISTER, DP = 0
a8()
i16()
code()
function InitTilemapRowTransfers {
    lda.b   #1
    sta.w   transferTilemapRowBufferOnZero


    // Set `tilemapRowVramWaddr` to the last row in the tilemap.
    // On the next call to `QueueRowTransfer`, `tilemapRowVramWaddr`will be incremented to the first row of the tilemap.
    ldx.w   #VRAM_BG1_MAP_WADDR + TILEMAP_WORD_SIZE * 2
    stx.w   tilemapRowVramWaddr


    // Also set `tilemapRowMapPos` to the end of the map
    // (keep it in sync with `tilemapRowVramWaddr`)
    ldx.w   #Map.Data.size
    stx.w   tilemapRowMapPos


    ldx.w   #0
    stx.w   cameraYpos

    rts
}



// Populate the `tilemapRowBuffer` with the next two map rows
// and schedule a DMA transfer for the next VBlank.
//
// REQUIRES: 8 bit A, 16 bit Index, DB access low-RAM, DP = 0
a8()
i16()
code()
function DrawNextTwoRows {
    rep     #$30
a16()

    // Increment `tilemapRowVramWaddr`, wrapping as required
    assert(TILEMAP_HEIGHT % N_ROWS_TO_TRANSFER == 0)

    lda.w   tilemapRowVramWaddr
    clc
    adc.w   #TILEMAP_WIDTH * N_ROWS_TO_TRANSFER
    cmp.w   #VRAM_BG1_MAP_WADDR + TILEMAP_WIDTH * TILEMAP_HEIGHT
    bcc     +
        lda.w   #VRAM_BG1_MAP_WADDR
    +
    sta.w   tilemapRowVramWaddr


    // Advance index to the next row, wrapping as necessary
    lda.w   tilemapRowMapPos
    clc
    adc.w   #Map.MAP_WIDTH * N_ROWS_TO_TRANSFER * 2
    cmp.w   #Map.Data.size
    bcc     +
        lda.w   #0
    +
    sta.w   tilemapRowMapPos
    tax



    // Populate `tilemapRowBuffer` with 2 tilemap rows
    //
    // X = index into Map
    // Y = index into one row of `tilemapRowBuffer`
    ldy.w   #0
    Loop:
        assert(N_ROWS_TO_TRANSFER == 2)
        lda.l   Map.Data + 0 * Map.MAP_WIDTH * 2,x
        sta.w   tilemapRowBuffer + 0 * ROW_BUFFER_WIDTH * 2,y

        lda.l   Map.Data + 1 * Map.MAP_WIDTH * 2,x
        sta.w   tilemapRowBuffer + 1 * ROW_BUFFER_WIDTH * 2,y

        inx
        inx

        iny
        iny
        cpy.w   #ROW_BUFFER_WIDTH * 2
        bcc     Loop


    sep     #$20
a8()

    // Transfer `tilemapRowBuffer` to VRAM on the next VBlank
    stz.w   transferTilemapRowBufferOnZero

    rts
}




// VBlank routine
//
// Uses DMA channels 0 & 1
//
// REQUIRES: 8 bit A, 16 bit Index, DB = registers, DP = 0
macro VBlank() {
    assert8a()
    assert16i()


    // Transfer tilemapRowBuffer to VRAM if `transferTilemapRowBufferOnZero` is zero
    lda.w   transferTilemapRowBufferOnZero
    bne     +
        // Due to the discontiguous nature of a 64 tile wide tilemap the transfer of
        // `tilemapRowBuffer` (a 64x2 word grid) to VRAM requires 4 DMA transfers.
        //
        //   * tilemapRowBuffer[  0 -  63] to VRAM word address `tilemapRowVramWaddr`
        //   * tilemapRowBuffer[128 - 191] to VRAM word address `tilemapRowVramWaddr + 32`
        //   * tilemapRowBuffer[ 64 - 127] to VRAM word address `tilemapRowVramWaddr + 0x400`
        //   * tilemapRowBuffer[192 - 255] to VRAM word address `tilemapRowVramWaddr + 0x400 + 32`
        //
        //
        // By using two DMA channels, one for the top row and a second for the bottom row,
        // we can transfer the left and right quarters of the buffer to VRAM in a single
        // `MDMAEN` write.  After the transfer, the final two quarters will be transferred.
        //
        //   * tilemapRowBuffer[  0 -  63] and tilemapRowBuffer[128 - 191] to VRAM word address `tilemapRowVramWaddr`
        //   * tilemapRowBuffer[ 64 - 127] and tilemapRowBuffer[192 - 255] to VRAM word address `tilemapRowVramWaddr + 0x400`

        assert(tilemapRowBuffer.size == 2 * 64 * 2)

        // Set VMAIN to normal word access
        lda.b   #VMAIN.increment.by1 | VMAIN.incrementMode.high
        sta.w   VMAIN

        ldx.w   tilemapRowVramWaddr
        stx.w   VMADD


        // Setup Two DMA channels, transfer from `tilemapRowBuffer` and `tilemapRowBuffer + 128` to VRAM
        lda.b   #DMAP.direction.toPpu | DMAP.transfer.two
        sta.w   DMAP0
        sta.w   DMAP1

        lda.b   #VMDATA
        sta.w   BBAD0
        sta.w   BBAD1

        ldx.w   #tilemapRowBuffer
        stx.w   A1T0
        ldx.w   #tilemapRowBuffer + 128
        stx.w   A1T1

        lda.b   #tilemapRowBuffer >> 16
        sta.w   A1B0
        sta.w   A1B1


        // Transfer the first half of both rows to the first tilemap
        // (located at VRAM Word address `tilemapRowVramWaddr`)
        ldx.w   #TILEMAP_WIDTH * 2
        stx.w   DAS0
        stx.w   DAS1

        // Transfer two DMA channels at once
        lda.b   #MDMAEN.dma1 | MDMAEN.dma0
        sta.w   MDMAEN


        // Transfer the second half of both row to the second tilemap
        // (located at VRAM Word address `tilemapRowVramWaddr + TILEMAP_WORD_SIZE`)
        //
        // No need to set the DMA control, destination or address registers.  They are already contain the correct values.
        //
        // After the first transfer, the source address on DMA channel 0 is `tilemapRowBuffer + 64` and 
        // the source address on channel 1 is `tilemapRowBuffer + 128 + 64`.

        // X contains `TILEMAP_WIDTH * 2`
        stx.w   DAS0
        stx.w   DAS1


        // Set VRAM word Address to `tilemapRowVramWaddr + TILEMAP_WORD_SIZE`
        assert(TILEMAP_WORD_SIZE & 0xff == 0)
        lda.w   tilemapRowVramWaddr
        sta.w   VMADDL

        lda.w   tilemapRowVramWaddr + 1
        clc
        adc.b   #TILEMAP_WORD_SIZE >> 8
        sta.w   VMADDH


        // Transfer two DMA channels at once
        lda.b   #MDMAEN.dma1 | MDMAEN.dma0
        sta.w   MDMAEN


        // A is non-zero
        sta.w   transferTilemapRowBufferOnZero
    +


    // Transfer bg1 offset shadow variables to PPU
    lda.w   bg1_hofs
    sta.w   BG1HOFS
    lda.w   bg1_hofs + 1
    sta.w   BG1HOFS

    lda.w   bg1_vofs
    sta.w   BG1VOFS
    lda.w   bg1_vofs + 1
    sta.w   BG1VOFS
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


    // Initialise the tilemap row transfers
    jsr     InitTilemapRowTransfers


    // Offset BG1 so both the left and right tilemaps are onscreen
    ldx.w   #128
    stx.w   bg1_hofs

    ldx.w   #0
    stx.w   cameraYpos


    // Set PPU registers

    // Mode 0
    stz.w   BGMODE

    lda.b   #(VRAM_BG1_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s64x32
    sta.w   BG1SC

    lda.b   #(VRAM_BG1_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg1.shift
    sta.w   BG12NBA

    lda.b   #TM.bg1
    sta.w   TM


    // Transfer tiles and palette to VRAM
    ldx.w   #VRAM_BG1_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Tiles)


    // Transfer palette to CGRAM
    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Palette)


    EnableVblankInterrupts()


    jsr     WaitFrame

    // Enable screen, full brightness (still in VBlank)
    lda.b   #15
    sta.w   INIDISP



    // Slowly draw the first 15 pairs of rows
    lda.b    #15
    InitialDrawLoop:
        pha
            jsr     DrawNextTwoRows

            jsr     WaitFrame
            jsr     WaitFrame
            jsr     WaitFrame
            jsr     WaitFrame
            jsr     WaitFrame
        pla
        dec
        bne     InitialDrawLoop



    // Scroll BG1 vertically, drawing new rows as required
    MainLoop:
        rep     #$30
    a16()
        lda.w   cameraYpos
        clc
        adc.w   #1
        sta.w   cameraYpos

        // Must adjust the vertical offset by -1 to align the Background and Object layers.
        dec
        sta.w   bg1_vofs

        sep     #$20
    a8()

        assertPowerOfTwo(N_ROWS_TO_TRANSFER)
        and.b   #~((N_ROWS_TO_TRANSFER * 8) - 1)
        cmp.w   maskedCameraYpos
        beq     +
            sta.w   maskedCameraYpos

            jsr     DrawNextTwoRows
        +

        jsr     WaitFrame

        jmp     MainLoop
}



// Resources
// =========

namespace Resources {
Tiles:
// Blank tile
    fill    16, 0

// Tilled tile
    db  %11111111, %00000000
    db  %11111111, %00000000
    db  %11111111, %00000000
    db  %11111111, %00000000
    db  %11111111, %00000000
    db  %11111111, %00000000
    db  %11111111, %00000000
    db  %11111111, %00000000

constant Tiles.size = pc() - Tiles


Palette:
    dw  ToPalette( 0,  0 , 0)
    dw  ToPalette(22,   6, 6)
    dw  ToPalette( 0,  0 , 0)
    dw  ToPalette( 0,  0 , 0)

    dw  ToPalette( 0,  0 , 0)
    dw  ToPalette(11, 13, 28)
    dw  ToPalette( 0,  0 , 0)
    dw  ToPalette( 0,  0 , 0)

    dw  ToPalette( 0,  0 , 0)
    dw  ToPalette(27, 21, 12)
    dw  ToPalette( 0,  0 , 0)
    dw  ToPalette( 0,  0 , 0)

constant Palette.size = pc() - Palette
}



// The map to display
//
// (Grid of TileMap words)
namespace Map {

constant MAP_WIDTH  = 70
constant MAP_HEIGHT = 112


assert(MAP_WIDTH  > TILEMAP_WIDTH * 2)
assert(MAP_HEIGHT > TILEMAP_HEIGHT * 2)


constant _ = 0
constant H = 1 | (0 << Tilemap.palette.shift)
constant W = 1 | (1 << Tilemap.palette.shift)
constant T = 1 | (2 << Tilemap.palette.shift)

Data:

    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,H,H,H,H,_,_,_,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,H,H,H,H,_,_,_,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,H,H,H,H,_,_,_,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,H,H,H,H,_,_,_,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,H,H,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,H,H,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,H,H,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,W,W,W,W,W,W,W,W,W,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,W,W,W,W,W,W,W,W,W,W,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,W,W,W,W,W,W,W,W,W,W,W,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,W,W,W,W,W,W,W,W,W,W,W,W,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,W,W,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,W,W,W,W,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,W,W,W,W,W,W,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,W,W,W,W,W,W,W,W,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,W,W,W,W,W,W,W,W,W,W,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,W,W,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,T,T,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,W,W,W,W,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,T,T,T,T,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,W,W,W,W,W,W,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,H,H,H,H,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,W,W,W,W,W,W,W,W,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,W,W,W,W,W,W,W,W,W,W,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,W,W,W,W,W,W,W,W,W,W,W,W,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,_,_,_,_,W,W,W,W,W,W,W,W,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,_,_,_,_,W,W,W,W,W,W,W,W,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,W,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,W,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,W,W,W,W,W,_,_,_,_,_,_,_,_,W,W,W,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,W,W,W,W,W,_,_,_,_,_,_,_,_,W,W,W,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,W,W,W,W,W,W,W,W,W,W,_,_,_,_,_,W,W,W,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,W,W,W,W,W,W,W,_,_,_,_,_,_,_,_,W,W,W,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,W,W,W,W,W,W,W,W,W,_,_,_,_,_,_,_,_,W,W,W,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,W,W,W,W,W,W,W,W,W,_,_,_,_,_,_,_,_,W,W,W,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,T,T,_,_,_,_,_,_,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,T,T,T,T,_,_,_,_,_,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,H,H,H,H,H,H,H,H,_,_,_,W,_,_,_,W,W,W,W,W,W,W,W,W,W,W,W,W,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,W,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,W,W,W,_,_,_,W,W,W,_,_,_,_,_,_,_,_,W,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,W,_,_,_,W,_,_,_,_,_,_,_,_,_,_,W,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,W,_,_,_,W,_,_,_,_,_,_,W,W,W,W,W,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,W,_,_,_,W,_,_,_,_,_,_,_,_,_,_,W,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,W,W,W,_,_,_,_,W,_,_,_,W,_,_,_,_,_,_,_,_,_,_,W,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,W,_,_,_,W,W,W,W,W,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,W,_,_,_,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,W,_,_,_,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,W,W,W,W,W,_,_,_,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,W,W,_,_,_,W,W,_,_,_,_,W,W,_,_,_,W,W,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,W,W,_,_,_,W,W,_,_,_,_,W,W,_,_,_,W,W,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,T,T,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,T,T,T,T,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,W,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,_,_,W,W,W,W,W,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,H,H,_,_,_,H,H,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,H,H,_,_,_,H,H,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,H,H,_,_,_,H,H,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,H,H,H,H,_,_,_,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,H,H,H,H,_,_,_,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,H,H,H,H,_,_,_,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,H,H,H,H,H,H,_,_,_,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,

constant Data.size = pc() - Data

assert(Data.size == MAP_WIDTH * MAP_HEIGHT * 2)
assert(Data.size % (MAP_HEIGHT * N_ROWS_TO_TRANSFER) == 0)

}

