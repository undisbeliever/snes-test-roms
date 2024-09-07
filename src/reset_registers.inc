// reset_registers.inc
// ===================
//
// A subroutine to reset the registers to a good initial state.
//
// SPDX-FileCopyrightText: © 2016 Marcus Rowe <undisbeliever@gmail.com>
// SPDX-License-Identifier: Zlib
//
// Copyright © 2016 Marcus Rowe <undisbeliever@gmail.com>
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



// Reset the registers to a good initial state.
//
// REQUIRES: Requires 6 bytes of stack space
au()
iu()
code()
function ResetRegisters {
    php
    phd

    rep     #$30
a16()
    lda.w   #0x2100
    tcd

    sep     #$30
a8()
i8()

    // Disable interrupts and HDMA
    // A = 0
	sta.l   NMITIMEN
    sta.l   HDMAEN

    // Reset IO pins
    lda.b   #0xff
    sta.l   WRIO


    // Force Screen Blank
    lda.b   #INIDISP.force
    sta.b   INIDISP


    stz.b   OBSEL


    // Registers $210d - $2114
    // BG Scroll Locations - Write twice
    // horizontal offset set to 0
    // vertical offset set to -1
    ldx.b   #0x2114 - 0x210d - 1
    lda.b   #0xff
-
        stz.b   0x0d,x
        stz.b   0x0d,x
        sta.b   0x0e,x
        sta.b   0x0e,x
        dex
        dex
        bpl     -

    // Registers $2105 - $210c
    // BG settings and VRAM base addresses
    ldx.b   #$210c - $2105
-
        stz.b   $05,x
        dex
        bpl     -

    // Skipping Mode 7 as any programmer using that mode
    // will set those registers anyway.

    // Increment VRAM by 1 word on reading/writing the high byte of VRAM
    lda.b   #VMAIN.incrementMode.high | VMAIN.increment.by1
    sta.b   VMAIN

    // Registers $2123 - $2133
    // Window Settings, BG/OBJ designation, Color Math, Screen Mode
    // All disabled
    ldx.b   #0x2133 - 0x2123
-
        stz.b   0x23,x
        dex
        bpl     -


    lda.b   #CGWSEL.prevent.always
    sta.b   CGWSEL

    // Set Fixed color data to black
    lda.b   #COLDATA.plane.all | 0
    sta.b   COLDATA



    // reset all of the DMA registers
    // Registers $4300 - $437f
    rep     #$20
a16()
    lda.w   #0x4300
    tcd

    ldx.b   #0x7e
-
        stz.b   0,x
        dex
        dex
        bpl     -

    pld
    plp
    rts
}

