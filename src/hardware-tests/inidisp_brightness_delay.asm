// A simple test to demonstrate the brightness delay on a RGB modded 1-chip console.
//
// NOTE: You must disable the *1CHIP transient fixes* and *Brightness limit*
//       settings if you are running this test on an sd2snes.
//
// SPDX-FileCopyrightText: © 2019 Marcus Rowe <undisbeliever@gmail.com>
// SPDX-License-Identifier: Zlib
//
// Copyright © 2019 Marcus Rowe <undisbeliever@gmail.com>
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
define ROM_NAME = "BRIGHTNESS DELAY TEST"
define VERSION = 3

define USES_IRQ_INTERRUPTS


architecture wdc65816-strict

include "../common.inc"

createCodeBlock(code,       0x808000, 0x80ffaf)

createRamBlock(lowram,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)

include "../reset_handler.inc"
include "../break_handler.inc"
include "../nmi_handler.inc"
include "../dma_forceblank.inc"


// The number of scanlines between each brightness test
constant BRIGHTNESS_TEST_HEIGHT = 32


// The horizontal dot position to trigger IRQ
//
// This value is chosen to ensure that:
//  1) The SLHV latch is triggered after h-blank
//  2) The INIDISP store occurs before Work RAM refresh
constant IRQ_X_POS = 339 - 30



au()
iu()
code()
function Main {
    rep     #$30
    sep     #$20
a8()
i16()
    // Setup PPU registers

    lda.b   #INIDISP.force | 0xf
    sta.w   INIDISP


    // Fill CGRAM with white
    stz.w   CGADD

    ldx.w   #512
    lda.b   #0xff
    -
        sta.w   CGDATA
        dex
        bne     -

    lda.b   #0
    sta.w   TM



    // Enable Horizontal IRQ
    ldx.w   #IRQ_X_POS
    stx.w   HTIME

    lda.b   #NMITIMEN.hCounter | NMITIMEN.vBlank
    sta.w   NMITIMEN

    cli


    MainLoop:
        wai
        bra     MainLoop
}


// IRQ ISR
//
// Enable display (at full brightness)
function IrqHandler {
    rep     #$30
a16()
i16()
    phb
    pha
    phx
    phy

    phk
    plb

    sep     #$30
a8()
i8()
    // Latch V Counter
    lda.w   SLHV

    // Read vertical scanline location
    lda.w   OPVCT
    ldx.w   OPVCT
    // A = OPVCT low byte

    // Change brightness when we are on an appropriate scanline
    assertPowerOfTwo(BRIGHTNESS_TEST_HEIGHT)
    sec
    sbc.b   #8
    and.b   #BRIGHTNESS_TEST_HEIGHT - 1
    bne     +
        // Full brightness
        ldx.b   #0xf
        stx.w   INIDISP
        bra     End
    +
    cmp.b   #BRIGHTNESS_TEST_HEIGHT / 2
    bne     +
        // 0 brightness
        stz.w   INIDISP
    +

End:
    lda.w   TIMEUP  // Required to escape IrqHandler

    rep     #$30
a16()
i16()
    ply
    plx
    pla
    plb

    rti
}


finalizeMemory()

