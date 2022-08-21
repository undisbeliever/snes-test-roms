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
createRamBlock(lowram,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)
createRamBlock(wram7e,      0x7e2000, 0x7effff)


include "../reset_handler.inc"
include "../break_handler.inc"
include "../dma_forceblank.inc"



if !{defined MODE7} {
    // VRAM Map
    constant VRAM_BG1_TILES_WADDR = 0x0000
    constant VRAM_BG1_MAP_WADDR   = 0x7c00  // 32x32

    // The size of a single tilemap
    constant TILEMAP_WIDTH = 32
    constant TILEMAP_HEIGHT = 32

    constant BUFFER_WIDTH_PX = 256
    constant BUFFER_HEIGHT_PX = 224

} else {
    // Mode 7

    constant BITS_PER_PIXEL = 8
    constant TILE_SIZE_IN_BYTES = BITS_PER_PIXEL * 8

    constant M7_TILEMAP_WIDTH  = 128
    constant M7_TILEMAP_HEIGHT = 128

    constant BUFFER_WIDTH_PX = 128
    constant BUFFER_HEIGHT_PX = 112
}

constant BUFFER_SIZE = BUFFER_WIDTH_PX * BUFFER_HEIGHT_PX * BITS_PER_PIXEL / 8



// Temporary zero-page word variables
// Used by the SetPixel routine
// (word)
allocate(zpTmp0, zeropage, 2)
allocate(zpTmp1, zeropage, 2)


// `SetPixel` pixel colour.
// (zeropage byte)
allocate(SetPixel.pixelColour, zeropage, 1)



// Byte variables used by DrawLine routine
allocate(DrawLine.zpTmpB0, zeropage, 1)
allocate(DrawLine.zpTmpB1, zeropage, 1)
allocate(DrawLine.zpTmpB2, zeropage, 1)
allocate(DrawLine.zpTmpB3, zeropage, 1)
allocate(DrawLine.zpTmpB4, zeropage, 1)
allocate(DrawLine.zpTmpB5, zeropage, 1)

// Word variables used by the DrawLine routine
allocate(DrawLine.zpWord0, zeropage, 2)
allocate(DrawLine.zpWord1, zeropage, 2)
allocate(DrawLine.zpWord2, zeropage, 2)
allocate(DrawLine.zpWord3, zeropage, 2)
allocate(DrawLine.zpWord4, zeropage, 2)


// Current position in `LineList`
// (word index)
allocate(lineIndex, lowram, 2)




// Tile buffer
allocate(tileBuffer, wram7e, BUFFER_SIZE)
constant tileBuffer.size = BUFFER_SIZE



// VBlank routine
macro VBlank() {
    // Empty - no VBlank routine
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


    // Set PPU registers

    if !{defined MODE7} {
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

    } else {
        // Mode 7

        lda.b   #7
        sta.w   BGMODE

        stz.w   M7SEL


        // Initialize Mode 7 matrix
        lda.b   #MODE7_MATRIX_A
        sta.w   M7A
        lda.b   #MODE7_MATRIX_A >> 8
        sta.w   M7A
        lda.b   #MODE7_MATRIX_B
        sta.w   M7B
        lda.b   #MODE7_MATRIX_B >> 8
        sta.w   M7B
        lda.b   #MODE7_MATRIX_C
        sta.w   M7C
        lda.b   #MODE7_MATRIX_C >> 8
        sta.w   M7C
        lda.b   #MODE7_MATRIX_D
        sta.w   M7D
        lda.b   #MODE7_MATRIX_D >> 8
        sta.w   M7D

        stz.w   M7X
        stz.w   M7X
        stz.w   M7Y
        stz.w   M7Y
    }

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
    Dma.ForceBlank.ToCgram(Palette)

    jsr     GenerateTilemap

    jsr     TransferTileBufferToVram


    EnableVblankInterrupts()
    jsr     WaitFrame

    // Enable screen, full brightness (in VBlank)
    lda.b   #15
    sta.w   INIDISP


    MainLoop:
        wai
        bra     MainLoop
}


if !{defined MODE7} {

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

    ldx.w   #0
    Loop:
        stx.w   lineIndex
        jsr     DrawLine

        ldx.w   lineIndex
        inx
        inx
        inx
        inx
        inx
        cpx.w   #LineList.size
        bcc     Loop

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
    cpy.b   #BUFFER_HEIGHT_PX
    rep     #$10
a16()
    bcs     +
        jmp     SetPixel
    +
    rts
}


code()
namespace DrawLine {
a8()
i16()
InvalidInput:
    rts
}



