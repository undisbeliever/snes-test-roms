// This test tests what happens when the NMITIMEN autojoy enable flag
// is cleared shortly after HVBJOY reports autojoy active.
//
// After the autojoy-enable-flag is cleared, this test will manually
// read the joypad using JOYSER0 (without latching) and print the
// JOY1 register and JOYSER0 manual read.
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
define ROM_NAME = "CLR AUTOJOY AFTER AJ"
define TEST_NAME = "Clear autojoy after HVBJOY\nreports autojoy active test"
define TEST_INSTRUCTIONS = "Hold B on controller 1"
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


constant TB_RESULTS_XPOS       = 9

constant TB_RESULTS_YPOS       = 10
constant TB_RESULTS_MAX_YPOS   = TB_RESULTS_YPOS + 14

constant TB_HEADING_YPOS       = TB_RESULTS_YPOS - 2


include "../../reset_handler.inc"
include "../../break_handler.inc"
include "../../dma_forceblank.inc"
include "../../textbuffer.inc"

// No VBlank interrupts
constant NmiHandler = BreakHandler


// zero-page temporary word variables (used by TextBuffer)
allocate(zpTmp0, zeropage, 2)

// zero-page temporary far pointer (used by TextBuffer)
allocate(zpTmpPtr, zeropage, 3)


// Test variables
allocate(testRow,    zeropage, 2)
allocate(manualRead, zeropage, 2)



// DB = 0x80
a8()
i16()
code()
function SetupTest {
    TextBuffer.SetCursor(0, 0)
    TextBuffer.PrintString(TitleAndVersionStr)

    TextBuffer.SetCursor(TB_RESULTS_XPOS, TB_HEADING_YPOS)
    TextBuffer.PrintStringLiteral("JOY1 JOYSER0")

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

    sep     #$20
a8()

    lda.b   #NMITIMEN.autoJoy

    // Enable autojoy
    sta.b   NMITIMEN

    // Wait until start of auto-joy
    -
        assert(NMITIMEN.autoJoy == HVBJOY.autoJoy)
        bit.b   HVBJOY
        beq     -

    // Delay determined experimentally.
    //
    // On my 1-CHIP SFC:
    //  * 156 m-cycles = No `0008 1000`
    //  * 158 m-cycles = Occasionally outputs `0008 1000`, sometimes `0001 0001`
    //  * 160 m-cycles = Occasionally outputs `0008 1000`, lots of `0001 0001`
    //  * 162 m-cycles = Lots of `0001 0001`, I did not see any `0008 1000`

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
    nop                 // 12 m-cycles
    bit.w   manualRead  // 26 m-cycles


    // Disable auto-joy
    stz.b   NMITIMEN


    // Wait until autojoy normally ends
    ldx.w   #600
    -
        dex
        bne     -

    pld
// D = 0

    // Read 16 bits from JOYSER0
    // Manual reading code from the SNESDEV wiki
    // https://snes.nesdev.org/wiki/Controller_reading#Manual_controller_reading
    lda.b   #1
    sta.b   manualRead
    stz.b   manualRead + 1
    -
        lda.w   JOYSER0
        lsr
        rol.b   manualRead
        rol.b   manualRead + 1
        bcc     -


PrintResults:
    ldy.b   testRow
    cpy.w   #TB_RESULTS_MAX_YPOS
    bcc     +
        ldy.w   #TB_RESULTS_YPOS - 1
    +
    iny
    sty.b   testRow

    ldx.w   #TB_RESULTS_XPOS
    jsr     TextBuffer.SetCursor

    ldy.w   JOY1
    jsr     TextBuffer.PrintHexSpace_16Y

    ldy.b   manualRead
    jsr     TextBuffer.PrintHexSpace_16Y


    // Transfer text buffer to VRAM

    lda.b   #INIDISP.force | 0x0f
    sta.w   INIDISP

    TextBuffer.VBlank()

    lda.b   #0x0f
    sta.w   INIDISP

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

