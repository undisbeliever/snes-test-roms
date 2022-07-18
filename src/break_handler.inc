// break_handler.inc
// =================
//
// A simple Break Interrupt handler.
//
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT



// Break ISR
//
// Red screen of death on error
au()
iu()
code()
function BreakHandler {
    // This ISR may be invoked in emulation mode, switch to native mode
    sei
    clc
    xce

    rep     #$30
    sep     #$20
i16()
a8()
    assert((pc() >> 16) | 0x80 == 0x80)
    phk
    plb

    jsr     ResetRegisters


    // Change Background colour to RED
    stz.w   CGADD
    lda.b   #0x1f
    sta.w   CGDATA
    stz.w   CGDATA

    lda.b   #0x0f
    sta.w   INIDISP


    // Interrupts are disabled.
    // This spinloop will loop forever and do absolutely nothing until the console has been reset.
    SpinLoop:
        wai
        bra     SpinLoop
}


// Use `BreakHandler` for all unused interrupts

// (Used by emulation mode interrupts)
constant EmptyHandler = BreakHandler


if !{defined USES_IRQ_INTERRUPTS} {
    constant IrqHandler = BreakHandler
}

if !{defined USES_COP_INTERRUPTS} {
    constant CopHandler = BreakHandler
}


