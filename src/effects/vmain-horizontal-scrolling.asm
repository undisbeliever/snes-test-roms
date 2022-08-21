// A horizontally scrolling demo that displays a map that is more than 64 tiles long.
//
// This demo uses the VMAIN register (in "increment by 32" mode) to transfer an
// entire column of tilemap cells to VRAM in a single DMA transfer.
//
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "VMAIN HORIZONTAL SCROLLING"
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



// A buffer holding a column of tilemap cells.
//
// (32x tilemap word entries)
allocate(columnBuffer, lowram, TILEMAP_HEIGHT * 2)
constant columnBuffer.size = TILEMAP_HEIGHT * 2


// If this value is zero, the `columnBuffer` will be transferred to VRAM on the next VBlank.
// (byte flag)
allocate(transferColumnBufferOnZero, lowram, 1)


// The VRAM word address to transfer the `columnBuffer` to.
//
// (VRAM word address)
allocate(columnBufferVramWaddr, lowram, 2)


// The index within the map data for the last transferred column.
//
// NOTE: This index is incremented before the Map Data is read as
//       to keep it in sync with `columnBufferVramWaddr`.
//
// (Word Index into `Map`)
allocate(columnBufferMapPos, lowram, 2)



// Shadow variable of the BG1 Horizontal Offset register
// (uint16)
allocate(bg1_hofs, lowram, 2)


// Used to determine if the next column is to be uploaded to VRAM
// (byte)
allocate(maskedHofsPreviousColumnDraw, lowram, 1)



// Initialise the column buffer
//
// REQUIRES: 8 bit A, 16 bit Index, DB = REGISTER, DP = 0
a8()
i16()
code()
function InitColumnBuffer {
    lda.b   #1
    sta.w   transferColumnBufferOnZero

    // Set `vramWaddr` to the last column in the second tilemap.
    // On the next call to `DrawNextColumn`, `vramWaddr` will be incremented to the first column of the first tilemap.
    ldx.w   #VRAM_BG1_MAP_WADDR + TILEMAP_WORD_SIZE + (TILEMAP_WIDTH - 1)
    stx.w   columnBufferVramWaddr

    // Also set `columnBufferMapPos` to the end of the map
    // (keeping it in sync with `columnBufferVramWaddr`)
    ldx.w   #(Map.MAP_WIDTH - 1) * 2
    stx.w   columnBufferMapPos


    rts
}



// Populate the `columnBuffer` with the next map column
// and schedule a DMA transfer for the next VBlank.
//
// REQUIRES: 8 bit A, 16 bit Index, DB access low-RAM, DP = 0
a8()
i16()
code()
function DrawNextColumn {
    rep     #$30
a16()

    // Increment `columnBufferVramWaddr`, advancing to the next tilemap as required
    lda.w   columnBufferVramWaddr
    inc
    cmp.w   #VRAM_BG1_MAP_WADDR + TILEMAP_WORD_SIZE + TILEMAP_WIDTH
    bcc     +
        // Past the end of the second tilemap, go back to the start of the first tilemap
        lda.w   #VRAM_BG1_MAP_WADDR
        bra     ++
    +
    cmp.w   #VRAM_BG1_MAP_WADDR + TILEMAP_WIDTH
    bne     +
        // Past the end of the first tilemap, go to the second tilemap
        lda.w   #VRAM_BG1_MAP_WADDR + TILEMAP_WORD_SIZE
    +
    sta.w   columnBufferVramWaddr


    // Increment `columnBufferMapPos` with wrapping
    lda.w   columnBufferMapPos
    inc
    inc
    cmp.w   #Map.MAP_WIDTH * 2
    bcc     +
        lda.w   #0
    +
    sta.w   columnBufferMapPos

    tax


    // Populate the `columnBuffer` with a column of Map cells
    //
    // X = index into Map
    // Y = index into columnBuffer
    ldy.w   #0
    Loop:
        lda.l   Map.Data,x
        sta.w   columnBuffer,y

        txa
        clc
        adc.w   #Map.MAP_WIDTH * 2
        tax

        iny
        iny
        cpy.w   #columnBuffer.size
        bcc     Loop


    sep     #$20
a8()

    // Transfer the `columnBuffer` to VRAM on the next VBlank
    stz.w   transferColumnBufferOnZero

    rts
}




// VBlank routine
//
// REQUIRES: 8 bit A, 16 bit Index, DB = registers, DP = 0
macro VBlank() {
    assert8a()
    assert16i()

    // Transfer `columnBuffer` to VRAM if `transferColumnBufferOnZero` is zero.
    lda.w   transferColumnBufferOnZero
    bne     +
        // Transfer one tilemap column to VRAM
        lda.b   #VMAIN.increment.by32 | VMAIN.incrementMode.high
        sta.w   VMAIN


        ldx.w   columnBufferVramWaddr
        stx.w   VMADD


        lda.b   #DMAP.direction.toPpu | DMAP.transfer.two
        sta.w   DMAP0

        lda.b   #VMDATA
        sta.w   BBAD0

        ldx.w   #columnBuffer
        stx.w   A1T0
        lda.b   #columnBuffer >> 16
        sta.w   A1B0

        ldx.w   #columnBuffer.size
        stx.w   DAS0

        lda.b   #MDMAEN.dma0
        sta.w   MDMAEN


        // A is non-zero
        sta.w   transferColumnBufferOnZero
    +


    lda.w   bg1_hofs
    sta.w   BG1HOFS
    lda.w   bg1_hofs + 1
    sta.w   BG1HOFS
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


    // Initialise column buffer
    jsr     InitColumnBuffer


    // Set PPU registers

    // Mode 0
    stz.w   BGMODE

    lda.b   #(VRAM_BG1_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s64x32
    sta.w   BG1SC

    lda.b   #(VRAM_BG1_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg1.shift
    sta.w   BG12NBA

    lda.b   #TM.bg1
    sta.w   TM


    // Set BG1 Vertical Offset to -1.
    lda.b   #0xff
    sta.w   BG1VOFS
    sta.w   BG1VOFS


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



    // Slowly draw the first 32 columns
    lda.b    #TILEMAP_WIDTH + 2
    InitialDrawLoop:
        pha
            jsr     DrawNextColumn

            jsr     WaitFrame
            jsr     WaitFrame
        pla
        dec
        bne     InitialDrawLoop



    // Scroll BG1 horizontally, drawing new columns when needed.
    MainLoop:
        ldx.w   bg1_hofs
        inx
        inx
        inx
        stx.w   bg1_hofs

        txa
        and.b   #~7
        cmp.w   maskedHofsPreviousColumnDraw
        beq     +
            sta.w   maskedHofsPreviousColumnDraw

            jsr     DrawNextColumn
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

constant Palette.size = pc() - Palette
}



