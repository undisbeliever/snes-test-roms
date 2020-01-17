// OAM for the `obj-4bpp-tiles.png` sprite image
//
// Copyright (c) 2020, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT

constant tileSize = 32

constant width = 4
constant height = 2

constant startX = (256 - (width * tileSize)) / 2
constant startY = (224 - (height * tileSize)) / 2

variable tile = 0
variable nextTileRow = 16

variable y = 0
while y < height {

    variable x = 0
    while x < width {
        db  startX + x * tileSize
        db  startY + y * tileSize
        dw  tile | 0x3000   // highest priority

        tile = tile + tileSize / 8
        if tile >= nextTileRow {
            nextTileRow = nextTileRow + (tileSize / 8) * 16
            tile = nextTileRow - 16
        }

        x = x + 1
    }
    y = y + 1
}


// vim: ft=bass-65816 ts=4 sw=4 et:

