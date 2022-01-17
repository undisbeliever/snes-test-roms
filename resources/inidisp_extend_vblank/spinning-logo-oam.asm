// OAM for the spinning logo.
//
// Assumes small sprites are 16x16 px.
//
// Copyright (c) 20, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


constant X_OFFSET = (256 - 192) / 2
constant Y_OFFSET = (224 - 80) / 2

// Add a single sprite to Oam
macro sprite(evaluate x, evaluate y, evaluate tile) {
    // 0x30 = highest priority
    db  X_OFFSET + {x}, Y_OFFSET + {y}, {tile}, 0x30
}

// Adds 4 sprites to the Oam
macro halfRow(x, y, tile) {
    sprite({x} +  0, {y}, {tile} + 0)
    sprite({x} + 16, {y}, {tile} + 2)
    sprite({x} + 32, {y}, {tile} + 4)
    sprite({x} + 48, {y}, {tile} + 6)
}


variable y = 0
while y < 5 {
    halfRow( 0, y * 16, y * 32)
    halfRow(64, y * 16, y * 32 + 8)

    y = y + 1
}
halfRow(128,  0, 0xa0)
halfRow(128, 16, 0xa8)
halfRow(128, 32, 0xc0)
halfRow(128, 48, 0xc8)
halfRow(128, 64, 0xe0)


// vim: ft=bass-65816 ts=4 sw=4 et:


