// A Model-1 HDMA/DMA crash test ROM
//
// This test is designed to recreate the conditions of the model 1/1/1 DMA/HDMA crash as quickly as
// possible (frame 0, scanline 1 or 0).
//
// Test output:
//   * Red screen: A break interrupt occurred (crash).
//   * White screen: HDMA was not active on scanline 0.
//   * Green HDMA gradient:  No crashes detected and no HDMA errors.
//     The S-CPU may have done something unexpected, but it did not execute a `brk` or `cop` instructions.
//
//
// It has been discovered that a sd2snes has a different reset position to a normal cartridge.
// To make matters worse, there is a 10 dot jitter in the reset position.  To minimize the
// reset-jitter half of the tests (`_test-no-irq-delay.inc`) use an IRQ interrupt to delay the test
// by a single scanline to minimize the test-start jitter to 3 dots.
//
//
// Copyright (c) 2023, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


architecture wdc65816

include "../../_common/registers.inc"


// Memory location to store the `OPHCT` value read by the test.
// Used to verify the IRQ delay works correctly.
constant ophctValue = 0


constant DISPLAY_HEIGHT = 224

constant FAILURE_COLOR = %00000'00000'01000


// Lorom seek macro
macro seek(evaluate addr) {
    origin (({addr} & 0x3f0000) >> 1) | ({addr} & 0x7fff)
    base   {addr}
}


seek(0xA000)
include "../../break_handler.inc"



// This macro must be invoked at the start of an IRQ or Reset ISR.
//
// DB = 0
// SP unknown
// e unknown
// d = 0
// a8
// i unknown
macro QuickDmaTest(evaluate DMA_TRANSFER_SIZE) {
    // Latch PPU counters as early as possible
    lda.w   SLHV

    // Not setting Stack Pointer (not enough CPU time).
    // The high byte of SP is 0x01 on reset and this test only uses a single variable at 0x00

    clc
    xce

    rep     #$38
    sep     #$24
// d flag clear
// i flag set
// i16
// a8

    // Save OPHCT counter to be read by usb2snes to verify the horizontal-position is correct
    lda.w   OPHCT
    sta.b   ophctValue


    // Set backdrop color to white
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

    ldx.w   #{DMA_TRANSFER_SIZE}
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
    nop
    nop
    nop
    nop
    lda.w   NLTR7
    cmp.b   #0xff - 1
    beq     +
        stz.w   HDMAEN
    +

    jsr     ResetRegistersExceptHdma


    lda.b   #0xf
    sta.w   INIDISP

    -
        wai
        bra -
}



// NOTE: Does not reset HDMA
//
// a8
// DB access registers
seek(0xB000)
function ResetRegisters {
    stz.w   HDMAEN

// Fallthrough
}


function ResetRegistersExceptHdma {
    stz.w   NMITIMEN

    lda.b   #INIDISP.force
    sta.w   INIDISP

    stz.w   BGMODE

    stz.w   MOSAIC

    lda.b   #0xff
    sta.w   BG1VOFS
    sta.w   BG1VOFS

    stz.w   BG1HOFS
    stz.w   BG1HOFS

    stz.w   TM
    stz.w   TS
    stz.w   TMW
    stz.w   TSW

    stz.w   CGWSEL
    stz.w   CGADSUB

    stz.w   WOBJSEL
    stz.w   SETINI

    rts
}



// The block of data to transfer on using DMA
// (using 0xff to make it easy to see on an oscilloscope)
DmaBlock:
    fill 0x1000, 0xff



// SNES Header
seek(0xffb0)
SnesHeader:
    // Reset map
    map 0, 0, 256

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
    dw  IrqHandler

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

