// Enable auto joypad read late test.
//
// This test uses IRQ to enable auto-joypad read (0 to 1 transition for NMITIMEN.bit0)
// at various H/V positions and prints:
//  * How many times the auto-joy flag is 1
//  * The output of the JOY1 register.
//
// Be aware, the VTIME/HTIME is the time of the IRQ interrupt, it is not the position of the
// NMITIMEN write.
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
define ROM_NAME = "EN AUTOJOY LATE TEST"

define TEST_NAME = "Enable AUTOJOY late test"
define TEST_INSTRUCTIONS = "Press and hold Joypad 1"
define VERSION = 1

define USES_IRQ_INTERRUPTS

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



constant TB_TEST_Y              = 10

constant TB_TEST_X_TIME         = 1
constant TB_TEST_X_DATA         = 16


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


allocate(testIndex, zeropage, 2)

allocate(tmpCounter, zeropage, 2)


rodata(rodata0)
TestData:
namespace TestData {
    constant VTime = TestData;
    constant HTime = TestData + 2;
    constant YPos  = TestData + 4;

    constant BYTES_PER_ROW = 6


    variable _n_rows = 0
    macro _TestRow(vtime, htime) {
        dw  {vtime}, {htime}, TB_TEST_Y + _n_rows
        _n_rows = _n_rows + 1
    }
    macro _Scanlines(vtime) {
        // Manually tweaked to be somewhere in the middle of the auto-joypad-clock
        // (tested on my 2/1/3 SFC console, not the Mesen event viewer)
        _TestRow({vtime},  20)
        _TestRow({vtime}, 200)
    }

    constant DATA_VERSION = 1

    _Scanlines(224)
    _Scanlines(225)
    _Scanlines(226)
    _Scanlines(227)
    _Scanlines(228)

    constant N_TESTS = _n_rows
    constant END_INDEX = N_TESTS * BYTES_PER_ROW
}



// DB = 0x80
a8()
i16()
code()
function SetupTest {
    TextBuffer.SetCursor(0, 0)
    TextBuffer.PrintString(TitleAndVersionStr)

    TextBuffer.SetCursor(TB_TEST_X_TIME - 1, TB_TEST_Y - 3)
    TextBuffer.PrintStringLiteral("  IRQ IRQ")
    TextBuffer.SetCursor(TB_TEST_X_TIME - 1, TB_TEST_Y - 2)
    TextBuffer.PrintStringLiteral("VTIME HTIME")

    TextBuffer.SetCursor(TB_TEST_X_DATA - 2, TB_TEST_Y - 3)
    TextBuffer.PrintStringLiteral("HVBJOY")

    TextBuffer.SetCursor(TB_TEST_X_DATA - 1, TB_TEST_Y - 2)
    TextBuffer.PrintStringLiteral("COUNT JOY1")

    ldx.w   #0
    -
        stx.b   testIndex

        lda.w   TestData.YPos,x
        tay
        ldx.w   #TB_TEST_X_TIME
        jsr     TextBuffer.SetCursor

        ldx.b   testIndex
        ldy.w   TestData.VTime,x
        jsr     TextBuffer.PrintHexSpace_16Y

        ldx.b   testIndex
        ldy.w   TestData.HTime,x
        jsr     TextBuffer.PrintHexSpace_16Y

        assert(TestData.END_INDEX < 0xff)
        tdc
        lda.b   testIndex
        clc
        adc.b   #TestData.BYTES_PER_ROW
        tax
        cmp.b   #TestData.END_INDEX
        bne     -

    rts
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

    phd
    pea $4200
    pld
// D = $4200


    // Enable IRQ, Disable autojoy
    stz.b   NMITIMEN

    assert(pc() >> 16 == TestData >> 16)
    ldy.w   TestData.HTime,x
    sty.b   HTIME

    ldy.w   TestData.VTime,x
    sty.b   VTIME

    lda.b   #NMITIMEN.vCounter | NMITIMEN.hCounter
    bit.b   TIMEUP      // clear IRQ flag
    sta.b   NMITIMEN

    // Enable IRQ interrupts
    cli


    // Setup read-loop registers
    ldx.w   #500
    ldy.w   #0

    // Enable autojoy in the IRQ interrupt
    lda.b   #NMITIMEN.autoJoy
    wai

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

    sty.b   tmpCounter


    // Update text buffer
    ldx.w   testIndex
    ldy.w   TestData.YPos,x
    ldx.w   #TB_TEST_X_DATA
    jsr     TextBuffer.SetCursor

    ldy.b   tmpCounter
    jsr     TextBuffer.PrintHexSpace_16Y

    ldy.w   JOY1
    jsr     TextBuffer.PrintHexSpace_16Y


    // Transfer text buffer to VRAM
    lda.b   #INIDISP.force | 0x0f
    sta.w   INIDISP

    TextBuffer.VBlank()

    lda.b   #0x0f
    sta.w   INIDISP


    rts
}


// Assumes IRQ interrupt set in DoTest
//
// A = NMITIMEN.autoJoy
// DB = 80
// D = $4200
a8()
iu()
code()
function IrqHandler {
    sta.b   NMITIMEN

    // Clear IRQ flag
    bit.b   TIMEUP

    rti
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
    a16()
    i16()
        lda.b   testIndex
        clc
        adc.w   #TestData.BYTES_PER_ROW
        cmp.w   #TestData.END_INDEX
        bcc     +
            lda.w   #0
        +
        sta.b   testIndex
        tax

        sep     #$20
    a8()
        jsr     DoTest

        bra     MainLoop
}


rodata(rodata0)
TitleAndVersionStr:
evaluate TEST_VERSION = DoTest.TEST_VERSION
evaluate DATA_VERSION = TestData.DATA_VERSION
    db  "\n", {TEST_NAME}, "\nversion {TEST_VERSION}-{DATA_VERSION}", "\n\n", {TEST_INSTRUCTIONS}, 0

assert({VERSION} == {TEST_VERSION} + {DATA_VERSION} - 1)

namespace Resources {

rodata(rodata0)
Palette:
    dw  ToPalette(0, 0, 0)
    dw  ToPalette(31, 31, 31)
constant Palette.size = pc() - Palette
}

finalizeMemory()

