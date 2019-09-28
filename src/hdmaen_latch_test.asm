// A simple HDMAEN latch test
//
// Copyright (c) 2019, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "HDMAEN LATCH TEST"
define VERSION = 0

architecture wdc65816-strict

include "common/common.inc"


createCodeBlock(code,       0x808000, 0x80ffaf)

createRamBlock(shadow,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)


include "util/reset_handler.inc"
include "util/dma_forceblank.inc"


constant VERTICAL_OFFSET = 6
constant FIRST_HTIME     = 220
constant LAST_HTIME      = FIRST_HTIME + 12


// Pauses execution until the start of HBlank
// REQUIRES: 8 bit A, DB access registers
// KEEP: all
macro WaitUntilHblank() {
    _Loop{#}:
        assert(HVBJOY.hBlank == 0x40)
        bit.w   HVBJOY
        bvc     _Loop{#}
}

// Pauses execution until the end of HBlank
// REQUIRES: 8 bit A, DB access registers
// KEEP: all
macro WaitUntilHblankEnd() {
    _Loop{#}:
        assert(HVBJOY.hBlank == 0x40)
        bit.w   HVBJOY
        bvs     _Loop{#}
}



au()
iu()
code()
NmiHandler:
BreakHandler:
CopHandler:
EmptyHandler:
    // Don't use STP, it can cause some versions snes9x to freeze
    bra     EmptyHandler



code()
PartialHdmaTable:
    //  CGADD,  CGDATA
    dw  0,      31 << Palette.red.shift
    db  0


// IRQ ISR
// REQUIRES: DB access registers
a8()
iu()
code()
IrqHandler:
    bit.w   TIMEUP      // Required to escape IrqHandler
    rti


au()
iu()
code()
function Main {
allocate(_hdmaen, shadow, 1)

    sep     #$30
a8()
i8()

    stz.w   NMITIMEN
    stz.w   HDMAEN

    // Wait until VBlank
    -
        assert(RDNMI.nmi == 0x80)
        lda.w   RDNMI
        bpl     -


    // Set BG to white
    stz.w   CGADD

    lda.b   #0xff
    sta.w   CGDATA
    sta.w   CGDATA


    // Enable display - full brightness
    lda.b   #15
    sta.w   INIDISP


    // Setup HDMA registers
    ldx.b   #0x70
    -
        lda.b   #DMAP.direction.toPpu | DMAP.transfer.twoWriteTwice
        sta.w   DMAP0,x

        lda.b   #CGADD & 0xff
        sta.w   BBAD0,x

        lda.b   #PartialHdmaTable
        sta.w   A1T0L,x
        sta.w   A2A0L,x

        lda.b   #PartialHdmaTable >> 8
        sta.w   A1T0H,x
        sta.w   A2A0H,x

        lda.b   #PartialHdmaTable >> 16
        sta.w   A1B0,x

        txa
        sec
        sbc.b   #0x10
        tax
        bpl     -


    // Wait until scanline 8
    lda.b   #VERTICAL_OFFSET
    sta.w   VTIMEL
    stz.w   VTIMEH

    lda.b   #NMITIMEN.vCounter
    sta.w   NMITIMEN

    cli
    wai


    lda.b   #1
    sta.w   _hdmaen

    lda.b   #0

    // Signal start of test
    wdm     #0

    HdmaChannelLoop:
        // A = Dma index
        tax

        ldy.b   #FIRST_HTIME

        HtimeLoop:
            // X = DMA index
            // Y = HTIMEL to test

            // Reset HDMA registers
            stz.w   NLTR0,x

            lda.b   #PartialHdmaTable
            sta.w   A2A0L,x

            // No need to set A2A0H
            assert((PartialHdmaTable & 0xff) + 6 < 256)


            // Y = htime to test
            sty.w   HTIMEL
            stz.w   HTIMEH

            lda.b   #NMITIMEN.hCounter
            sta.w   NMITIMEN

            lda.w   _hdmaen
            wai
            sta.w   HDMAEN

            WaitUntilHblank()
            WaitUntilHblankEnd()

            stz.w   NMITIMEN
            stz.w   HDMAEN


            // Set color 0 to white on next HBlank

            WaitUntilHblank()

            stz.w   CGADD
            lda.b   #0xff
            sta.w   CGDATA
            sta.w   CGDATA

            WaitUntilHblankEnd()

            iny
            cpy.b   #LAST_HTIME + 1
            bcc     HtimeLoop


        asl.w   _hdmaen

        txa
        clc
        adc.b   #16
        cmp.b   #0x80
        bcc     HdmaChannelLoop

    assert((LAST_HTIME - FIRST_HTIME + 1) * 2 * 8 + VERTICAL_OFFSET < 224)

    jmp     Main
}


finalizeMemory()

