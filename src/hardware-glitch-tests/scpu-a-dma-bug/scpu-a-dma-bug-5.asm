// S-CPU-A hardware DMA bug test
// =============================
//
// Copyright (c) 2021, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define mChannel = 0
define hChannel = 1


include "dma-test.inc"


variable sv_counter = 0
macro sv() {
    db  sv_counter ? 15 : 8

    sv_counter = !sv_counter
}


// This HDMA table triggers the bug every 5th or 10th scanline
HdmaTable:
    variable n = 0
    while n < 128 {
        db  5
            sv()

        n = n + 1
    }

    db  0


finalizeMemory()

