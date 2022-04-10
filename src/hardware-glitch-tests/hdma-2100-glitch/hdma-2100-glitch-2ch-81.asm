// Tests if writing to $2100 using HDMA after a previous HDMA channel has
// written data would glitch sprites.
//
//
// You may need to reset your console a few times for the glitch to appear.
//
// Copyright (c) 2021, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define ROM_NAME = "HDMA 2100 2CH 81 TEST"
define VERSION = 1


// REQUIRES: 8 bit A, 16 bit Index, DB access registers
macro SetupHdma() {
    assert8a()
    assert16i()

    stz.w   HDMAEN


    lda.b   #DMAP.direction.toPpu | DMAP.addressing.absolute | DMAP.transfer.one
    sta.w   DMAP6

    lda.b   #BGMODE
    sta.w   BBAD6

    ldx.w   #HdmaTable_bgmode
    stx.w   A1T6

    lda.b   #HdmaTable_bgmode >> 16
    sta.w   A1B6



    lda.b   #DMAP.direction.toPpu | DMAP.addressing.absolute | DMAP.transfer.one
    sta.w   DMAP7

    lda.b   #0x00
    sta.w   BBAD7

    ldx.w   #HdmaTable_inidisp
    stx.w   A1T7

    lda.b   #HdmaTable_inidisp >> 16
    sta.w   A1B7


    lda.b   #HDMAEN.dma6 | HDMAEN.dma7
    sta.w   HDMAEN
}


include "glitch-test.inc"


code()
HdmaTable_bgmode:
    variable n = 0
    while n < 256 {
        db  1
            // If bit 7 is set then this table causes a glitch.
            // It doesn't matter what the value or target register is, if bit 7 is set, it can glitch.
            db  0x81

        n = n + 1
    }

    db  0


code()
HdmaTable_inidisp:
    variable n = 0
    while n < 256 {
        db  1
            db  0x0f

        db  1
            db  0x08

        n = n + 1
    }

    db  0


finalizeMemory()

