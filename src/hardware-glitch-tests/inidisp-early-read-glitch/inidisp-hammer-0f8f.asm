// Constantly writes 0x0f8f to $20ff (0x8f to $20ff, 0x0f to $2100)
//
// SPDX-FileCopyrightText: © 2021 Marcus Rowe <undisbeliever@gmail.com>
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define ROM_NAME = "INIDISP HAMMER TEST"
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


    MainLoop:
        // Adding a delay here the sprite glitch more interesting
        ldx.w   #0x0f8f
        stx.w   INIDISP - 1

        bra     MainLoop
}

