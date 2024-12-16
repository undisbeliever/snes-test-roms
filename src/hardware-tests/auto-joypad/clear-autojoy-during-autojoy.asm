// Clear auto joypad flag during auto-joypad read test (multiple scanlines)
//
// See _clear-autojoy-during-autojoy.inc for test details
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


define ROM_NAME = "CLEAR AUTOJOY TEST"

define TEST_NAME = "Clear AUTOJOY during AUTOJOY"
define VERSION = 1

namespace TestData {
    constant DATA_VERSION = 1

    constant N_TESTS = 9

    array[N_TESTS] vtime = 224, 225, 225, 226, 226, 227, 227, 228, 227
    array[N_TESTS] htime = 200,  20, 200,  20, 200,  20, 200,  20, 200
}

include "_clear-autojoy-during-autojoy.inc"

