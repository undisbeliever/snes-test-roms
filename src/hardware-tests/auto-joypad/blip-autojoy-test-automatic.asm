// Automatic blip auto joypad enable flag test.
//
// This test ROM is designed to see what happens if auto-joypad is disabled, then
// quickly re-enabled shortly after auto-joypad read stats.
//
// For 19 different wait values this test:
//  * Waits until auto-joypad active flag is set
//  * Waits X fastROM cycles
//  * Disables auto-joypad enable (NMITIMEN = 0)
//  * Enables auto-joypad (NMITIMEN = 1) 18 or 58 m-cycles later
//  * Reads HVBJOY.bit0 in a loop to see if the auto-joypad enable flag is set
//  * Prints the results
//
// Test Results:
//  * Min HVBJOY.0 counter:
//    The minimum number of times HVBJOY.bit0 was read in the loop when HVBJOY.bit0 was 1 at least one.
//
//  * Row 1:   At least 1 read occurred in the column
//  * Row 2:   At least 1 no-read occurred in the column
//  * Rows 3+: Raw Read/No-read data
//
//
// SPDX-FileCopyrightText: © 2024 Marcus Rowe <undisbeliever@gmail.com>
// SPDX-License-Identifier: Zlib
//
// Copyright © 2024 Marcus Rowe <undisbeliever@gmail.com>
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


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "AUTOJOY BLIP TEST A"
define TEST_NAME = "Automatic AUTOJOY blip test\n(1-0-1 to AUTOJOY enable)"
define VERSION = 1

architecture wdc65816-strict

include "../../common.inc"

createCodeBlock(code,       0x808000, 0x80bfff)
createDataBlock(rodata0,    0x80c000, 0x80ff80)

createRamBlock(zeropage,        0x00,     0xff)
createRamBlock(lowram,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)
createRamBlock(wram7e,      0x7e2000, 0xfeffff)


constant VRAM_BG1_TILES_WADDR = 0x1000
constant VRAM_BG1_MAP_WADDR   = 0x0000

constant VRAM_TEXTBUFFER_MAP_WADDR   = VRAM_BG1_MAP_WADDR
constant VRAM_TEXTBUFFER_TILES_WADDR = VRAM_BG1_TILES_WADDR


constant TB_MIN_READ_COUNTER_XPOS = 22
constant TB_MIN_READ_COUNTER_YPOS = 5

constant TB_TEST_START_X = 4

constant TB_ANY_READ_YPOS       =  7
constant TB_ANY_NO_READ_YPOS    =  8

constant TB_RAW_DATA_YPOS       = 10
constant TB_RAW_DATA_LAST_YPOS  = 25


include "../../reset_handler.inc"
include "../../break_handler.inc"
include "../../dma_forceblank.inc"
include "../../textbuffer.inc"

// No Vblank interrupts
constant NmiHandler = BreakHandler


// zero-page temporary word variables (used by TextBuffer)
allocate(zpTmp0, zeropage, 2)

// zero-page temporary far pointer (used by TextBuffer)
allocate(zpTmpPtr, zeropage, 3)

// minimum non-zero HVBJOY.0 loop counter
allocate(minNonZeroCounter, zeropage, 2)


// Current cursor position
allocate(cursorXPos, zeropage, 2)
allocate(cursorYPos, zeropage, 2)


allocate(tmpCounter, zeropage, 2)


// DB = 0x80
a8()
i16()
code()
function SetupTest {
    TextBuffer.SetCursor(0, 0)
    TextBuffer.PrintString(TitleAndVersionStr)

    TextBuffer.SetCursor(TB_MIN_READ_COUNTER_XPOS - 20, TB_MIN_READ_COUNTER_YPOS)
    TextBuffer.PrintStringLiteral("Min HVBJOY.0 count:")

    ldx.w   #0xffff
    stx.b   cursorYPos

    stx.b   minNonZeroCounter


    rts
}


