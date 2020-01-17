// A brick pattern tile map
//
// Copyright (c) 2020, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT

// 32x32 tilemap
// 8x8 px tiles

variable y = 0
while y < 32 {
    variable row = (y + 1) / 2
    variable rowOffset = (y + 1) % 2

    variable startingTile = row * 4
    variable brickId = (row == 2 || row == 12) ? 0 : 1

    // first row
    variable x = 0
    while x < 32 {
        dw ((startingTile + x) % 8) + brickId * 8 + rowOffset * 16
        x = x + 1
    }

    y = y + 1
}


// vim: ft=bass-65816 ts=4 sw=4 et:

