// S-CPU-A hardware DMA bug test
// =============================
//
// SPDX-FileCopyrightText: © 2021 Marcus Rowe <undisbeliever@gmail.com>
// SPDX-License-Identifier: Zlib
//
// Copyright © 2021 Marcus Rowe <undisbeliever@gmail.com>
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


define mChannel = 0
define hChannel = 1


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
            sv()

        n = n + 1
    }

    db  0


finalizeMemory()

