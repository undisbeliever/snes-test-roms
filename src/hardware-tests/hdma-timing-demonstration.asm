// A test used to create a HDMA timing diagram for the SNESdev wiki.
//
// To recreate the diagram you will need to run the test in Mesen, then:
//  * Open the Event Viewer.
//  * Open the Debugger.
//  * Create a read breakpoint for $80A000 to $80A0FF
//  * Enable "Mark on Event Viewer" on the breakpoint.
//  * Unpause emulation.
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
define ROM_NAME = "HDMA TIMING"
define VERSION = 1

architecture wdc65816-strict

include "../common.inc"

createCodeBlock(code,       0x808000, 0x808fff)

createDataBlock(tableBank,  0x80a000, 0x80afff)

createRamBlock(stack,       0x7e1f80, 0x7e1fff)

include "../reset_handler.inc"
include "../break_handler.inc"
include "../dma_forceblank.inc"


// This demo does not use VBlank Interrupts.
constant NmiHandler = BreakHandler


a8()
i16()
// DB = 0x80
// DP = 0
code()
function Main {
    lda.b   #INIDISP.force | 0
    sta.w   INIDISP


    // Setup HDMA registers
    //
    // Using 2 HDMA channels to show that the line-counter is decremented/read after
    // the HDMA transfers are completed.

    // Setup an HDMA to CGADD
    lda.b   #DMAP.direction.toPpu | DMAP.transfer.one
    sta.w   DMAP0

    lda.b   #CGADD
    sta.w   BBAD0

    ldx.w   #CgaddTable
    lda.b   #CgaddTable >> 16
    stx.w   A1T0
    sta.w   A1B0

    // Setup an HDMA to CGDATA
    lda.b   #DMAP.direction.toPpu | DMAP.transfer.writeTwice
    sta.w   DMAP1

    lda.b   #CGDATA
    sta.w   BBAD1

    ldx.w   #CgdataTable
    lda.b   #CgdataTable >> 16
    stx.w   A1T1
    sta.w   A1B1


    // Wait until VBlank starts
    assert(HVBJOY.vBlank == 0x80)
    -
        lda.w   HVBJOY
        bmi     -

    // Enable HDMA
    lda.b   #HDMAEN.dma0 | HDMAEN.dma1
    sta.w   HDMAEN


    lda.b   #15
    sta.w   INIDISP


    SpinLoop:
        wai
        bra     SpinLoop
}



rodata(tableBank)

// HDMA Table to CGADD (one register HDMA pattern)
CgaddTable:
    variable _i = 0
    while _i < 11 {
        db  16
            db  0
        _i = _i + 1
    }
    db 0


// HDMA Table to CGDATA (one register HDMA pattern)
CgdataTable:
    variable _i = 0
    while _i < 11 {
        variable c = 31 - (_i * 3)
        db  16
            dw  ToPalette(c, c, c)
        _i = _i + 1
    }


