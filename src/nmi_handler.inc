// nmi_handler.inc
// ===============
//
// NMI Interrupt Service Routine.
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



// NMI ISR
//
// This NMI handler is designed to be 4 master cycles slower on
// non-interlace frames to help stabilize the horizontal position in
// which the IRQ ISR is executed.
//
// REQUIRES: fastROM enabled
au()
iu()
code()
function NmiHandler {
    assert((pc() >> 16) == 0x80 && (pc() & 0xffff) >= 0x8000)
    assert(ROM_SPEED.{ROM_SPEED} == ROM_SPEED.fast)

    jml     Nmi_Fast
Nmi_Fast:

    sep     #$20
a8()
    pha

    assert(STAT78.interlace == 0x80)
    bit.w   STAT78
    bmi     +
        // 2 fast (branch not taken)
        // 4 fast (2x nop)
        // 3 fast (bra)
        // = (9*6) = 54 master cycles
        nop
        nop
        bra     ++
    +
        // Have to use long addressing, DP and DB is unknown

        // 3 fast (branch taken)
        // 4 fast, 1 slow  (lda long WorkRAM)
        // = (7*6 + 1*8) = 50 master cycles
        lda.b   0x7e0000
    +

    pla
    rti
}