// Draw a line to the tile buffer
//
// REQUIRES: 8 bit A, 16 bit Index, DP = 0, DB = 0x7e
//
// INPUT: X = index into `LineList`
a8()
i16()
code()
function DrawLine {

constant _xPos      = zpTmpB0
constant _yPos      = zpTmpB1
constant _targetX   = zpTmpB2
constant _targetY   = zpTmpB3

constant _iy        = zpTmpB4


// Word variables
// _dx and _dy are word variables as they simplify the creation of _a, _b & _d below
constant _dx        = zpWord0
constant _dy        = zpWord1

constant _a         = zpWord2
constant _b         = zpWord3
constant _d         = zpWord4


    // Line drawing code is based on Bresenham's line algorithm.

    // Load variables from Line List (exiting early if y1 or y2 id out of bounds)
    lda.l   LineList.x1,x
    sta.b   _xPos

    lda.l   LineList.y1,x
    cmp.b   #BUFFER_HEIGHT_PX
    bcs     InvalidInput
    sta.b   _yPos

    lda.l   LineList.x2,x
    sta.b   _targetX

    lda.l   LineList.y2,x
    cmp.b   #BUFFER_HEIGHT_PX
    bcs     InvalidInput
    sta.b   _targetY

    lda.l   LineList.colour,x
    sta.b   SetPixel.pixelColour



    // if _xPos >= _targetX:
    //      swap position and target
    // _dx = abs(_xPos - targetX)
    lda.b   _xPos
    sec
    sbc.b   _targetX
    bcc     +
        // _xPos >= _targetX
        sta.b   _dx

        // Swap position and target
        assert16i()
        assert(_xPos + 1 == _yPos)
        assert(_targetX + 1 == _targetY)
        ldx.b   _xPos
        ldy.b   _targetX

        sty.b   _xPos
        stx.b   _targetX

        bra     ++

    +
        // _xPos < _targetX

        eor.b   #0xff
        inc
        sta.b   _dx
    +
    stz.b   _dx + 1


    // _dy = abs(_yPos - targetY)
    // _iy = _yPos < targetY ? 1 : -1
    lda.b   _yPos
    sec
    sbc.b   _targetY
    bcc     +
        // _yPos >= _targetY
        sta.b   _dy

        lda.b   #-1

        bra     ++

    +
        // _yPos < _targetY

        eor.b   #0xff
        inc
        sta.b   _dy

        lda.b   #1
    +
    sta.b   _iy
    stz.b   _dy + 1



    lda.b   _dx
    cmp.b   _dy
    bcc     SteepLine
        // Shallow Line dx >= dy

        // _a = (_dy - _dx) * 2
        // _b = _dy * 2
        // _d = _b - dx
        rep     #$30
    a16()
        lda.b   _dy
        sec
        sbc.b   _dx
        asl
        sta.b   _a

        lda.b   _dy
        asl
        sta.b   _b

        sec
        sbc.b   _dx
        sta.b   _d


    a16()
        ShallowLoop:
            sep     #$20
        a8()

            ldx.b   _xPos
            ldy.b   _yPos
            jsr     SetPixel

            lda.b   _xPos
            cmp.b   _targetX
            beq     Return

            inc
            sta.b   _xPos

            rep     #$20
        a16()

            lda.b   _d
            bmi     +
            beq     +
                // _d > 0
                clc
                adc.b   _a
                sta.b   _d

                sep     #$20
            a8()
                lda.b   _yPos
                clc
                adc.b   _iy
                sta.b   _yPos
                cmp.b   #BUFFER_HEIGHT_PX
                bcs     Return

                bra     ShallowLoop

            +
            a16()
                // _d <= 0
                clc
                adc.b   _b
                sta.b   _d

                bra     ShallowLoop


    SteepLine:
        // dx < dy

        // _a = (_dx - _dy) * 2
        // _b = _dx * 2
        // _d = _b - dy
        rep     #$30
    a16()
        lda.b   _dx
        sec
        sbc.b   _dy
        asl
        sta.b   _a

        lda.b   _dx
        asl
        sta.b   _b

        sec
        sbc.b   _dy
        sta.b   _d

    a16()
        SteepLoop:
            sep     #$20
        a8()
            ldx.b   _xPos
            ldy.b   _yPos
            jsr     SetPixel

            lda.b   _yPos
            cmp.b   _targetY
            beq     Return

            clc
            adc.b   _iy
            sta.b   _yPos

            rep     #$20
        a16()

            lda.b   _d
            bmi     +
            beq     +
                // _d > 0
                clc
                adc.b   _a
                sta.b   _d

                sep     #$20
            a8()
                // No need to preform a bounds check on _xPos
                inc.b   _xPos

                bra     SteepLoop

            a16()
            +
                // _d <= 0
                clc
                adc.b   _b
                sta.b   _d

                bra     SteepLoop

a8()
Return:
    rts
}



