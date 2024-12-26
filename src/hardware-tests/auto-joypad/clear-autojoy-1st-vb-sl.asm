// Clear auto joypad flag during the first VBlank scanline test
//
// See _modify-autojoy-during-autojoy.inc for test details
//
//
// SPDX-FileCopyrightText: © 2024 Marcus Rowe <undisbeliever@gmail.com>
// SPDX-License-Identifier: Zlib
//
// Copyright © 2024 Marcus Rowe <undisbeliever@gmail.com>
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


define ROM_NAME = "CLEAR AUTOJOY VB SL"

define TEST_NAME = "Clear AUTOJOY on\nfirst VBlank scanline"
define VERSION = 3

namespace TestData {
    constant DATA_VERSION = 1

    constant N_TESTS = 15

    array[N_TESTS] vtime =   0, 224, 224, 225, 225, 225, 225, 225, 225, 225, 225, 225, 225, 225, 225
    array[N_TESTS] htime =   0, 308, 324,   0,  16,  32,  48,  64,  80,  96, 112, 144, 160, 176, 192
}


constant JOYSER_LATCH_START_VALUE = 0
constant AUTO_JOY_ENABLED_BEFORE_IRQ = 1


// Disables IRQ Interrupts and
//  * on the first IRQ of the test: A = 0 and IrqCode disables auto-joypad.
//  * on the second IRQ of the test: A is set and IrqCode disables auto-joypad.
//
// ::HACK CPU registers are setup before IRQ fires::
// Assumes IRQ interrupt set in DoTest
//
// A = NMITIMEN.autoJoy OR 0
// DB = 80
// D = $4200
inline IrqCode() {
    constant IRQ_VERSION = 1

    assert8a()

    // Disable IRQ interrupts and auto-joypad reading
    stz.b   NMITIMEN
}


include "_modify-autojoy-during-autojoy.inc"