// TIMING: VBlank
// IN: Y = HVBJOY count
// DB = 0x80
// D unknown
a8()
i16()
code()
function PrintResults {
    sty.b   tmpCounter

    ldx.b   cursorXPos
    ldy.b   cursorYPos
    jsr     TextBuffer.SetCursor

    ldy.b   tmpCounter
    beq     +
        TextBuffer.PrintStringLiteral("R")

        // Updated the any read line
        ldx.b   cursorXPos
        ldy.w   #TB_ANY_READ_YPOS
        jsr     TextBuffer.SetCursor
        TextBuffer.PrintStringLiteral("R")

        bra     ++
    +
        TextBuffer.PrintStringLiteral("-")

        // Updated the any no read line
        ldx.b   cursorXPos
        ldy.w   #TB_ANY_NO_READ_YPOS
        jsr     TextBuffer.SetCursor
        TextBuffer.PrintStringLiteral("-")
    +

    ldy.b   tmpCounter
    beq     +
        cpy.b   minNonZeroCounter
        bcs     +
            sty.b   minNonZeroCounter

            TextBuffer.SetCursor(TB_MIN_READ_COUNTER_XPOS, TB_MIN_READ_COUNTER_YPOS)

            ldy.b   tmpCounter
            jsr     TextBuffer.PrintHexSpace_16Y
    +


    // Transfer text buffer to VRAM
    lda.b   #INIDISP.force | 0x0f
    sta.w   INIDISP

    TextBuffer.VBlank()

    lda.b   #0x0f
    sta.w   INIDISP

    inc.b   cursorXPos

    rts
}


// DB = $80
// D = 0
macro Test(evaluate numberOfFastRomCycles) {
    assert8a()
    assert16i()

    // MUST Update this constant if the test changes
    assert(TEST_VERSION == 1)

    phd
    pea $4200
    pld
// D = $4200

    // Enable autojoy
    lda.b   #NMITIMEN.autoJoy
    sta.b   NMITIMEN


    // Setup read-loop registers
    ldx.w   #200
    ldy.w   #0


    // Wait for the start of autojoy
    assert(NMITIMEN.autoJoy == HVBJOY.autoJoy)
    -
        bit.b   HVBJOY
        beq     -


    // Add fastROM cycles between autojoy-flag set and autojoy enable blip
    variable _c = {numberOfFastRomCycles}
    while _c > 0 {
        if _c == 3 {
            rep #0
            _c = _c - 3
        } else if _c >= 2 {
            nop
            _c = _c - 2
        } else {
            error "invalid numberOfFastRomCycles: {numberOfFastRomCycles}"
            _c = 0
        }
    }

    // Disable then quickly enable auto-joy
    stz.b   NMITIMEN
    sta.b   NMITIMEN

    // Count number of times S-CPU reports autoJoy active
    -
        // X = loop decrementing counter
        // Y = HVBJOY.autoJoy counter
        // A = NMITIMEN.autoJoy
        assert(NMITIMEN.autoJoy == HVBJOY.autoJoy)
        bit.b   HVBJOY
        beq     +
            iny
        +
        dex
        bne     -

    pld
// D = $4200

    jsr     PrintResults
}


// IN: X = testIndex
// DB = 0x80
// D = 0
a8()
i16()
code()
function DoTest {
    // MUST Update this constant if the test changes
    constant TEST_VERSION = 1

    ldy.w   #TB_TEST_START_X
    sty.w   cursorXPos


    // Update cursor position
    ldy.w   cursorYPos
    cpy.w   #TB_RAW_DATA_LAST_YPOS
    bcc     +
        ldy.w   #TB_RAW_DATA_YPOS - 1
    +
    iny
    sty.b   cursorYPos


    // Selected 19 tests per line as it is a prime number
    Test(0)

    inc.b   cursorXPos

    evaluate i = 20
    while {i} < 37 {
        Test({i})
        evaluate i = {i} + 1
    }

    inc.b   cursorXPos

    Test(42)


    rts
}



// DB = 0x80
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

    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Palette)

    jsr     TextBuffer.InitAndTransferToVram

    lda.b   #0xf
    sta.w   INIDISP


    jsr     SetupTest


    MainLoop:
        rep     #$30
        sep     #$20
    a8()
    i16()
        jsr     DoTest

        bra     MainLoop
}


rodata(rodata0)
TitleAndVersionStr:
evaluate TEST_VERSION = DoTest.TEST_VERSION
    db  "\n", {TEST_NAME}, "\nversion {TEST_VERSION}", 0

assert({VERSION} == {TEST_VERSION})

namespace Resources {

rodata(rodata0)
Palette:
    dw  ToPalette(0, 0, 0)
    dw  ToPalette(31, 31, 31)
constant Palette.size = pc() - Palette
}

finalizeMemory()

