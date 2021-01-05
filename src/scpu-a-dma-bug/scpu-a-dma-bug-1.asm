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


// This HDMA table occasionally triggers the bug
// (between 1 to 3 DMA failures per 896 tests)
HdmaTable:
    variable n = 0
    while n < 256 {
        db  1
            sv()

        n = n + 1
    }

    db  0


finalizeMemory()

