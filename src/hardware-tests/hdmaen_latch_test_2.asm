// A simple HDMAEN latch test
//
// Copyright (c) 2019, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "HDMAEN LATCH TEST 2"
define VERSION = 0

architecture wdc65816-strict

include "../common.inc"


createCodeBlock(code,       0x808000, 0x80ffaf)

createRamBlock(zeropage,    0x7e0000, 0x7e00ff)
createRamBlock(lowram,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)


include "../wait.inc"


constant VERTICAL_OFFSET    = 6
constant HTIME_TO_TEST      = 206
constant TESTS_PER_CHANNEL  = 13


au()
iu()
code()
NmiHandler:
BreakHandler:
CopHandler:
EmptyHandler:
    sep     #$20
a8()

    lda.b   #0
    sta.l   NMITIMEN

    lda.b   #8
    sta.l   INIDISP

    // Don't use STP, it can cause some versions snes9x to freeze
    bra     EmptyHandler



code()
PartialHdmaTable:
    //  CGADD,  CGDATA
    dw  0,      31 << Palette.red.shift
    db  0


// IRQ ISR
// REQUIRES: DB access registers
au()
iu()
code()
IrqHandler:
    sep     #$20
a8()
    bit.w   TIMEUP      // Required to escape IrqHandler
    rti


au()
iu()
code()
function ResetHandler {
constant STACK_BOTTOM = __MEMORY__.ramBlocks.stack.end
assert((STACK_BOTTOM & 0xffff) < 0x2000)
assert((STACK_BOTTOM >> 16) == 0 || (STACK_BOTTOM >> 16) == 0x7e)

    jml     Reset
Reset:

    sei
    clc
    xce             // Switch to native mode

    rep     #$38    // 16 bit A, 16 bit Index, Decimal mode off
a16()
i16()
    ldx.w   #STACK_BOTTOM
    txs             // Setup stack

    lda.w   #$0000
    tcd             // Reset Direct Page

    // Set Data Bank
    pea     (REGISTER_DB << 8) | $30
    plp
    plb
a8()
i8()

	stz.w   NMITIMEN
    stz.w   HDMAEN

    // ROM access time
    assert(ROM_SPEED.{ROM_SPEED} == ROM_SPEED.fast)
    lda.b   #MEMSEL.fastrom
    sta.w   MEMSEL

    lda.b   #INIDISP.force
    sta.b   INIDISP


    // Registers $2105 - $210c
    // BG settings and VRAM base addresses
    ldx.b   #$210c - $2105
-
        stz.w   $2105,x
        dex
        bpl     -

    // Registers $2123 - $2133
    // Window Settings, BG/OBJ designation, Color Math, Screen Mode
    // All disabled
    ldx.b   #0x2133 - 0x2123
-
        stz.w   0x2123,x
        dex
        bpl     -

    // reset all of the DMA registers
    // Registers $4300 - $437f

    ldx.b   #0x7f
-
        stz.w   0x4300,x
        dex
        bpl     -


    jml     Main
}


au()
iu()
code()
function Main {
allocate(_channelIndex, lowram, 2)
allocate(_hdmaen,       lowram, 1)

    sep     #$30
a8()
i8()

    stz.w   NMITIMEN
    stz.w   HDMAEN

    // Wait until VBlank
    -
        assert(HVBJOY.vBlank == 0x80)
        lda.w   HVBJOY
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


    lda.b   #HTIME_TO_TEST
    sta.w   HTIMEL
    stz.w   HTIMEH

    lda.b   #NMITIMEN.hCounter
    sta.w   NMITIMEN


    rep     #$10
a8()
i16()
    ldx.w   #0
    stx.w   _channelIndex

    lda.b   #1
    sta.w   _hdmaen


    HdmaChannelLoop:
        evaluate t = 0
        while {t} < TESTS_PER_CHANNEL {
            evaluate delay = 24 + {t} * 2
            evaluate after_delay = 48 - {t} * 2

            wdm     #{t}

            wai
            w{delay}()

            lda.w   _hdmaen
            sta.w   HDMAEN

            w{after_delay}()

            jsr     _OddScanline

            evaluate t = {t} + 1
        }


        lda.w   _channelIndex
        clc
        adc.b   #16
        sta.w   _channelIndex


        asl.w   _hdmaen
        beq     +
            jmp     HdmaChannelLoop
        +

    assert(TESTS_PER_CHANNEL * 2 * 8 + VERTICAL_OFFSET < 220)

    jmp     Main


a8()
i16()
function _OddScanline {
    wai
    stz.w   HDMAEN


    // Reset HDMA registers
    ldx.w   _channelIndex

    stz.w   NLTR0,x

    lda.b   #PartialHdmaTable
    sta.w   A2A0L,x

    // No need to set A2A0H
    assert((PartialHdmaTable & 0xff) + 6 < 256)

    // Set color 0 to white on next HBlank

    -
        assert(HVBJOY.hBlank == 0x40)
        bit.w   HVBJOY
        bvc     -

    lda.b   #0xff
    stz.w   CGADD
    sta.w   CGDATA
    sta.w   CGDATA

    // Required to get the H-Counter IRQ to fire at a consistent time
    // (on bsnes-plus at least)
    lda.b   #11
    -
        dec
        bne     -

    w32()
    w18()

    rts
}

}


finalizeMemory()

