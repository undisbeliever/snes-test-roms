// IPL speed test
//
// Test ROM that transfers 32678 bytes of data to Audio-RAM using the S-SMP IPL
// and prints the number of frames it took to make the transfer.
//
// SPDX-FileCopyrightText: © 2025 Marcus Rowe <undisbeliever@gmail.com>
// SPDX-License-Identifier: Zlib
//
// Copyright © 2025 Marcus Rowe <undisbeliever@gmail.com>
//
// This software is provided 'as-is', without any express or implied warranty.
// In no event will the authors be held liable for any damages arising from the
// use of this software.
//
// Permission is granted to anyone to use this software for any purpose, including
// commercial applications, and to alter it and redistribute it freely, subject to
// the following restrictions:
//
//    1. The origin of this software must not be misrepresented; you must not
//       claim that you wrote the original software. If you use this software in
//       a product, an acknowledgment in the product documentation would be
//       appreciated but is not required.
//
//    2. Altered source versions must be plainly marked as such, and must not be
//       misrepresented as being the original software.
//
//    3. This notice may not be removed or altered from any source distribution.


define ROM_NAME = "IPL SPEED TEST"
define VERSION = 1
define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan


architecture wdc65816-strict

include "../../common.inc"


createCodeBlock(code,       0x808000, 0x80ffaf)
createDataBlock(rodata0,    0x818000, 0x81ffff)
createDataBlock(rodata1,    0x828000, 0x82ffff)

createRamBlock(zeropage,        0x00,     0xff)
createRamBlock(stack,       0x7e0100, 0x7e01ff)
createRamBlock(lowram,      0x7e0200, 0x7e1fff)
createRamBlock(wram7e,      0x7e2000, 0xfeffff)


constant TRANSFER_SIZE = 32 * 1024


constant VRAM_BG1_TILES_WADDR = 0x1000
constant VRAM_BG1_MAP_WADDR   = 0x0000

constant VRAM_TEXTBUFFER_MAP_WADDR   = VRAM_BG1_MAP_WADDR
constant VRAM_TEXTBUFFER_TILES_WADDR = VRAM_BG1_TILES_WADDR


include "../../reset_handler.inc"
include "../../break_handler.inc"
include "../../dma_forceblank.inc"
include "../../textbuffer.inc"


// zero-page temporary variables (used by TextBuffer)
allocate(zpTmp0, zeropage, 2)
allocate(zpTmpPtr, zeropage, 3)


// Incremented every VBlank
allocate(frameCounter, zeropage, 1)


allocate(testCounter, zeropage, 1)

allocate(test_startFrameCounter, zeropage, 1)
allocate(test_nVBlanks, zeropage, 1)

allocate(data_farAddr, zeropage, 3)
allocate(data_remainingBytes, zeropage, 2)


// Minimal NMI ISR that also increments a frame counter
au()
iu()
// DB = 0x80
function NmiHandler {
    sep     #$20
a8()
    inc.w   frameCounter

    rti
}


// Initialise the IPL
a8()
i16()
// DB = 0x80
function TestSetup {
    // Clear start command port (just in case APUIO0 has $cc in it)
    // SOURCE: `blarggapu.s` from lorom-template, originally written by blargg (Shay Green)
    stz.w    APUIO0

    // Wait for ready signal
    ldx.w   #0xbbaa
    -
        cpx.w   APUIO0
        bne     -

    rts
}