// Palette
// =======

if BITS_PER_PIXEL == 1 {
    Palette:
        dw  ToPalette( 0,  0,  0)
        dw  ToPalette(31, 31, 31)

        fill 512 - 2 * 2, 0x1c
    constant Palette.size = pc() - Palette

    constant N_COLORS = 1


} else if BITS_PER_PIXEL == 2 {
    Palette:
        dw  ToPalette( 0,  0,  0)
        dw  ToPalette(31, 31, 31)
        dw  ToPalette(31,  0,  0)
        dw  ToPalette( 0, 31,  0)

        fill 512 - 2 * 4, 0x1c
    constant Palette.size = pc() - Palette

    constant N_COLORS = 4


} else if BITS_PER_PIXEL == 4 {
    // ::TODO better palette::
    Palette:
        dw  ToPalette( 0,  0,  0)
        dw  ToPalette(31, 31, 31)
        dw  ToPalette(31,  0,  0)
        dw  ToPalette(15,  0,  0)
        dw  ToPalette( 0, 31,  0)
        dw  ToPalette( 0, 15,  0)
        dw  ToPalette( 0,  0, 31)
        dw  ToPalette( 0,  0, 15)
        dw  ToPalette(31, 31,  0)
        dw  ToPalette(15, 15,  0)
        dw  ToPalette( 0, 31, 31)
        dw  ToPalette( 0, 15, 15)
        dw  ToPalette(31,  0, 31)

        fill 512 - 2 * 13, 0x1c
    constant Palette.size = pc() - Palette

    constant N_COLORS = 13


} else if BITS_PER_PIXEL == 8 {
    // ::TODO better palette::
    Palette:
        dw  ToPalette( 0,  0,  0)
        dw  ToPalette(31, 31, 31)
        dw  ToPalette(20, 20, 20)
        dw  ToPalette(10, 10, 10)
        dw  ToPalette(31,  0,  0)
        dw  ToPalette(15,  0,  0)
        dw  ToPalette( 0, 31,  0)
        dw  ToPalette( 0, 15,  0)
        dw  ToPalette( 0,  0, 31)
        dw  ToPalette( 0,  0, 15)
        dw  ToPalette(31, 31,  0)
        dw  ToPalette(15, 15,  0)
        dw  ToPalette( 0, 31, 31)
        dw  ToPalette( 0, 15, 15)
        dw  ToPalette(31,  0, 31)
        dw  ToPalette(15,  0, 15)
        dw  ToPalette(31, 15,  0)
        dw  ToPalette(15, 31,  0)
        dw  ToPalette( 0, 31, 15)
        dw  ToPalette( 0, 15, 31)
        dw  ToPalette(31,  0, 15)
        dw  ToPalette(15,  0, 31)
        dw  ToPalette(31, 23, 15)
        dw  ToPalette(15, 31, 23)
        dw  ToPalette(23, 15, 31)

        fill 512 - 2 * 25, 0x1c
    constant Palette.size = pc() - Palette

    constant N_COLORS = 25


} else {
    error "Invalid BITS_PER_PIXEL value"
}

assert(Palette.size == 256 * 2)



// Line List
// =========

LineList:
namespace LineList {
    // Data format:  x1, y1, x2, y2, colour
    constant x1     = LineList + 0
    constant y1     = LineList + 1
    constant x2     = LineList + 2
    constant y2     = LineList + 3
    constant colour = LineList + 4

    constant elementSize = 5


    // ::TODO draw an picture::

    if N_COLORS > 1 {
        assert(24 % (N_COLORS - 1) == 0)
    }

    variable _c = 1
    variable _t = 0

    inline addLine(evaluate x2, evaluate y2) {
        db BUFFER_WIDTH_PX / 2, BUFFER_HEIGHT_PX / 2, {x2}, {y2}, _c

        _t = _t + 1
        if _t >= 5 {
            _t = 0

            _c = _c + 1
            if _c >= N_COLORS {
                _c = 1
            }
        }
    }

    variable _y = 0
    while _y < BUFFER_HEIGHT_PX {
        addLine(0, _y)

        _y = _y + 8
    }

    variable _x = 0
    while _x < BUFFER_WIDTH_PX {
        addLine(_x, BUFFER_HEIGHT_PX - 1)

        _x = _x + 8
    }

    variable _y = BUFFER_HEIGHT_PX - 1
    while _y > 0 {
        addLine(BUFFER_WIDTH_PX - 1, _y)

        _y = _y - 8
    }

    variable _x = BUFFER_WIDTH_PX - 1
    while _x > 0 {
        addLine(_x, 0)

        _x = _x - 8
    }
}
constant LineList.size = pc() - LineList


