// nmi_handler.inc
// ===============
//
// NMI Interrupt Service Routine.
//
// Copyright (c) 2020, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT



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
