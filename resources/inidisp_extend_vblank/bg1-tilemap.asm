// A simple 2x2 repeating tile pattern tilemap
//
// Copyright (c) 2021, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


// 32x32 tilemap
// 8x8 px tiles

variable i = 0
while i < 1024 {
    dw  (i & 1) | ((i / 16) & 2)

    i = i + 1
}

// vim: ft=bass-65816 ts=4 sw=4 et:

