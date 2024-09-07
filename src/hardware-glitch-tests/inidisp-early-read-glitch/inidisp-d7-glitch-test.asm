// Tests if writing to INIDISP when the previous value on the data bus
// has bit 7 set would cause a sprite glitch.
//
// This is an interactive test:
//      * if A/B/X/Y button is not pressed then the test will write
//        0x80 to $20ff and `0x0f` to INIDISP.
//
//      * if A/B/X/Y button is pressed then the test will write
//        0x00 to $20ff and `0x0f` to INIDISP.
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


define ROM_NAME = "INIDISP D7 GLITCH TEST"
define VERSION = 1

include "_inidisp-hammer-common.inc"


au()
iu()
code()
function Main {
    rep     #$30
    sep     #$20
a8()
i16()
    sei

    SetupPpu()

    lda.b   #0x0f
    sta.w   INIDISP

    lda.b   #NMITIMEN.autoJoy
    sta.w   NMITIMEN


    MainLoop:
        // Check if a button is pressed
        // There is not need to check `HVBJOY`, bad `JOY1` reads affect non-visible scanlines.
        lda.b   #JOYH.b | JOYH.y
        bit.w   JOY1H
        bne     ButtonPressed

        lda.b   #JOYL.a | JOYL.x
        bit.w   JOY1L
        bne     ButtonPressed
            // No button pressed, write to 2100 with data bus b7 set
            ldx.w   #0x0f80

            bra     EndIf

        ButtonPressed:
            // No button pressed, write to 2100 with data bus b7 clear
            ldx.w   #0x0f00

        EndIf:


        // Wait until hBlank
        -
            assert(HVBJOY.hBlank == 0x40)
            bit.w   HVBJOY
            bvc     -


        stx.w   INIDISP - 1


        // Wait until the end of hBlank
        -
            assert(HVBJOY.hBlank == 0x40)
            bit.w   HVBJOY
            bvs     -


        bra     MainLoop
}

