// Simple delay macros/functions
//
// SPDX-FileCopyrightText: © 2019 Marcus Rowe <undisbeliever@gmail.com>
// SPDX-License-Identifier: Zlib
//
// Copyright © 2019 Marcus Rowe <undisbeliever@gmail.com>
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


code()
_wait_rom:
allocate(_wait_ram, lowram, 1)
allocate(_wait_zp,  zeropage, 1)


// Wait 12 master cycles
// REQUIRES: in fastROM
inline w12() {
    nop                     // 2 fast
}

// Wait 18 master cycles
// REQUIRES: in fastROM
inline w18() {
    rep     #0              // 3 fast
}

// Wait 20 master cycles
// REQUIRES: 8 bit A, DP = 0, in fastROM
// MODIFIES: n, v
inline w20() {
    assert8a()

    bit.b   _wait_zp       // 2 fast, 1 slow
}

// Wait 24 master cycles
// REQUIRES: in fastROM
inline w24() {
    nop
    nop                     // 4 fast
}

// Wait 26 master cycles
// REQUIRES: 8 bit A, DB = 0x80, in fastROM
// MODIFIES: n, v
inline w26() {
    assert8a()
    bit.w   _wait_ram       // 3 fast, 1 slow
}

// Wait 28 master cycles
// REQUIRES: 16 bit Index, DP = 0, in fastROM
// MODIFIES: Y, P
inline w28() {
    assert16i()
    ldy.b   _wait_zp        // 2 fast, 2 slow
}
// Wait 30 master cycles
// REQUIRES: 16 bit Index, DB = 0x80, in fastROM
// MODIFIES: Y, P
inline w30() {
    assert16i()
    ldy.w   _wait_rom        // 5 fast
}

// Wait 32 master cycles
// REQUIRES: 8 bit A, DB = 0x80, in fastROM
// MODIFIES: A, P
inline w32() {
    assert8a()
    lda.l   _wait_ram        // 4 fast, 1 slow
}

// Wait 34 master cycles
// REQUIRES: 8 bit A, DP = 0, in fastROM
// MODIFIES: Y, P
inline w34() {
    assert8a()
    dec.b   _wait_zp        // 3 fast, 2 slow
}

// Wait 36 master cycles
// REQUIRES: in fastROM
inline w36() {
    w18()
    w18()
}

// Wait 36 master cycles
// REQUIRES: 8 bit A, DP = 0, in fastROM
inline w38() {
    w20()
    w18()
}

// Wait 40 master cycles
// REQUIRES: 8 bit A, DP = 0, in fastROM
inline w40() {
    w20()
    w20()
}

// Wait 42 master cycles
// REQUIRES: in fastROM
inline w42() {
    w18()
    w24()
}

// Wait 44 master cycles
// REQUIRES: 8 bit A, DB = 0x80, in fastROM
inline w44() {
    w18()
    w26()
}

// Wait 46 master cycles
// REQUIRES: 16 bit Index, DP = 0, in fastROM
inline w46() {
    w18()
    w28()
}

// Wait 48 master cycles
// REQUIRES: 16 bit Index, DB = 0x80, in fastROM
inline w48() {
    w18()
    w30()
}


// Wait exactly A scanlines
// REQUIRES: DB = 0x80, fastROM active
// INPUT: A = number of scanlines to wait (must be >= 2)
au()
iu()
code()
function WaitScanlines_A {
    php
    sep     #$30
a8()
i8()
    tax
    dex

    rep     #$10
i16()

    Loop:
        lda.b   #42
        -
            dec
            bne     -

        w28()

        dex
        bne     Loop


    lda.b   #37
    -
        dec
        bne     -

    w28()

    plp
    rts
}

