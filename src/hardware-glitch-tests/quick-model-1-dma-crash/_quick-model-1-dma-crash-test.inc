// A Model-1 HDMA/DMA crash test ROM
//
// This test is designed to recreate the conditions of the model 1/1/1 DMA/HDMA crash on the first
// Horizontal Blanking period (frame 0, scanline 0).
//
// Test output:
//   * Red screen: A break interrupt occurred (crash).
//   * White screen: HDMA was not active on scanline 0.
//   * Green HDMA gradient:  No crashes detected and no HDMA errors.
//     The S-CPU may have done something unexpected, but it did not execute a `brk` or `cop` instructions.
//
// This test is very finicky.  You will need to reset the console multiple times to get a crash or
// HDMA failure.  To help improve timing there are 4 versions of this test, each with different DMA
// transfer sizes.
//
// DMA_TRANSFER_SIZE of 21 to 24 show crashes and HDMA failures on my 1/1/1 Super Famicom console
// in less than 10 resets using an SD2SNES Rev J running firmware 1.11.0 and the following settings:
//  * In Game Hook: off
//  * Auto region patch: off
//  * 1CHIP transient fixes off
//  * Brightness Limit: off
//  * Reset patch for clock phase: off
//
//
// Copyright (c) 2023, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


evaluate _dts = DMA_TRANSFER_SIZE

define   ROM_NAME = "QUICK DMA CRASH {_dts}"
constant VERSION = 0

architecture wdc65816

include "../../_common/registers.inc"


constant DISPLAY_HEIGHT = 224

constant FAILURE_COLOR = %00000'00000'01000


// Lorom seek macro
macro seek(evaluate addr) {
    origin (({addr} & 0x3f0000) >> 1) | ({addr} & 0x7fff)
    base   {addr}
}


seek(0x8000)

// DB = 0
// SP = 0x01ff
// e = 1
// a8
// i8
function ResetHandler {
    clc
    xce

    rep     #$30
    sep     #$20
// a8
// i16

    stz.w   CGADD
    lda.b   #0xff
    sta.w   CGDATA
    sta.w   CGDATA


    // Setup mid-frame HDMA
    ldx.w   #DMAP.direction.toPpu | DMAP.transfer.twoWriteTwice | (CGADD << 8)
    stx.w   DMAP7               // Also sets BBAD7

    ldx.w   #HdmaTable
    stx.w   A1T7
    stz.w   A1B7

    // Set HDMA state registers for a repeat mode HDMA entry
    inx
    stx.w   A2A7                // current HDMA table address
    lda.b   #0xff
    sta.w   NLTR7               // line counter

    lda.b   #HDMAEN.dma7
    sta.w   HDMAEN


    // DMA transfer
    // Transferring to OAMDATA so this transfer is visible on Mesen's Trace Viewer

    ldx.w   #DMAP.direction.toPpu | DMAP.transfer.one | (OAMDATA << 8)
    stx.w   DMAP0       // also sets BBAD0

    ldx.w   #DmaBlock
    stx.w   A1T0
    stz.w   A1B0

    ldx.w   #DMA_TRANSFER_SIZE
    stx.w   DAS0

    lda.b   #MDMAEN.dma0
    sta.w   MDMAEN


    // Disable HDMA if there was no HDMA write at the end of scanline 0

    // Wait a bit before testing the line counter
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    lda.w   NLTR7
    cmp.b   #0xff - 1
    beq     +
        stz.w   HDMAEN
    +


    // Show only the backdrop
    stz.w   TM
    stz.w   TS
    stz.w   TMW
    stz.w   TSW

    stz.w   CGWSEL
    stz.w   CGADSUB

    stz.b   WOBJSEL
    stz.b   SETINI


    lda.b   #0xf
    sta.w   INIDISP

    -
        wai
        bra -
}



// Break ISR
//
// Display a dark red screen
//
// DB unknown (it may be corrupted)
// A unknown
// I unknown
function BreakHandler {
    sep     #$30
// a8
// i8
    phk
    plb
// DB = 0

    // Disable HDMA
    stz.w   HDMAEN
    stz.w   NMITIMEN

    lda.b   #INIDISP.force
    sta.w   INIDISP

    // Set the backdrop color to dark red
    stz.w   CGADD

    lda.b   #FAILURE_COLOR
    sta.w   CGDATA
    lda.b   #FAILURE_COLOR >> 8
    sta.w   CGDATA

    // Show only the backdrop
    stz.w   TM
    stz.w   TS
    stz.w   TMW
    stz.w   TSW

    stz.w   CGWSEL
    stz.w   CGADSUB

    stz.b   WOBJSEL
    stz.b   SETINI

    lda.b   #0xf
    sta.w   INIDISP

    -
        wai
        bra -
}



seek(0x9000)

// The block of data to transfer on using DMA
// (using 0xff to make it easy to see on an oscilloscope)
DmaBlock:
    fill 0x1000, 0xff



seek(0xA000)

HdmaTable:
namespace HdmaTable {
    // HDMA table to CGRAM (2 registers write twice)

    constant SCANLINES_PER_ENTRY = 16

    variable _sl = 0

    variable _i = 0
    while _i < 2 {
        db  0x80 | 0x7f     // HDMA repeat mode

        variable _j = 0
        while _j < 0x7f {
            evaluate c = (_sl + 8) % 64
            if {c} > 31 {
                evaluate c = 63 - {c}
            }
            _sl = _sl + 1

            dw  0           // CGADD
            dw  {c} << 5    // CGDATA

            _j = _j + 1
        }

        _i = _i + 1
    }

    db 0
}



// SNES Header
seek(0xffb0)
SnesHeader:
    db  "  "                    // $ffbo - 2 Digit marker code (blank - unlicensed)
    db  "    "                  // $ffb2 - 4 Character game code (blank - unlicensed)
    db  0, 0, 0, 0, 0, 0, 0     // $ffb6 - fixed value (7 bytes)

    db  0                       // $ffbd - expansion RAM size
    db  0                       // $ffbe - special version
    db  0                       // $ffbf - cartridge type sub-number

    fill 21, ' '
seek(0xffc0)
    db  {ROM_NAME}              // $ffc0 - ROM name (21 characters)
seek(0xffd5)
    db  0x20                    // $ffd5 - map mode
    db  0                       // $ffd6 - cartridge type (0 = ROM only)
    db  7                       // $ffd7 - ROM size (7 = 1Mbit)
    db  0                       // $ffd8 - RAM size
    db  0                       // $ffd9 - Destination code (0 = Japan, tested on a Super Famicom console)
    db  0x33                    // $ffda - fixed value
    db  VERSION                 // $ffdb - ROM version
    dw  0xaaaa                  // $ffdc - checksum compliment
    dw  0x5555                  // $ffde - checksum

// Native Interrupt Vectors
    dw  BreakHandler
    dw  BreakHandler
    dw  BreakHandler
    dw  BreakHandler
    dw  BreakHandler
    dw  BreakHandler
    dw  BreakHandler
    dw  BreakHandler

// Emulated Interrupt Vectors
    dw  BreakHandler
    dw  BreakHandler
    dw  BreakHandler
    dw  BreakHandler
    dw  BreakHandler
    dw  BreakHandler
    dw  ResetHandler            // $fffc - emu reset
    dw  BreakHandler



// Padding
seek(0x03ffff)
    db  0

