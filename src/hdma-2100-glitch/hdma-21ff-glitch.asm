// Tests if writing to $21ff using HDMA glitches sprites.
//
// You may need to reset your console a few times for the glitch to appear.
//
// Copyright (c) 2021, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define ROM_NAME = "HDMA 21ff GLITCH TEST"
define VERSION = 2


// REQUIRES: 8 bit A, 16 bit Index, DB access registers
macro SetupHdma() {
    assert8a()
    assert16i()

    stz.w   HDMAEN


    lda.b   #DMAP.direction.toPpu | DMAP.addressing.absolute | DMAP.transfer.one
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
            //  21ff
            db  0xff

        n = n + 1
    }

    db  0


finalizeMemory()

