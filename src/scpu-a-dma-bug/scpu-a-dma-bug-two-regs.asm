// S-CPU-A hardware DMA bug test
// =============================
//
// Copyright (c) 2021, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define mChannel = 0
define hChannel = 1

// Use HDMA to transfer two bytes to 0x2100 & 0x2101
evaluate hdma_dmap = 0x01 // DMAP.direction.toPpu | DMAP.addressing.absolute | DMAP.transfer.two
evaluate hdma_bbad = 0x00


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
            sv() ; db  1

        n = n + 1
    }

    db  0


finalizeMemory()

