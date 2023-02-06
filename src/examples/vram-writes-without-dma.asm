// A simple write data to VRAM without using DMA example.
//
// Copyright (c) 2023, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "VRAM WRITES NO DMA"
define VERSION = 0

architecture wdc65816-strict

include "../common.inc"


createCodeBlock(code,       0x808000, 0x80ffaf)
createCodeBlock(rodata0,    0x818000, 0x81ffff)

createRamBlock(zeropage,        0x00,     0xff)
createRamBlock(lowram,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)
createRamBlock(wram7e,      0x7e2000, 0xfeffff)

include "../reset_handler.inc"
include "../break_handler.inc"
include "../dma_forceblank.inc"


constant VRAM_BG1_MAP_WADDR   = 0x0000
constant VRAM_BG1_TILES_WADDR = 0x1000


// zero-page temporary far pointer
allocate(zpTmpPtr, zeropage, 3)



// VBlank routine
//
// REQUIRES: 8 bit A, 16 bit Index, DB = 0x80, DP = 0
macro VBlank() {
    assert8a()
    assert16i()
}

include "../vblank_interrupts.inc"


// Write a block of colors to CGRAM.
//
// REQUIRES: Vertical-Blank or Force-Blank.
//           (There is not enough Horizontal-Blank time to run this code)
a8()
i16()
// DB access registers
function WriteCgramData {

    // Reset CGRAM word address (color index)
    stz.w   CGADD

    ldx.w   #0
    Loop:
        // Write low byte
        lda.l   PaletteData,x
        sta.w   CGDATA
        inx

        // Write high byte
        lda.l   PaletteData,x
        sta.w   CGDATA
        inx

        cpx.w   #PaletteData.size
        bne     Loop
    rts
}



// Writes the word data at `TileData` to VRAM word address `VRAM_BG1_TILES_WADDR`.
//
// REQUIRES: Force-Blank
//           (There might not be enough Vertical-Blank time if `TileData` is too large)
a8()
i16()
// DB access registers
function WriteVramTileData {
    // Set VMAIN to word access
    lda.b   #0x80
    sta.w   VMAIN

    // Set VRAM word address
    ldx.w   #VRAM_BG1_TILES_WADDR
    stx.w   VMADD

    // Use a 16 bit accumulator
    rep     #$30
a16()

    ldx.w   #0
    Loop:
        // Read one word of TileData and write it to VRAM
        lda.l   TileData,x
        sta.w   VMDATA

        inx
        inx
        cpx.w   #TileData.size
        bcc     Loop

    sep     #$20
a8()

    rts
}



// Build a BG1 tilemap and write it to VRAM
//
// REQUIRES: Force-Blank
//           (There is not be enough Vertical-Blank time to run this code)
a8()
i16()
// DB access registers
function BuildTilemap {

constant N_TILES = TileData.size / 16

    // VRAM word access
    lda.b   #0x80
    sta.w   VMAIN

    // Set VRAM word address
    ldx.w   #VRAM_BG1_MAP_WADDR
    stx.w   VMADD

    // Use a 16 bit accumulator and 8 bit Index
    rep     #$20
    sep     #$10
a16()
i8()

    ldy.b   #0
    OuterLoop:
        ldx.b   #0

        InnerLoop:
            //  if y == 5 && x >= 5 && x < 5 + N_TILES:
            //      a = x - 5
            //  else:
            //      a = 0
            //
            cpy.b   #5
            bne     +
                // 16 bits transferred, high byte of A is always 0
                txa
                sec
                sbc.w   #5
                cmp.w   #N_TILES
                bcc     ++
            +
                lda.w   #0
            +

            // Write 16-bit A to VRAM
            sta.w   VMDATA

            inx
            cpx.b   #32
            bcc     InnerLoop
        iny
        cpy.b   #32
        bcc     OuterLoop


    // Restore 8 bit A, 16 bit Index
    rep     #$10
    sep     #$20
a8()
i16()

    rts
}



