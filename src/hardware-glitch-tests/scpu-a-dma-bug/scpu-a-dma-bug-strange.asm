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

