// S-CPU-A hardware DMA bug test
// =============================
//
// Copyright (c) 2021, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define mChannel = 0
define hChannel = 1

// Using HDMA to transfer two bytes to 0x21ff & 0x2100
// (BBAD is not 0x00 and the bug is no-longer triggered)
evaluate hdma_dmap = 0x01 // DMAP.direction.toPpu | DMAP.addressing.absolute | DMAP.transfer.two
evaluate hdma_bbad = 0xff


include "dma-test.inc"


variable sv_counter = 0
macro sv() {
    db  sv_counter ? 15 : 8

    sv_counter = !sv_counter
}


HdmaTable:
    variable n = 0
    while n < 128 {
        db  2
            db  0 ; sv()

        n = n + 1
    }

    db  0


finalizeMemory()

