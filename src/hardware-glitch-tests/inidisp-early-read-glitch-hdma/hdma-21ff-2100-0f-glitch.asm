// Tests if writing to $21ff and $2100 using the same HDMA channel glitches sprites.
//
// You may need to reset your console a few times for the glitch to appear.
//
// SPDX-FileCopyrightText: © 2021 Marcus Rowe <undisbeliever@gmail.com>
// SPDX-License-Identifier: Zlib
//
// Copyright © 2021 Marcus Rowe <undisbeliever@gmail.com>
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


define ROM_NAME = "HDMA 21ff 2100 0F GLITCH"
define VERSION = 2


// REQUIRES: 8 bit A, 16 bit Index, DB access registers
macro SetupHdma() {
    assert8a()
    assert16i()

    stz.w   HDMAEN


    lda.b   #DMAP.direction.toPpu | DMAP.addressing.absolute | DMAP.transfer.two
    sta.w   DMAP0

    lda.b   #0xff
    sta.w   BBAD0

    ldx.w   #HdmaTable
    stx.w   A1T0

    lda.b   #HdmaTable >> 16
    sta.w   A1B0


    lda.b   #HDMAEN.dma0
    sta.w   HDMAEN
}


include "glitch-test.inc"


code()
HdmaTable:
    variable n = 0
    while n < 256 {
        db  1
            //  21ff  2100
            db  0x0f, 0x0f

        n = n + 1
    }

    db  0


finalizeMemory()

