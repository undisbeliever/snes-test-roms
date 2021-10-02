// A clouds pattern tile map
//
// Copyright (c) 2020, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


// 32x32 tilemap


constant PATTERN_WIDTH = 16
constant PATTERN_HEIGHT = 8


variable y = 0
while y < 32 {
    variable x = 0
    while x < 32 {
        dw  (x % PATTERN_WIDTH) + (y % PATTERN_HEIGHT) * PATTERN_WIDTH

        x = x + 1
    }

    y = y + 1
}


// vim: ft=bass-65816 ts=4 sw=4 et:

