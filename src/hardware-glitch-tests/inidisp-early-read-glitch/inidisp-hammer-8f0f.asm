// Constantly writes 0x8f0f to $20ff (0x0f to $20ff, 0x8f to $2100)
//
// Copyright (c) 2021, Marcus Rowe <undisbeliever@gmail.com>.
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
        // Adding a delay here makes the pattern easier to see on my display
        ldx.w   #0x8f0f
        stx.w   INIDISP - 1

        bra     MainLoop
}

