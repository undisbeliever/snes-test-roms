// A simple demo that uses VMAIN to draw an entire Mode 7 tilemap row
// in a single DMA transfer.
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "MODE7 TILEMAP ROWS"
define VERSION = 1


architecture wdc65816-strict


include "../common.inc"


createCodeBlock(code,       0x808000, 0x80ffaf)

createRamBlock(shadow,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)
createRamBlock(wram7e,      0x7e2000, 0x7effff)


include "../reset_handler.inc"
include "../dma_forceblank.inc"



constant MODE7_TILEMAP_WIDTH = 128
constant MODE7_TILEMAP_HEIGHT = 128


constant ROWS_TO_TRANSFER = 28

assert(ROWS_TO_TRANSFER < MODE7_TILEMAP_WIDTH)


constant MODE7_MATRIX_A = 0x0100
constant MODE7_MATRIX_B = 0
constant MODE7_MATRIX_C = 0
constant MODE7_MATRIX_D = 0x0100



// Execute V-Blank Routine flag
//
// The VBlank routine will be executed if this value is non-zero.
//
// (byte flag)
allocate(vBlankFlag, shadow, 1)




// If this variable is zero, draw the next row on the next VBlank
//
// (byte flag)
allocate(transferRowOnZero, shadow, 1)


// VRAM word address of the next mode-7 row to transfer.
//
// (VRAM word address)
allocate(rowVramWaddr, shadow, 2)


// The tileId of the row to draw.
//
// (byte)
allocate(rowTile, shadow, 1)



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



    // Setup variables
    ldx.w   #0
    stx.w   rowVramWaddr

    lda.b   #1
    sta.w   rowTile

    stz.w   transferRowOnZero



    // Setup PPU registers

    // Mode 7
    lda.b   #BGMODE.mode7
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


    stz.w   BG1HOFS
    stz.w   BG1HOFS

    lda.b   #-1
    sta.w   BG1VOFS
    sta.w   BG1VOFS


    // Enable BG1
    lda.b   #TM.bg1
    sta.w   TM


    // Clear Mode 7 Tilemap
    ldx.w   #0
    ldy.w   #MODE7_TILEMAP_WIDTH * MODE7_TILEMAP_WIDTH
    jsr     Dma.ForceBlank.ClearVramL


    // Transfer tiles and palette to VRAM
    ldx.w   #0
    stx.w   VMADD
    Dma.ForceBlank.ToVramH(Resources.Mode7Tiles)


    // Transfer palette to CGRAM
    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Palette)


    // Enable VBlank interrupts
    lda.b   #NMITIMEN.vBlank
    sta.w   NMITIMEN



    jsr     WaitFrame

    // Enable screen, full brightness (still in VBlank)
    lda.b   #15
    sta.w   INIDISP



    MainLoop:
        jsr     WaitFrame
        jsr     WaitFrame
        jsr     WaitFrame
        jsr     WaitFrame
        jsr     WaitFrame
        jsr     WaitFrame
        jsr     WaitFrame
        jsr     WaitFrame


        // Advance to the next row
        rep     #$30
    a16()
        lda.w   rowVramWaddr
        clc
        adc.w   #MODE7_TILEMAP_WIDTH
        cmp.w   #MODE7_TILEMAP_WIDTH * ROWS_TO_TRANSFER
        bcc     +
            lda.w   #0
        +
        sta.w   rowVramWaddr

        sep     #$20
    a8()
        // carry set if `rowVramWaddr` has been reset
        bcc     ++
            // `rowVramWaddr` has been reset, draw a different tile
            lda.w   rowTile
            inc
            cmp.b   #Resources.N_TILES
            bcc     +
                lda.b   #0
            +
            sta.w   rowTile
        +

        stz.w   transferRowOnZero


        jmp     MainLoop
}



// VBlank routine
//
// REQUIRES: 8 bit A, 16 bit Index, DB = registers, DP = 0
macro VBlank() {
    assert8a()
    assert16i()


    lda.w   transferRowOnZero
    bne     NoTransfer

        // Transfer one MODE7 tilemap row to VRAM
        lda.b   #VMAIN.incrementMode.low | VMAIN.increment.by1
        sta.w   VMAIN


        ldx.w   rowVramWaddr
        stx.w   VMADD


        // Transfer `MODE7_TILEMAP_HEIGHT` copies of the `rowTile` byte to the mode 7 tilemap
        lda.b   #DMAP.direction.toPpu | DMAP.transfer.one | DMAP.fixed
        sta.w   DMAP0

        lda.b   #VMDATAL
        sta.w   BBAD0

        ldx.w   #rowTile
        stx.w   A1T0
        lda.b   #rowTile >> 16
        sta.w   A1B0

        ldx.w   #MODE7_TILEMAP_WIDTH
        stx.w   DAS0

        lda.b   #MDMAEN.dma0
        sta.w   MDMAEN

        // A is non-zero
        sta.w   transferRowOnZero

    NoTransfer:
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
    bra     -
}



// NMI ISR
au()
iu()
code()
function NmiHandler {
    // Jump to FastROM bank
    jml     FastRomNmiHandler
FastRomNmiHandler:

    // Save CPU state
    rep     #$30
a16()
i16()
    pha
    phx
    phy
    phd
    phb


    phk
    plb
// DB = 0x80

    lda.w   #0
    tcd
// DP = 0


    sep     #$20
a8()

    // Only execute the VBlank routine if `vBlankFlag` is non-zero.
    // (prevents corruption during force-blank setup or a lag frame)
    lda.w   vBlankFlag
    bne     +
        jmp     EndVBlankRoutine
    +

        VBlank()


        stz.w   vBlankFlag


EndVBlankRoutine:


    rep     #$30
a16()
i16()

    // Restore CPU state
    assert16a()
    assert16i()
    plb
    pld
    ply
    plx
    pla

    rti
}



// Wait until the start of a new display frame
// (or the end of the VBlank routine (NmiHandler)).
//
// REQUIRES: NMI enabled, DB access shadow
au()
iu()
code()
function WaitFrame {
    php
    sep     #$20
a8()

    lda.b   #1
    sta.w   vBlankFlag


    // Loop until `vBlankFlag` is clear
    Loop:
        wai

        lda.w   vBlankFlag
        bne     Loop

    plp

    rts
}



// Resources
// =========

namespace Resources {


Palette:
    dw  ToPalette( 0,  0 ,  0)
    dw  ToPalette(31, 31,  31)
    dw  ToPalette(31,  0 ,  0)
    dw  ToPalette( 0, 31 ,  0)
    dw  ToPalette( 0,  0 , 31)

constant Palette.size = pc() - Palette


constant N_TILES = Palette.size / 2



Mode7Tiles:
    variable _i = 0
    while _i < N_TILES {
        fill 64, _i

        _i = _i + 1
    }
constant Mode7Tiles.size = pc() - Mode7Tiles

assert(Mode7Tiles.size == 8 * 8 * N_TILES)

}


