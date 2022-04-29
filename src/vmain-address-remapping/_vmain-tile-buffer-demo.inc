// Common code for the VMAIN address remapping test roms.
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define VERSION = 1


architecture wdc65816-strict


include "../common.inc"


createCodeBlock(code,       0x808000, 0x80ffaf)

createRamBlock(zeropage,    0x000000, 0x0000ff)
createRamBlock(shadow,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)
createRamBlock(wram7e,      0x7e2000, 0x7effff)


include "../reset_handler.inc"
include "../dma_forceblank.inc"


// VRAM Map
constant VRAM_BG1_TILES_WADDR = 0x0000
constant VRAM_BG1_MAP_WADDR   = 0x7c00  // 32x32



constant BUFFER_WIDTH_PX = 256
constant BUFFER_HEIGHT_PX = 224

constant BUFFER_SIZE = BUFFER_WIDTH_PX * BUFFER_HEIGHT_PX * BITS_PER_PIXEL / 8

assert(BUFFER_WIDTH_PX % 8 == 0)
assert(BUFFER_HEIGHT_PX % 8 == 0)


// The size of a single tilemap
constant TILEMAP_WIDTH = 32
constant TILEMAP_HEIGHT = 32


// The size of the display
constant DISPLAY_WIDTH = 256
constant DISPLAY_HEIGHT = 224



// Temporary zero-page word variables
// (word)
allocate(zpTmp0, zeropage, 2)
allocate(zpTmp1, zeropage, 2)
allocate(zpTmp2, zeropage, 2)
allocate(zpTmp3, zeropage, 2)



// Tile buffer
allocate(tileBuffer, wram7e, BUFFER_SIZE)
constant tileBuffer.size = BUFFER_SIZE



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


    // Set PPU registers

    // Set BGMODE
    if BITS_PER_PIXEL == 1 || BITS_PER_PIXEL == 2 {
        lda.b   #BGMODE.mode0
    } else if BITS_PER_PIXEL == 4 {
        lda.b   #BGMODE.mode1
    } else if BITS_PER_PIXEL == 8 {
        lda.b   #BGMODE.mode3
    } else {
        error "Unknown BITS_PER_PIXEL"
    }
    sta.w   BGMODE


    lda.b   #(VRAM_BG1_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG1SC

    lda.b   #(VRAM_BG1_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg1.shift
    sta.w   BG12NBA

    lda.b   #TM.bg1
    sta.w   TM



    lda.b   #0x7e
    pha
    plb
// DB = 0x7e
        jsr     ClearTileBuffer
        jsr     DrawImage
    phk
    plb
// DB = 0x80



    // Transfer data to PPU
    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Palette)

    jsr     GenerateTilemap

    jsr     TransferTileBufferToVram



    // Wait until VBlank
    lda.b   #NMITIMEN.vBlank
    sta.w   NMITIMEN
    wai

    // Enable screen, full brightness
    lda.b   #15
    sta.w   INIDISP


    MainLoop:
        wai
        bra     MainLoop
}



// Generate the BG1 tilemap in VRAM.
//
// REQUIRES: Force-blank
// REQUIRES: 8 bit A, 16 bit Index, DP = 0, DB access registers
a8()
i16()
code()
function GenerateTilemap {

constant N_TILES = tileBuffer.size / BITS_PER_PIXEL / 8
constant BUFFER_TILE_HEIGHT = N_TILES / TILEMAP_WIDTH

assert(BUFFER_TILE_HEIGHT < TILEMAP_HEIGHT)


    lda.b   #VMAIN.increment.by1 | VMAIN.incrementMode.high
    sta.w   VMAIN


    ldx.w   #VRAM_BG1_MAP_WADDR
    stx.w   VMADD


    // Fill tilemap with sequential tiles
    ldx.w   #0
    -
        stx.w   VMDATA
        inx
        cpx.w   #N_TILES
        bne     -


    // Fill the rest of the tilemap with zeros
    ldx.w   #0
    ldy.w   #(TILEMAP_HEIGHT - BUFFER_TILE_HEIGHT) * TILEMAP_WIDTH
    -
        stx.w   VMDATA
        dey
        bne     -

    rts
}



// Clear the tile buffer
//
// REQUIRES: 8 bit A, 16 bit Index, DP = 0, DB = 0x7e
a8()
i16()
code()
function ClearTileBuffer {
    rep     #$30
a16()

    assert(tileBuffer.size % 2 == 0)

    ldx.w   #tileBuffer.size - 2
    Loop:
        stz.w   tileBuffer,x
        dex
        dex
        bne     Loop

    stz.w   tileBuffer

    sep     #$20
a8()
    rts
}



