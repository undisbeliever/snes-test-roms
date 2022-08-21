// A simple demo that uses VMAIN to quickly convert 1bpp tiles to 2bpp tiles
// and transfer them into vram.
//
// This demo will set the high bits to 0, effectively creating tiles
// that use 2bpp palette colours 0 (transparent) & 1.
//
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "VMAIN 1BPP TILES 0"
define VERSION = 1


architecture wdc65816-strict


include "../common.inc"


createCodeBlock(code,       0x808000, 0x80ffaf)

createRamBlock(zeropage,    0x000000, 0x0000ff)
createRamBlock(lowram,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)
createRamBlock(wram7e,      0x7e2000, 0x7effff)


include "../reset_handler.inc"
include "../break_handler.inc"
include "../dma_forceblank.inc"



// VRAM Map
constant VRAM_BG1_MAP_WADDR   = 0x0000  // 32x32
constant VRAM_BG1_TILES_WADDR = 0x1000


// The size of a single tilemap
constant TILEMAP_WIDTH = 32
constant TILEMAP_HEIGHT = 32



// Temporary zero-page word variable
// (word)
allocate(zpTmp0, zeropage, 2)




// Transfer 1bpp tiles to VRAM, converting the 1bpp tiles to 2bpp tiles
// with a high bit of 0.
//
// The tiles will have transparent pixels and will use 2bpp palette colours 0 & 1.
//
// REQUIRES: 8 bit A, 16 bit Index, DP = 0, DB access registers
// REQUIRES: Force Blank enabled
//
// Uses DMA channel 0
//
// INPUT: zpTmp0 = VRAM word address to store the tile data
//           A:X = address of 1bpp tile data
//             Y = size of 1bpp tile data
a8()
i16()
code()
function Transfer1bppTilesToVram_0 {

    // First DMA transfer.
    //
    // Transfer the tiles data to the VRAM low bytes (VMADDL).

    // MUST NOT modify Y

    // A:X = 1bpp tile address
    stx.w   A1T0
    sta.w   A1B0

    // Y = size
    sty.w   DAS0

    lda.b   #DMAP.direction.toPpu | DMAP.transfer.one
    sta.w   DMAP0

    lda.b   #VMDATAL
    sta.w   BBAD0


    lda.b   #VMAIN.incrementMode.low | VMAIN.increment.by1
    sta.w   VMAIN

    ldx.b   zpTmp0
    stx.w   VMADD


    lda.b   #MDMAEN.dma0
    sta.w   MDMAEN



    // Second DMA transfer.
    //
    // Fill the high bits with zeros

    lda.b   #VMAIN.incrementMode.high | VMAIN.increment.by1
    sta.w   VMAIN

    ldx.b   zpTmp0
    stx.w   VMADD


    lda.b   #DMAP.direction.toPpu | DMAP.transfer.one | DMAP.fixed
    sta.w   DMAP0

    lda.b   #VMDATAH
    sta.w   BBAD0

    ldx.w   #Resources.ZeroByte
    stx.w   A1T0
    lda.b   #Resources.ZeroByte >> 16
    sta.w   A1B0

    // Y = size
    sty.w   DAS0


    lda.b   #MDMAEN.dma0
    sta.w   MDMAEN

    rts
}



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

    // Mode 0
    stz.w   BGMODE

    lda.b   #(VRAM_BG1_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG1SC

    lda.b   #(VRAM_BG1_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg1.shift
    sta.w   BG12NBA

    lda.b   #TM.bg1
    sta.w   TM


    // Transfer tilemap to VRAM
    ldx.w   #VRAM_BG1_MAP_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Map)


    // Transfer palette to CGRAM
    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Palette)


    // Clear the first tile in BG1
    ldx.w   #VRAM_BG1_TILES_WADDR
    ldy.w   #16
    jsr     Dma.ForceBlank.ClearVram


    // Transfer 1bpp tiles to VRAM

    // Start transfer from tile 1, tile 0 will be fully transparent.
    ldx.w   #VRAM_BG1_TILES_WADDR + 8
    stx.b   zpTmp0

    ldx.w   #Resources.Tiles_1bpp
    lda.b   #Resources.Tiles_1bpp >> 16
    ldy.w   #Resources.Tiles_1bpp.size

    jsr     Transfer1bppTilesToVram_0



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




// Interrupts
// ==========


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


ZeroByte:
    db  0


