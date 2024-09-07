// vblank_interrupts.inc
// =====================
//
// A simple NMI interrupt handler.
//
// NOTE: This file must be included after a `VBlank()` macro is defined and before the
//       `EnableVblankInterrupts()` macro is invoked.
//
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



// Execute V-Blank Routine flag
//
// The VBlank routine will be executed if this value is non-zero.
//
// (byte flag)
allocate(__vBlankFlag, lowram, 1)


// Frame counter.  Incremented every NMI interrupt
// (uint32)
allocate(frameCounter, lowram, 4)



if {defined VBLANK_READS_JOYPAD} {
    // The current state of the joypad
    allocate(joypadCurrent, lowram, 2)

    // The newly pressed buttons on this frame
    allocate(joypadPressed, lowram, 2)
}



// Enable VBlank interrupts.
//
// NOTE: This macro disabled IRQ interrupts.
//
// This is a macro, it should only be included once inside the Setup routine.
//
// REQUIRES: DB access low-RAM
macro EnableVblankInterrupts() {

    // Do not process VBlank routine on the next VBlank Interrupt
    stz.w   __vBlankFlag

    // Clear NMI flag
    lda.w   RDNMI

    lda.b   #NMITIMEN.vBlank | NMITIMEN.autoJoy
    sta.w   NMITIMEN
}



// Enable VBlank interrupts with auto joypad read disabled
//
// NOTE: This macro disables IRQ interrupts and Auto-Joypad read.
//
// This is a macro, it should only be included once inside the Setup routine.
//
// REQUIRES: DB access low-RAM
macro EnableVblankInterrupts_NoAutoJoypad() {

    // Do not process VBlank routine on the next VBlank Interrupt
    stz.w   __vBlankFlag

    // Clear NMI flag
    lda.w   RDNMI

    lda.b   #NMITIMEN.vBlank
    sta.w   NMITIMEN
}



// Wait until the start of a new display frame
// (or the end of the VBlank routine (NmiHandler)).
//
// REQUIRES: NMI enabled, DB access low-RAM
au()
iu()
code()
function WaitFrame {
    php
    sep     #$20
a8()

    lda.b   #1
    sta.w   __vBlankFlag


    // Loop until `__vBlankFlag` is clear
    Loop:
        wai

        lda.w   __vBlankFlag
        bne     Loop

    plp

    rts
}



// NMI ISR
//
// Invokes `VBlank()` macro if the main-loop is inside `WaitFrame`.
au()
iu()
code()
function NmiHandler {
    // Ensure we are in bank 0x00 or 0x80
    assert((pc() >> 16) | 0x80 == 0x80)


    // Jump to FastROM bank (if this ISR is in a FastROM address)
    if pc() >> 16 == 0x80 {
        jml     FastRomNmiHandler
    FastRomNmiHandler:
    }


    // Save CPU state
    rep     #$30
a16()
i16()
    pha
    phx
    phy
    phd
    phb


    phk
    plb
// DB = 0x00 or 0x80

    lda.w   #0
    tcd
// DP = 0


    sep     #$20
a8()

    // Only execute the VBlank routine if `__vBlankFlag` is non-zero.
    // (prevents corruption during force-blank setup or a lag frame)
    lda.w   __vBlankFlag
    bne     +
        jmp     EndVBlankRoutine
    +

        // Execute VBlank routine
        VBlank()


        // Clear VBlank flag
        // (signal to the main-loop that the VBlank routine has been executed)
        assert8a()
        stz.w   __vBlankFlag


        if {defined VBLANK_READS_JOYPAD} {
            // Wait until Auto-Joy is ready
            lda.b   #HVBJOY.autoJoy
            -
                assert8a()
                bit.w	HVBJOY
                bne		-

            rep     #$30
        a16()
        i16()

            // Test joypad type bits and ignore anything that is not a standard controller
            lda.w   JOY1
            bit.w   #JOY.type.mask
            beq     +
                lda.w   #0
            +

            // Save current and retrieve old `joypadCurrent`
            tay
            lda.w   joypadCurrent
            sty.w   joypadCurrent

            // Calculate newly pressed buttons
            // A = old joypadCurrent
            eor.w   #0xffff
            and.w   joypadCurrent
            sta.w   joypadPressed
        }

au()
iu()
EndVBlankRoutine:

    rep     #$30
a16()
i16()

    // Increment 32 bit frameCounter
    inc.w   frameCounter
    bne     +
        inc.w   frameCounter + 2
    +


    // Restore CPU state
    assert16a()
    assert16i()
    plb
    pld
    ply
    plx
    pla

    rti
}