// OUT: test_nVBlanks = number of VBlanks during the transfer
a8()
i16()
// DB = 0x80
function MeasureIpl {
    rep     #$30
    sep     #$20
a8()
i16()

    lda.b   frameCounter
    sta.b   test_startFrameCounter


    ldx.w   #DataToTransfer
    lda.b   #DataToTransfer >> 16
    stx.b   data_farAddr
    sta.b   data_farAddr + 2

    ldx.w   #DataToTransfer.size
    stx.b   data_remainingBytes


    // Set destination ARAM address ($0200)
    stz.w   APUIO2
    lda.b   #0x02
    sta.w   APUIO3

    // Send a new data command
    //
    // The first data command must use 0xcc.
    // The rest of the data commands MUST be non-zero and be at least 2 larger than APUIO0.
    //
    // From the snesdev wiki
    // https://snes.nesdev.org/wiki/Booting_the_SPC700#Writing_to_a_different_address
    lda.w   APUIO0
    clc
    adc.b   #$22
    bne     +
        inc
    +
    sta.w   APUIO1
    sta.w   APUIO0

    // Wait for a response from the IPL
    -
        cmp.w   APUIO0
        bne     -

    sep     #$30
a8()
i8()
    jsr     _IplWriteLoop


    rep     #$30
    sep     #$20
a8()
i16()

    lda.b   frameCounter
    sec
    sbc.b   test_startFrameCounter
    sta.b   test_nVBlanks

    rts
}


// Optimised IPL writing loop
//
// This function uses DP indirect-long addressing to read the data to match what a game might do.
//
// Moved to a separate function so it can be profiled with Mesen
a8()
i8()
function _IplWriteLoop {
    ldx.b   #0

    lda     [data_farAddr]

    Loop:
        // Send the next byte to the IPL
        sta.w   APUIO1

        // Tell the IPL the next byte is ready
        stx.w   APUIO0

        rep     #$20
    a16()
        inc.b   data_farAddr
        dec.b   data_remainingBytes
        beq     Break

        sep     #$20
    a8()
        // Read next byte
        lda     [data_farAddr]

        txy

        inx

        // Wait for a response form the IPL
        -
            cpy.w   APUIO0
            bne     -

        bra     Loop

Break:

    sep     #$20
a8()

    // Wait for a response form the IPL
    -
        cpx.w   APUIO0
        bne     -

    rts
}



// REQUIRED: Force-Blank
a8()
i16()
// DB = 0x80
function SetupPpu_ForceBlank {
    lda.b   #BGMODE.mode0
    sta.w   BGMODE

    lda.b   #TM.bg1
    sta.w   TM

    lda.b   #(VRAM_BG1_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG1SC

    lda.b   #(VRAM_BG1_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg1.shift
    sta.w   BG12NBA

    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Palette)

    jsr     TextBuffer.InitAndTransferToVram

    rts
}


a8()
i16()
// DB = 0x80
function Main {
    jsr     SetupPpu_ForceBlank

    evaluate TS = TRANSFER_SIZE
    TextBuffer.PrintStringLiteral("Transferring {TS} bytes\nusing the IPL\n\n")

    lda.b   #15
    sta.w   INIDISP


    // Clear NMI flag
    lda.w   RDNMI
    // Enable NMI
    lda.b   #NMITIMEN.vBlank
    sta.w   NMITIMEN


    jsr     TestSetup

    MainLoop:
        wai
        TextBuffer.VBlank()

        // Wait until start of VBlank
        // to make the test output consistent
        wai

        jsr     MeasureIpl


        // Output test results

        TextBuffer.PrintStringLiteral("Test 0x")

        inc.b   testCounter

        lda.b   testCounter
        jsr     TextBuffer.PrintHexSpace_8A

        TextBuffer.PrintStringLiteral("  0x")

        lda.b   test_nVBlanks
        jsr     TextBuffer.PrintHexSpace_8A

        TextBuffer.PrintStringLiteral("VBlanks\n")

        ldx.w   TextBuffer.cursorIndex
        cpx.w   #24 * 32
        bcc     +
            TextBuffer.SetCursor(0, 3)
        +

        jmp     MainLoop
}


rodata(rodata0)
Palette:
    // BG1 palette
    dw  ToPalette(0, 0, 0)
    dw  ToPalette(31, 31, 31)

constant Palette.size = pc() - Palette


rodata(rodata1)
DataToTransfer:
    variable _i = 0
    while _i < 256 {
        fill 128, _i
        _i = _i + 1
    }
constant DataToTransfer.size = pc() - DataToTransfer

assert(DataToTransfer.size == TRANSFER_SIZE)

finalizeMemory()