au()
iu()
code()
function Main {
    rep     #$30
    sep     #$20
a8()
i16()
    // Setup PPU
    lda.b   #INIDISP.force | 0x0f
    sta.w   INIDISP

    lda.b   #BGMODE.mode0
    sta.w   BGMODE

    lda.b   #TM.bg1
    sta.w   TM

    lda.b   #(VRAM_BG1_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG1SC

    lda.b   #(VRAM_BG1_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg1.shift
    sta.w   BG12NBA


    jsr     WriteCgramData

    jsr     WriteVramTileData

    jsr     BuildTilemap


    EnableVblankInterrupts()

    jsr     WaitFrame

    lda.b   #0x0f
    sta.w   INIDISP


    MainLoop:
        jsr     WaitFrame
        jmp     MainLoop
}



PaletteData:
    dw  ToPalette(0, 0, 0)
    dw  ToPalette(31, 31, 31)
constant PaletteData.size = pc() - PaletteData


// 2bpp tile data
TileData:
    db  %00000000, %00000000
    db  %00000000, %00000000
    db  %00000000, %00000000
    db  %00000000, %00000000
    db  %00000000, %00000000
    db  %00000000, %00000000
    db  %00000000, %00000000
    db  %00000000, %00000000

    db  %00000000, %00000000
    db  %01000010, %00000000
    db  %01000010, %00000000
    db  %01111110, %00000000
    db  %01000010, %00000000
    db  %01000010, %00000000
    db  %01000010, %00000000
    db  %00000000, %00000000

    db  %00000000, %00000000
    db  %01111110, %00000000
    db  %01000000, %00000000
    db  %01111000, %00000000
    db  %01000000, %00000000
    db  %01000000, %00000000
    db  %01111110, %00000000
    db  %00000000, %00000000

    db  %00000000, %00000000
    db  %01000000, %00000000
    db  %01000000, %00000000
    db  %01000000, %00000000
    db  %01000000, %00000000
    db  %01000000, %00000000
    db  %01111110, %00000000
    db  %00000000, %00000000

    db  %00000000, %00000000
    db  %01000000, %00000000
    db  %01000000, %00000000
    db  %01000000, %00000000
    db  %01000000, %00000000
    db  %01000000, %00000000
    db  %01111110, %00000000
    db  %00000000, %00000000

    db  %00000000, %00000000
    db  %00111100, %00000000
    db  %01000010, %00000000
    db  %01000010, %00000000
    db  %01000010, %00000000
    db  %01000010, %00000000
    db  %00111100, %00000000
    db  %00000000, %00000000

    db  %00000000, %00000000
    db  %00000000, %00000000
    db  %00000000, %00000000
    db  %00000000, %00000000
    db  %00000000, %00000000
    db  %00000000, %00000000
    db  %00000000, %00000000
    db  %00000000, %00000000

    db  %00000000, %00000000
    db  %10000010, %00000000
    db  %10010010, %00000000
    db  %10010010, %00000000
    db  %10010010, %00000000
    db  %01101100, %00000000
    db  %01000100, %00000000
    db  %00000000, %00000000

    db  %00000000, %00000000
    db  %00111100, %00000000
    db  %01000010, %00000000
    db  %01000010, %00000000
    db  %01000010, %00000000
    db  %01000010, %00000000
    db  %00111100, %00000000
    db  %00000000, %00000000

    db  %00000000, %00000000
    db  %01111100, %00000000
    db  %01000010, %00000000
    db  %01000010, %00000000
    db  %01111100, %00000000
    db  %01000100, %00000000
    db  %01000010, %00000000
    db  %00000000, %00000000

    db  %00000000, %00000000
    db  %01000000, %00000000
    db  %01000000, %00000000
    db  %01000000, %00000000
    db  %01000000, %00000000
    db  %01000000, %00000000
    db  %01111110, %00000000
    db  %00000000, %00000000

    db  %00000000, %00000000
    db  %01111000, %00000000
    db  %01000100, %00000000
    db  %01000010, %00000000
    db  %01000010, %00000000
    db  %01000100, %00000000
    db  %01111000, %00000000
    db  %00000000, %00000000

constant TileData.size = pc() - TileData


finalizeMemory()

