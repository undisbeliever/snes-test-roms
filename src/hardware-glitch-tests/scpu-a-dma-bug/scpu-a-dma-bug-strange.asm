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


// For some strange reason this HDMA table does not appear trigger the bug
// on my 2/1/3 3-Chip Super Famicom console.
//
// This table did not trigger on my console after running this test for
// over 3 hours.
//
// Limited testing has shown that I am unable to trigger the bug in HDMA
// repeat mode with a line count >= 3.
//
// I have no idea if this behaviour is specific to my console or not.
HdmaTable:
    variable n = 0
    while n < 256 {
        // repeat mode, 3 lines
        db  $80 | 3
            sv()
            sv()
            sv()

        n = n + 1
    }

    db  0


finalizeMemory()

