// A simple test to demonstrate the brightness delay on a RGB modded 1-chip console.
//
// NOTE: You must disable the *1CHIP transient fixes* and *Brightness limit*
//       settings if you are running this test on an sd2snes.
//
// Copyright (c) 2019, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "BRIGHTNESS DELAY TEST"
define VERSION = 0

architecture wdc65816-strict

include "../common.inc"

createCodeBlock(code,       0x808000, 0x80ffaf)

createRamBlock(shadow,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)

include "../reset_handler.inc"
include "../dma_forceblank.inc"


// The number of scanlines between each brightness test
constant BRIGHTNESS_TEST_HEIGHT = 32


// Break ISR
// Red screen of death on error
au()
iu()
code()
CopHandler:
EmptyHandler:
BreakHandler:
    rep     #$30
    sep     #$20
i16()
a8()
    assert(pc() >> 16 == 0x80)
    phk
    plb

    jsr     ResetRegisters

    stz.w   CGADD
    lda.b   #0x1f
    sta.w   CGDATA
    stz.w   CGDATA

    lda.b   #0x0f
    sta.w   INIDISP

-
    bra     -



// NMI ISR
// (only used for wai instructions)
au()
iu()
code()
NmiHandler:
    rti



au()
iu()
code()
function Main {
    rep     #$30
    sep     #$20
a8()
i16()
    // Setup PPU registers

    lda.b   #INIDISP.force | 0xf
    sta.w   INIDISP

    // Fill CGRAM with white
    stz.w   CGADD

    ldx.w   #512
    lda.b   #0xff
    -
        sta.w   CGDATA
        dex
        bne     -

    lda.b   #0
    sta.w   TM



    // Enable IRQ at HTIME=0
    ldx.w   #339 - 80
    stx.w   HTIME

    lda.b   #NMITIMEN.hCounter
    sta.w   NMITIMEN

    cli


    MainLoop:
        wai
        bra     MainLoop
}


// IRQ ISR
//
// Enable display (at full brightness)
function IrqHandler {
    rep     #$30
a16()
i16()
    phb
    pha
    phx
    phy

    phk
    plb

    sep     #$30
a8()
i8()
    // Latch V Counter
    lda.w   SLHV

    // Read vertical scanline location
    lda.w   OPVCT
    ldx.w   OPVCT
    // A = OPVCT low byte

    // Change brightness when we are on an appropriate scanline
    assertPowerOfTwo(BRIGHTNESS_TEST_HEIGHT)
    sec
    sbc.b   #8
    and.b   #BRIGHTNESS_TEST_HEIGHT - 1
    bne     +
        // Full brightness
        ldx.b   #0xf
        stx.w   INIDISP
        bra     End
    +
    cmp.b   #BRIGHTNESS_TEST_HEIGHT / 2
    bne     +
        // 0 brightness
        stz.w   INIDISP
    +

End:
    lda.w   TIMEUP  // Required to escape IrqHandler

    rep     #$30
a16()
i16()
    ply
    plx
    pla
    plb

    rti
}


finalizeMemory()

