// Constantly writes 0x0f to INIDISP
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


    lda.b   #0x0f

    MainLoop:
        sta.w   INIDISP

        bra     MainLoop
}