// Draw an image to the tile buffer
//
// REQUIRES: Force-blank
// REQUIRES: 8 bit A, 16 bit Index, DP = 0, DB = 0x7e
a8()
i16()
code()
function DrawImage {

    // Just drawing a dummy image for now
    //
    // ::TODO Add a line drawing algorithm::
    // ::TODO Create a list of lines to draw::


    lda.b   #0
    -
        pha
            ldx.w   #235
            tay
            lda.b   #1
            jsr     SetPixelWithBoundsChecking
        pla
        inc
        bne     -


    lda.b   #0
    -
        pha
            ldx.w   #15
            tay
            lda.b   #2
            jsr     SetPixelWithBoundsChecking
        pla
        inc
        bne     -


    lda.b   #0
    -
        pha
            tax
            ldy.w   #7
            lda.b   #3
            jsr     SetPixelWithBoundsChecking
        pla
        inc
        bne     -


    lda.b   #0
    -
        pha
            tax
            ldy.w   #202
            lda.b   #4
            jsr     SetPixelWithBoundsChecking
        pla
        inc
        bne     -


    lda.b   #0
    -
        pha
            tax
            lsr
            tay
            lda.b   #5
            jsr     SetPixelWithBoundsChecking
        pla
        inc
        bne     -


    lda.b   #0
    -
        pha
            tay
            lsr
            tax
            lda.b   #6
            jsr     SetPixelWithBoundsChecking
        pla
        inc
        bne     -

    rts
}



// Draw a pixel to the buffer (with bounds checking)
//
// REQUIRES: Force-blank
// REQUIRES: 8 bit A, 16 bit Index, DP = 0, DB = 0x7e
//
// INPUT: X = x-position
//        Y = y-position
//        A = pixel colour
a8()
i16()
code()
function SetPixelWithBoundsChecking {
    // Clip index registers to 8 bits
    sep     #$10
i8()
    cpy.b   #DISPLAY_HEIGHT
    rep     #$10
a16()
    bcs     +
        jmp     SetPixel
    +
    rts
}




// Interrupts
// ==========


// Break ISR
//
// Red screen of death on error
au()
iu()
code()
CopHandler:
IrqHandler:
EmptyHandler:
function BreakHandler {
    rep     #$30
    sep     #$20
i16()
a8()
    assert(pc() >> 16 == 0x80)
    phk
    plb

    jsr     ResetRegisters

    stz.w   CGADD
    lda.b   #0x1f
    sta.w   CGDATA
    stz.w   CGDATA

    lda.b   #0x0f
    sta.w   INIDISP

-
    wai
    bra     -
}




// NMI ISR
//
// Does nothing
au()
iu()
code()
function NmiHandler {
    rti
}




// Resources
// =========

namespace Resources {


if BITS_PER_PIXEL == 1 {
    Palette:
        dw  ToPalette( 0,  0,  0)
        dw  ToPalette(31, 31, 31)

        fill 512 - 2 * 2, 0x1c
    constant Palette.size = pc() - Palette

} else if BITS_PER_PIXEL == 2 {
    Palette:
        dw  ToPalette( 0,  0,  0)
        dw  ToPalette(31, 31, 31)
        dw  ToPalette(31,  0,  0)
        dw  ToPalette( 0, 31,  0)

        fill 512 - 2 * 4, 0x1c
    constant Palette.size = pc() - Palette

} else if BITS_PER_PIXEL == 4 {
    // ::TODO better palette::
    Palette:
        dw  ToPalette( 0,  0,  0)
        dw  ToPalette(31, 31, 31)
        dw  ToPalette(31,  0,  0)
        dw  ToPalette( 0, 31,  0)
        dw  ToPalette( 0,  0, 31)
        dw  ToPalette(31, 31,  0)
        dw  ToPalette( 0, 31, 31)

        fill 512 - 2 * 7, 0x1c
    constant Palette.size = pc() - Palette

} else if BITS_PER_PIXEL == 8 {
    // ::TODO better palette::
    Palette:
        dw  ToPalette( 0,  0,  0)
        dw  ToPalette(31, 31, 31)
        dw  ToPalette(31,  0,  0)
        dw  ToPalette( 0, 31,  0)
        dw  ToPalette( 0,  0, 31)
        dw  ToPalette(31, 31,  0)
        dw  ToPalette( 0, 31, 31)

        fill 512 - 2 * 7, 0x1c
    constant Palette.size = pc() - Palette

} else {
    error "Invalid BITS_PER_PIXEL value"
}


assert(Palette.size == 256 * 2)

}

