// S-CPU-A hardware DMA bug test
// =============================
//
// Copyright (c) 2021, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


// I can also trigger this bug with MDMA ch 5, HDMA ch 0
define mChannel = 5
define hChannel = 0


include "dma-test.inc"


variable sv_counter = 0
macro sv() {
    db  sv_counter ? 15 : 8

    sv_counter = !sv_counter
}


// This HDMA table triggers the bug the most often (every 4th scanline)
HdmaTable:
    variable n = 0
    while n < 128 {
        db  2
            sv()

        n = n + 1
    }

    db  0


finalizeMemory()

