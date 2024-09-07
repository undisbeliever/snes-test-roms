// This test uses an IRQ interrupt to delay the start of the DMA crash test by one scanline in an
// attempt to get an sd2snes and a Quickdev16 RAM cart to start the test at the same horizontal
// position.
//
// I was not able to eliminate the test-start jitter, it has been reduced from 10 dots to 3 dots.
//
//
// SPDX-FileCopyrightText: © 2023 Marcus Rowe <undisbeliever@gmail.com>
// SPDX-License-Identifier: Zlib
//
// Copyright © 2023 Marcus Rowe <undisbeliever@gmail.com>
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


evaluate _dtl = DMA_TRANSFER_LENGTH

define   ROM_NAME = "QUICK DMA CRASH IRQ {_dtl}"
constant VERSION = 3

define USES_IRQ_INTERRUPTS


include "_quick-model-1-dma-crash-test.inc"


// DB = 0
// SP = 0x01??
// d = 0
// i = 1
// e = 1
// a8
// i8
seek(0x8000)
function ResetHandler {
    clc
    xce

    rep     #$10
// i16

    ldx.w   #1
    stx.w   VTIME

    ldx.w   #23
    stx.w   HTIME

    lda.b   #NMITIMEN.vCounter | NMITIMEN.hCounter
    sta.w   NMITIMEN

    // required nop
    nop

    cli

    wai
}



// DP = 0
// DB = 0
// d = 0
seek(0x9000)
function IrqHandler {
    QuickDmaTest(DMA_TRANSFER_LENGTH)
}



seek(0xE000)
HdmaTable:
namespace HdmaTable {
    // HDMA table to CGRAM (2 registers write twice)
    // (use a different HDMA gradient then the `_test-no-irq-delay.inc` tests)

    variable _sl = 0

    while _sl < DISPLAY_HEIGHT {
        db  0x80 | 0x7f     // HDMA repeat mode

        variable _i = 0
        while _i < 0x7f {
            evaluate c = (_sl / 2 + 32 + 4) % 64
            if {c} > 31 {
                evaluate c = 63 - {c}
            }
            _sl = _sl + 1

            dw  0           // CGADD
            dw  {c} << 5    // CGDATA

            _i = _i + 1
        }
    }

    db 0
}


