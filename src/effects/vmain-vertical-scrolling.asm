// A vertically scrolling demo that displays a map that is more than 64 tiles tall.
//
// This demo is preformed on a background that is two tilemaps wide and one tilemap
// tall (64x32 tiles).
//
// Transferring a 64 tile tilemap row to a 64x32 or 64x64 tilemap in VRAM requires
// two separate DMA transfers since tilemap columns 31 and 32 are non-contiguous.
//
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "VMAIN VERTICAL SCROLLING"
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




// If this value is zero, the next row will be transferred to VRAM on the next VBlank interrupt.
// (byte flag)
allocate(transferTilemapRowOnZero, lowram, 1)

// The VRAM word address to transfer the map data.
//
// (VRAM word address)
allocate(tilemapRowVramWaddr, lowram, 2)

// Long address of the tilemap row to transfer to VRAM.
//
// (long address into `Map.Data`)
allocate(tilemapRowFarAddr, lowram, 3)



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
    sta.w   transferTilemapRowOnZero


    // Set `tilemapRowVramWaddr` to the last row in the tilemap.
    // On the next call to `QueueRowTransfer`, `tilemapRowVramWaddr`will be incremented to the first row of the tilemap.
    ldx.w   #VRAM_BG1_MAP_WADDR + TILEMAP_WORD_SIZE * 2
    stx.w   tilemapRowVramWaddr


    // Also set `tilemapRowVramWaddr` to the end of the map
    // (keep it in sync with `tilemapRowVramWaddr`)
    ldx.w   #Map.Data + Map.Data.size
    stx.w   tilemapRowFarAddr

    lda.b   #Map.Data >> 16
    sta.b   tilemapRowFarAddr + 2


    ldx.w   #0
    stx.w   cameraYpos

    rts
}



// Queue a transfer of the next tilemap row to VRAM on the next VBlank.
//
// REQUIRES: 8 bit A, 16 bit Index, DB access low-RAM, DP = 0
a8()
i16()
code()
function QueueRowTransfer {
    rep     #$30
a16()

    // Increment `tilemapRowVramWaddr`, wrapping as required
    lda.w   tilemapRowVramWaddr
    clc
    adc.w   #TILEMAP_WIDTH
    cmp.w   #VRAM_BG1_MAP_WADDR + TILEMAP_WIDTH * TILEMAP_HEIGHT
    bcc     +
        lda.w   #VRAM_BG1_MAP_WADDR
    +
    sta.w   tilemapRowVramWaddr


    // Advance pointer to the next row, wrapping as necessary
    // (leave bank unchanged)
    lda.w   tilemapRowFarAddr
    clc
    adc.w   #Map.MAP_WIDTH * 2
    cmp.w   #Map.Data + Map.Data.size
    bcc     +
        lda.w   #Map.Data
    +
    sta.w   tilemapRowFarAddr


    sep     #$20
a8()

    // Transfer the tilemap row to VRAM on the next VBlank
    stz.w   transferTilemapRowOnZero

    rts
}




// VBlank routine
//
// REQUIRES: 8 bit A, 16 bit Index, DB = registers, DP = 0
macro VBlank() {
    assert8a()
    assert16i()


    // Transfer tilemap row to VRAM if `transferTilemapRowOnZero` is
    // zero
    lda.w   transferTilemapRowOnZero
    bne     +
        // As BG1 is two tilemaps (64 tiles) wide, the row must be split in two
        // and uploaded to VRAM using two DMA transfers.
        //
        // The first will transfer 32 tilemap cells to `tilemapRowFarAddr`
        // The second will transfer 32 tilemap cells to `tilemapRowFarAddr + TILEMAP_WORD_SIZE`

        // Set VMAIN to normal word access
        lda.b   #VMAIN.increment.by1 | VMAIN.incrementMode.high
        sta.w   VMAIN


        // Setup DMA, transfer from `tilemapRowVramWaddr` to VRAM
        lda.b   #DMAP.direction.toPpu | DMAP.transfer.two
        sta.w   DMAP0

        lda.b   #VMDATA
        sta.w   BBAD0

        ldx.w   tilemapRowFarAddr
        stx.w   A1T0
        lda.w   tilemapRowFarAddr + 2
        sta.w   A1B0


        // Transfer the first half of the row to the first tilemap
        // (located at VRAM Word address `tilemapRowVramWaddr`)
        ldx.w   #TILEMAP_WIDTH * 2
        stx.w   DAS0

        ldx.w   tilemapRowVramWaddr
        stx.w   VMADD

        lda.b   #MDMAEN.dma0
        sta.w   MDMAEN


        // Transfer the second half of the row to the second tilemap
        // (located at VRAM Word address `tilemapRowVramWaddr + TILEMAP_WORD_SIZE`)
        //
        // No need to set the DMA control, destination or address registers.  They are already contain the correct values.
        ldx.w   #TILEMAP_WIDTH * 2
        stx.w   DAS0

        assert(TILEMAP_WORD_SIZE & 0xff == 0)
        lda.w   tilemapRowVramWaddr
        sta.w   VMADDL

        lda.w   tilemapRowVramWaddr + 1
        clc
        adc.b   #TILEMAP_WORD_SIZE >> 8
        sta.w   VMADDH

        lda.b   #MDMAEN.dma0
        sta.w   MDMAEN


        // A is non-zero
        sta.w   transferTilemapRowOnZero
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



    // Slowly draw the first 29 rows
    lda.b    #29
    InitialDrawLoop:
        pha
            jsr     QueueRowTransfer

            jsr     WaitFrame
            jsr     WaitFrame
            jsr     WaitFrame
            jsr     WaitFrame
        pla
        dec
        bne     InitialDrawLoop



    // Scroll BG1 vertically, drawing new columns when needed.
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

        and.b   #~7
        cmp.w   maskedCameraYpos
        beq     +
            sta.w   maskedCameraYpos

            jsr     QueueRowTransfer
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

}

