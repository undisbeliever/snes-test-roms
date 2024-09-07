// OAM for the spinning logo.
//
// Assumes small sprites are 16x16 px.
//
// SPDX-FileCopyrightText: © 2022 Marcus Rowe <undisbeliever@gmail.com>
// SPDX-License-Identifier: Zlib
//
// Copyright © 2022 Marcus Rowe <undisbeliever@gmail.com>
//
// This software is provided 'as-is', without any express or implied warranty.
// In no event will the authors be held liable for any damages arising from the
// use of this software.
//
// Permission is granted to anyone to use this software for any purpose, including
// commercial applications, and to alter it and redistribute it freely, subject to
// the following restrictions:
//
//    1. The origin of this software must not be misrepresented; you must not
//       claim that you wrote the original software. If you use this software in
//       a product, an acknowledgment in the product documentation would be
//       appreciated but is not required.
//
//    2. Altered source versions must be plainly marked as such, and must not be
//       misrepresented as being the original software.
//
//    3. This notice may not be removed or altered from any source distribution.


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


