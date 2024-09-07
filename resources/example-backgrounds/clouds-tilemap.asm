// A clouds pattern tile map
//
// SPDX-FileCopyrightText: © 2020 Marcus Rowe <undisbeliever@gmail.com>
// SPDX-License-Identifier: Zlib
//
// Copyright © 2020 Marcus Rowe <undisbeliever@gmail.com>
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

