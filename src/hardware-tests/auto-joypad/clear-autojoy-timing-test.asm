// Test ROM that determines when the HVBJOY auto-joy active flag is cleared
// when auto-joy is disabled in the middle of auto-joy.
//
// This test will:
//  1. Wait until HVBJOY reports automatic joypad read active
//  2. Delay for N master cycles using `sta long` instructions
//  3. Repeatedly poll HVBJOY until it reports auto-joy not active
//  4. Print the number of times HVBJOY reported auto-joy active.
//     A value of 0xff is invalid.
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
define ROM_NAME = "CLR AUTOJOY TIMING"
define TEST_NAME = "Clear AUTOJOY enable flag\ntiming test"
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


constant TB_DELAY_XPOS = 4
constant TB_RAW_XPOS   = 14
constant TB_MIN_XPOS   = TB_RAW_XPOS + 4
constant TB_MAX_XPOS   = TB_MIN_XPOS + 4

constant TB_LABEL_YPOS      = 8
constant TB_DATA_YPOS       = TB_LABEL_YPOS + 2


constant TEST_DATA_VERSION = 1
constant N_TESTS = 7
array[N_TESTS] TestDelays = 0, 64, 128, 192, 256, 384, 512


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


allocate(dummyStore, zeropage, 1)

allocate(tmpCounter, zeropage, 1)

allocate(minCounters, zeropage, N_TESTS)
allocate(maxCounters, zeropage, N_TESTS)


// DB = 0x80
a8()
i16()
code()
function SetupTest {
    TextBuffer.SetCursor(0, 0)
    TextBuffer.PrintString(TitleAndVersionStr)


    TextBuffer.SetCursor(TB_DELAY_XPOS, TB_LABEL_YPOS)
    TextBuffer.PrintStringLiteral("Delay")

    evaluate _i = 0
    while {_i} < N_TESTS {
        evaluate _delay = TestDelays[{_i}]

        TextBuffer.SetCursor(TB_DELAY_XPOS, TB_DATA_YPOS + {_i} * 2)
        TextBuffer.PrintStringLiteral("{_delay}")

        evaluate _i = {_i} + 1
    }


    TextBuffer.SetCursor(TB_RAW_XPOS - 1, TB_LABEL_YPOS - 1)
    TextBuffer.PrintStringLiteral("HVBJOY polls")

    TextBuffer.SetCursor(TB_RAW_XPOS - 1, TB_LABEL_YPOS)
    TextBuffer.PrintStringLiteral("RAW MIN MAX")

    ldx.w   #N_TESTS - 1
    -
        lda.b   #0xff
        sta.b   minCounters,x
        stz.b   maxCounters,x
        dex
        bpl     -

    rts
}


// DB = $80
// D = 0
inline _GenerateTest(evaluate TestNumber, evaluate DelayUntilClear, evaluate TbYpos) {
    function Test{TestNumber} {
        // MUST Update this constant if the test changes
        constant TEST_VERSION = 1

        constant N_HVBJOY_TESTS = 31

        assert({TestNumber} < N_TESTS)
        constant _minCounter = minCounters + {TestNumber}
        constant _maxCounter = maxCounters + {TestNumber}


        phd
        pea     $4200
        pld
    // D = $4200

        // Enable autojoy
        lda.b   #NMITIMEN.autoJoy
        sta.b   NMITIMEN

        // Wait until autojoy is active
        LoopUntilAutojoy:
            assert(NMITIMEN.autoJoy == HVBJOY.autoJoy)
            bit.b   HVBJOY
            beq     LoopUntilAutojoy


        // Delay for `DelayUntilClear` master cycles
        assert({DelayUntilClear} % 32 == 0)
        constant N_DELAY_LOOPS = {DelayUntilClear} / 32
        evaluate _i = 0
        while {_i} < N_DELAY_LOOPS {
            // 4 FastROM, 1 SlowROM cycle = 32 master cycles
            sta.l   dummyStore
            evaluate _i = {_i} + 1
        }

    ClearAutoJoyEnableFlag:
        stz.b   NMITIMEN

        // 30 master cycles between HVBJOY polls (18 for `bit.b fast`, 12 for `beq` not taken)
        // 70 master cycles if there is also a Work-RAM refresh
        // -12 master cycles for `beq` of the last poll
        // +12 master cycles for `beq LoopUntilAutojoy` branch above not taken
        // +18 master cycles for `stz.b NMITIMEN`
        evaluate _i = 1
        while {_i} <= N_HVBJOY_TESTS {
            bit.b   HVBJOY
            beq     InProgressFlagClear_{_i}
            evaluate _i = {_i} + 1
        }

        lda.b   #0xff
        bra     PrintResults

        evaluate _i = 1
        while {_i} <= N_HVBJOY_TESTS {
        InProgressFlagClear_{_i}:
            lda.b   #{_i}
            bra     PrintResults
            evaluate _i = {_i} + 1
        }

    PrintResults:
        pld
    // D = 0

        // A = number of times HVBJOY was read
        sta.b   tmpCounter

        cmp.b   _minCounter
        bcs     +
            sta.b   _minCounter
        +

        cmp.b   _maxCounter
        bcc     +
            sta.b   _maxCounter
        +

        TextBuffer.SetCursor(TB_RAW_XPOS, {TbYpos})
        lda.b   tmpCounter
        jsr     TextBuffer.PrintHexSpace_8A

        TextBuffer.SetCursor(TB_MIN_XPOS, {TbYpos})
        lda.b   _minCounter
        jsr     TextBuffer.PrintHexSpace_8A

        TextBuffer.SetCursor(TB_MAX_XPOS, {TbYpos})
        lda.b   _maxCounter
        jsr     TextBuffer.PrintHexSpace_8A


        // Transfer text buffer to VRAM

        lda.b   #INIDISP.force | 0x0f
        sta.w   INIDISP

        TextBuffer.VBlank()

        lda.b   #0x0f
        sta.w   INIDISP

        rts
    }
}


variable _i = 0
while _i < N_TESTS {
    _GenerateTest(_i, TestDelays[_i], TB_DATA_YPOS + _i * 2)

    _i = _i + 1
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

        evaluate _i = 0
        while {_i} < N_TESTS {
            jsr     Test{_i}
            evaluate _i = {_i} + 1
        }

        jmp     MainLoop
}


rodata(rodata0)
TitleAndVersionStr:
evaluate TEST_VERSION = Test1.TEST_VERSION
evaluate TEST_DATA_VERSION = TEST_DATA_VERSION
    db  "\n", {TEST_NAME}, "\n\nversion {TEST_VERSION}-{TEST_DATA_VERSION}", 0

assert({VERSION} == {TEST_VERSION} + TEST_DATA_VERSION - 1)

namespace Resources {

rodata(rodata0)
Palette:
    dw  ToPalette(0, 0, 0)
    dw  ToPalette(31, 31, 31)
constant Palette.size = pc() - Palette
}

finalizeMemory()