Palette:
    dw  ToPalette( 0,  0,  0)
    dw  ToPalette(31, 31, 31)
    dw  ToPalette(31,  0,  0)
    dw  ToPalette(31,  0,  0)

constant Palette.size = pc() - Palette



Tiles_1bpp:
    db  %01000010
    db  %01000010
    db  %01000010
    db  %01111110
    db  %01000010
    db  %01000010
    db  %01000010
    db  %00000000

    db  %01111110
    db  %01000000
    db  %01000000
    db  %01111000
    db  %01000000
    db  %01000000
    db  %01111110
    db  %00000000

    db  %01000000
    db  %01000000
    db  %01000000
    db  %01000000
    db  %01000000
    db  %01000000
    db  %01111110
    db  %00000000

    db  %01000000
    db  %01000000
    db  %01000000
    db  %01000000
    db  %01000000
    db  %01000000
    db  %01111110
    db  %00000000

    db  %00111100
    db  %01000010
    db  %01000010
    db  %01000010
    db  %01000010
    db  %01000010
    db  %00111100
    db  %00000000

    db  %00000000
    db  %00000000
    db  %00000000
    db  %00000000
    db  %00000000
    db  %00000000
    db  %00000000
    db  %00000000

    db  %01000010
    db  %01000010
    db  %01011010
    db  %01011010
    db  %01100110
    db  %01100110
    db  %01000010
    db  %00000000

    db  %00111100
    db  %01000010
    db  %01000010
    db  %01000010
    db  %01000010
    db  %01000010
    db  %00111100
    db  %00000000

    db  %01111100
    db  %01000010
    db  %01000010
    db  %01111100
    db  %01001000
    db  %01000100
    db  %01000010
    db  %00000000

    db  %01000000
    db  %01000000
    db  %01000000
    db  %01000000
    db  %01000000
    db  %01000000
    db  %01111110
    db  %00000000

    db  %01111000
    db  %01000100
    db  %01000010
    db  %01000010
    db  %01000010
    db  %01000100
    db  %01111000
    db  %00000000

    db  %00000000
    db  %00000000
    db  %00000000
    db  %00000000
    db  %00000000
    db  %00000000
    db  %00000000
    db  %00000000

    db  %00111110
    db  %00001000
    db  %00001000
    db  %00001000
    db  %00001000
    db  %00001000
    db  %00111110
    db  %00000000

    db  %01100010
    db  %01100010
    db  %01010010
    db  %01010010
    db  %01001010
    db  %01001010
    db  %01000110
    db  %00000000

    db  %00000000
    db  %00000000
    db  %00000000
    db  %00000000
    db  %00000000
    db  %00000000
    db  %00000000
    db  %00000000

    db  %00011000
    db  %00101000
    db  %00001000
    db  %00001000
    db  %00001000
    db  %00001000
    db  %00111110
    db  %00000000

    db  %01111100
    db  %01000010
    db  %01000010
    db  %01111100
    db  %01000010
    db  %01000010
    db  %01111100
    db  %00000000

    db  %01111100
    db  %01000010
    db  %01000010
    db  %01111100
    db  %01000000
    db  %01000000
    db  %01000000
    db  %00000000

    db  %01111100
    db  %01000010
    db  %01000010
    db  %01111100
    db  %01000000
    db  %01000000
    db  %01000000
    db  %00000000

    db  %00011000
    db  %00011000
    db  %00011000
    db  %00011000
    db  %00000000
    db  %00000000
    db  %00011000
    db  %00000000


constant Tiles_1bpp.size = pc() - Tiles_1bpp

assert(Tiles_1bpp.size % 8 == 0)
constant N_TILES = Tiles_1bpp.size / 8



assert(N_TILES < TILEMAP_WIDTH)

constant MARGIN_TOP = 6
constant MARGIN_LEFT = (TILEMAP_WIDTH - N_TILES) / 2


Map:
    fill MARGIN_TOP * TILEMAP_WIDTH * 2, 0

    fill MARGIN_LEFT * 2, 0

    variable _i = 0
    while _i < N_TILES {
        dw  _i + 1
        _i = _i + 1
    }
    fill (TILEMAP_WIDTH - MARGIN_LEFT - N_TILES) * 2, 0

    fill (TILEMAP_HEIGHT - MARGIN_TOP - 1) * TILEMAP_WIDTH * 2, 0

constant Map.size = pc() - Map

assert(Map.size == TILEMAP_WIDTH * TILEMAP_HEIGHT * 2)


}


