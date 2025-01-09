// Blipping autojoy enable latches joypad twice test.
//
// This test is used to determine if blipping (0 -> 1 -> 0) the NMITIMEN auto-joypad enable flag
// during the first auto-joypad clock will:
//  * Clear the joypad latch pin when NMITIMEN auto-joypad is disabled.
//  * Latch the joypad a second time when NMITIMEN auto-joypad is re-enabled.
//
// This is done by:
//  * Waiting until HVBJOY reports auto-joypad is active.
//  * Clear the NMITIMEN auto-joypad flag.
//  * Manually read the controller twice using JOYSER0.
//  * Enable the NMITIMEN auto-joypad flag before the end first auto-joy clock
//    (128 master-cycles after the HVBJOY auto-joypad active flag set).
//
// Two manual JOYSER0 reads are required to prove the joypad latch pin is cleared when NMITIMEN
// auto-joypad is disabled.
//
// Test results:
//  * The first two bits are the manual read
//  * The final 16 bits are the automatic-joypad read
//
// If automatic joypad read latches (strobes) the joypad a second time, the two manual reads
// should match the two most-significant bits of the auto-joy read and the auto-joy read should be
// uncorrupted.
//
// CAUTION:
//    This test is unable to meet the timing window required for the test on every test iteration.
//
//    I'm theorizing the joypad is not latched a second time if the `NMITIMEN = 1` write is too late.
//
//
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


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "BLIP AJ LATCHES JP"
define TEST_NAME = "Blipping AUTOJOY enable\nlatches joypad twice test"
define TEST_INSTRUCTIONS = "Hold B, then Y, then SELECT"
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


constant TB_RESULTS_XPOS       = 4

constant TB_RESULTS_YPOS       = 9
constant TB_RESULTS_MAX_YPOS   = TB_RESULTS_YPOS + 15


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


// Used to print JOY1 bits
allocate(tmpWord,    zeropage, 2)
allocate(tmpCounter, zeropage, 1)


// Test variables
allocate(testRow, zeropage, 2)

allocate(firstRead, zeropage, 1)
allocate(secondRead, zeropage, 1)



// DB = 0x80
a8()
i16()
code()
function SetupTest {
    TextBuffer.SetCursor(0, 0)
    TextBuffer.PrintString(TitleAndVersionStr)

    ldy.w   #0xffff
    sty.b   testRow

    rts
}


function Test {
    // MUST Update this constant if the test changes
    constant TEST_VERSION = 1

    phd
    pea     $4200
    pld
// D = $4200

    sep     #$30
a8()
i8()

    stz.w   JOYSER0

    lda.b   #NMITIMEN.autoJoy

LoopUntilAutojoy:
    // Enable autojoy
    sta.w   NMITIMEN

    // Wait until start of auto-joy
    -
        assert(NMITIMEN.autoJoy == HVBJOY.autoJoy)
        bit.b   HVBJOY
        beq     -


    // TIMING:
    // This test should complete 128 master-cycles after HVBJOY auto-joy active flag is set.
    // There is not enough CPU time to meet this deadline on every test iteration.
    // I'm guessing half of the test iterations meet the deadline.

StartTest:                          // 12-m-cycles for `beq -` above not taken
    // Disable auto-joy
    stz.b   NMITIMEN                // 18 m-cycles

    // Manually read the joypad twice
    ldx.w   JOYSER0                 // 30 m-cycles
    ldy.w   JOYSER0                 // 30 m-cycles

    // Enable auto-joy
    sta.b   NMITIMEN                // 18 m-cycles
TestOver:

    // Save results
    stx.w   firstRead
    sty.w   secondRead


    // Wait until autojoy has finished
    lda.b   #HVBJOY.autoJoy
    -
        bit.b   HVBJOY
        bne     -


PrintResults:
    rep     #$10
i16()
    pld
// D = 0

    ldy.b   testRow
    cpy.w   #TB_RESULTS_MAX_YPOS
    bcc     +
        ldy.w   #TB_RESULTS_YPOS - 1
    +
    iny
    sty.b   testRow

    ldx.w   #TB_RESULTS_XPOS
    jsr     TextBuffer.SetCursor


    lda.b   firstRead
    lsr
    jsr     PrintBit

    lda.b   secondRead
    lsr
    jsr     PrintBit


    TextBuffer.PrintStringLiteral("  ")

    ldx.w   JOY1
    stx.b   tmpWord

    lda.b   #16
    sta.b   tmpCounter

    -
        asl.b   tmpWord
        rol.b   tmpWord + 1
        jsr     PrintBit
        dec.b   tmpCounter
        bne     -


    // Transfer text buffer to VRAM

    lda.b   #INIDISP.force | 0x0f
    sta.w   INIDISP

    TextBuffer.VBlank()

    lda.b   #0x0f
    sta.w   INIDISP

    rts
}


BitString_0:
    db  "0", 0

BitString_1:
    db  "1", 0


// IN: carry = bit
//
// DB = 0x80
a8()
i16()
code()
function PrintBit {
    assert(BitString_0 >> 16 == BitString_1 >> 16)

    lda.b   #BitString_0 >> 16
    ldx.w   #BitString_0
    bcc     +
        ldx.w   #BitString_1
    +
    jmp     TextBuffer.PrintString
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

        jsr     Test

        jmp     MainLoop
}


rodata(rodata0)
TitleAndVersionStr:
evaluate TEST_VERSION = Test.TEST_VERSION
    db  "\n", {TEST_NAME}, "\n\nversion {TEST_VERSION}\n\n", {TEST_INSTRUCTIONS}, 0

assert({VERSION} == {TEST_VERSION})

namespace Resources {

rodata(rodata0)
Palette:
    dw  ToPalette(0, 0, 0)
    dw  ToPalette(31, 31, 31)
constant Palette.size = pc() - Palette
}

finalizeMemory()