// The map to display
//
// (Grid of TileMap words)
namespace Map {

constant MAP_WIDTH  = 164
constant MAP_HEIGHT = 32


constant _ = 0
constant H = 1 | (0 << Tilemap.palette.shift)
constant W = 1 | (1 << Tilemap.palette.shift)


Data:
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,H,H,H,H,H,H,H,H,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,H,H,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,_,_,W,W,W,W,_,_,_,_,_,W,W,W,W,W,W,_,_,_,_,_,_,W,W,_,_,_,_,_,_,_,_,W,W,W,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,H,H,H,H,H,H,H,H,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,H,H,H,H,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,_,W,W,W,W,W,W,_,_,_,_,W,W,W,W,W,W,W,_,_,_,_,_,W,W,_,_,_,_,_,_,_,_,W,W,W,W,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,H,H,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,H,_,_,H,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,W,W,W,_,_,W,W,W,_,_,_,W,W,_,_,_,W,W,W,_,_,_,_,W,W,_,_,_,_,_,_,_,_,W,W,_,_,W,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,H,H,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,W,W,_,_,_,_,W,W,_,_,_,W,W,_,_,_,_,W,W,W,_,_,_,W,W,_,_,_,_,_,_,_,_,W,W,_,_,_,W,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,H,H,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,W,W,_,_,_,_,_,W,W,_,_,_,W,W,_,_,_,_,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,H,H,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,W,W,_,_,_,_,_,W,W,_,_,_,W,W,_,_,_,_,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,H,H,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,_,W,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,W,W,_,_,_,_,_,W,W,_,_,_,W,W,_,_,_,_,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,H,H,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,_,W,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,W,W,_,_,_,_,W,W,W,_,_,_,W,W,_,_,_,_,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,H,H,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,W,_,_,_,W,W,_,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,W,W,_,_,_,W,W,W,_,_,_,_,W,W,_,_,_,_,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,H,H,H,H,H,H,H,H,_,_,_,H,H,H,H,H,H,H,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,W,W,W,_,_,W,W,_,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,W,W,W,W,W,W,W,_,_,_,_,_,W,W,_,_,_,_,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,H,H,H,H,H,H,H,H,_,_,_,H,H,H,H,H,H,H,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,W,W,W,_,_,W,W,_,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,W,W,W,W,W,_,_,_,_,_,_,_,W,W,_,_,_,_,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,H,H,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,W,W,W,_,_,W,W,_,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,W,W,_,W,W,_,_,_,_,_,_,_,W,W,_,_,_,_,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,H,H,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,W,W,W,W,W,W,W,_,_,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,W,W,_,_,W,W,_,_,_,_,_,_,W,W,_,_,_,_,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,H,H,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,W,W,W,W,W,W,W,_,_,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,W,W,_,_,W,W,_,_,_,_,_,_,W,W,_,_,_,_,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,H,H,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,W,W,_,W,W,W,W,_,_,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,W,W,_,_,_,W,W,_,_,_,_,_,W,W,_,_,_,_,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,H,H,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,W,W,_,W,W,W,W,_,_,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,W,W,_,_,_,W,W,_,_,_,_,_,W,W,_,_,_,_,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,H,H,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,W,W,_,_,_,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,W,W,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,_,_,_,_,_,W,W,_,_,_,W,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,H,H,_,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,_,_,_,_,_,_,_,_,H,H,H,_,_,H,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,W,W,_,_,_,_,_,_,_,W,W,W,_,_,W,W,W,_,_,_,W,W,_,_,_,_,W,W,_,_,_,_,W,W,_,_,_,_,_,_,_,_,W,W,_,_,W,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,H,H,H,H,H,H,H,H,_,_,_,H,H,H,H,H,H,H,_,_,_,H,H,H,H,H,H,H,_,_,_,_,H,H,H,H,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,W,W,_,_,_,_,_,_,_,_,W,W,W,W,W,W,_,_,_,_,W,W,_,_,_,_,_,W,W,_,_,_,W,W,W,W,W,W,W,_,_,_,W,W,W,W,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,H,H,_,_,_,_,H,H,_,_,_,H,H,H,H,H,H,H,H,_,_,_,H,H,H,H,H,H,H,_,_,_,H,H,H,H,H,H,H,_,_,_,_,_,H,H,H,H,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,W,W,_,_,_,W,W,_,_,_,_,_,_,_,_,_,W,W,W,W,_,_,_,_,_,W,W,_,_,_,_,_,W,W,_,_,_,W,W,W,W,W,W,W,_,_,_,W,W,W,W,W,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,

    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
    dw  _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,
constant Data.size = pc() - Data

assert(Data.size == MAP_WIDTH * MAP_HEIGHT * 2)

}

