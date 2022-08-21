// S-CPU-A hardware DMA bug tests
// ==============================
//
// Near has reported that a DMA transfer can fail if a HDMA transfer
// with a B-Bus address of $2100 occurs on the previous scanline.
//
//
// This test will:
//   * Create a HDMA transfer to INIDISP ($2100).
//
//   * Preform a DMA transfer to Work-RAM on every visible scanline.
//     The transfer will consist of a single byte of fixed data.
//     If the DMA transfer fails, a different value will be written to Work-RAM instead.
//
//   * At the end of the test, the Work-RAM data is transferred to Video-RAM.
//
//
// Output of these tests:
//
//   * Green squares with a "scanline" effect - No DMA issues detected.
//     The test will continue to test for a DMA bug until one occurs.
//
//   * Red squares with no "scanline" effect - At least one DMA failure occurred.
//     Each red square represents a single DMA failure, and green squares represent a
//     successful DMA transfer.
//     The test will stop execution and no-longer test for DMA failures.
//
//   * No scanline effect and the display is at half-brightness - The break handler was executed.
//
//
// Copyright (c) 2021, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "SCPU-A DMA BUG TEST"
define VERSION = 0


architecture wdc65816-strict


include "../../common.inc"


createCodeBlock(code,       0x808000, 0x80ffaf)

createRamBlock(dp,          0x7e0000, 0x7e00ff)
createRamBlock(lowram,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)
createRamBlock(wram7f,      0x7f0000, 0x7fffff)


// V-Counter value for the HTIME IRQ interrupt.
//
// The bug also happens in h-blank (irqXpos = 205)
define irqXpos = 20


if !{defined hdma_dmap} {
    evaluate hdma_dmap = DMAP.direction.toPpu | DMAP.addressing.absolute | DMAP.transfer.one
    evaluate hdma_bbad = 0x00
}



// ::TODO a basic reset file that doesn't use DMA routines ::
include "../../reset_handler.inc"
include "../../dma_forceblank.inc"



// VRAM MAP
// (test only uses BG1)
constant VRAM_BG1_TILES_WADDR = 0x1000
constant VRAM_BG1_MAP_WADDR   = 0x1400



// Variables
constant testStatus.size = 28 * 32
allocate(testStatus, wram7f, testStatus.size)

allocate(byteAfterTestStatus, wram7f, 2)

allocate(errorCount, dp, 2)




// Break ISR
// Disable HDMA, interrupts, set display to half brightness and stop execution.
code()
CopHandler:
EmptyHandler:
function BreakHandler {
    // This ISR may be invoked in emulation mode, switch to native mode
    sei
    clc
    xce

    sep     #$30
a8()
i8()
    phk
    plb

    stz.w   NMITIMEN
    stz.w   HDMAEN

    lda.b   #8
    sta.w   INIDISP

-
    bra     -
}



// NMI ISR
// Does not do anything
code()
function NmiHandler {
    rti
}



// IRQ ISR
//
// Does not do anything
code()
function IrqHandler {
    sep     #$20
a8()
    pha

    lda.l   TIMEUP

    pla
    rti
}



macro incrementErrorCount() {
    assert8a()

    inc.b   errorCount
    bne     Skip{#}
        inc.b   errorCount + 1
    Skip{#}:
}



a8()
i16()
code()
function SetupPpu {
    lda.b   #INIDISP.force
    sta.w   INIDISP

    stz.w   HDMAEN

    jsr     WaitUntilVBlank


    // Setup PPU registers

    lda.b   #BGMODE.mode0
    sta.w   BGMODE

    lda.b   #(VRAM_BG1_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG1SC

    lda.b   #(VRAM_BG1_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg1.shift
    sta.w   BG12NBA

    lda.b   #TM.bg1
    sta.w   TM
    stz.w   TS


    // Set BG1 scroll
    stz.w   BG1HOFS
    stz.w   BG1HOFS

    lda.b   #0xff
    sta.w   BG1VOFS
    sta.w   BG1VOFS



    // Setup CGRAM colors
    stz.w   CGADD

    ldx.w   #0
    -
        lda.l   PaletteData,x
        sta.w   CGDATA

        inx
        cpx.w   #PaletteData.size
        bcc     -



    lda.b   #VMAIN.increment.by1 | VMAIN.incrementMode.high
    sta.w   VMAIN

    rep     #$30
a16()

    // Copy Tile Data
    ldx.w   #VRAM_BG1_TILES_WADDR
    stx.w   VMADD

    ldx.w   #0
    -
        lda.l   TileData,x
        sta.w   VMDATA

        inx
        inx
        cpx.w   #TileData.size
        bcc     -


    // Clear tilemap
    ldx.w   #VRAM_BG1_MAP_WADDR
    stx.w   VMADD

    ldx.w   #32 * 32
    -
        stz.w   VMDATA
        dex
        dex
        bne     -


    sep     #$20
a8()

    rts
}



a8()
i16()
code()
function SetupHdma {
    stz.w   HDMAEN


    lda.b   #{hdma_dmap}
    sta.w   DMAP{hChannel}

    lda.b   #{hdma_bbad}
    sta.w   BBAD{hChannel}


    ldx.w   #HdmaTable
    stx.w   A1T{hChannel}

    lda.b   #HdmaTable >> 16
    sta.w   A1B{hChannel}


    // Enable HDMA
    lda.b   #HDMAEN.dma{hChannel}
    sta.w   HDMAEN

    rts
}



a8()
i16()
code()
function DoTest {
constant WRITE_TEST_VALUE = 0x42


    // Setup WMDATA address
    ldx.w   #testStatus
    stx.w   WMADDL

    lda.b   #testStatus >> 16
    sta.w   WMADDH


    // Reset the write test bytes
    // (used to assert `WMDATA` writes exactly `testStatus.size` bytes to `testStatus`)
    assert(byteAfterTestStatus == testStatus + testStatus.size)
    lda.b   #WRITE_TEST_VALUE
    sta.l   testStatus + testStatus.size - 1
    sta.l   byteAfterTestStatus


    // Setup MDMA
    // Copy 1 byte to Work RAM

    ldy.w   #DMAP.direction.toPpu | DMAP.fixed | DMAP.transfer.one | (WMDATA << 8)
    sty.w   DMAP{mChannel}     // also sets BBAD

    ldx.w   #SuccessByte
    stx.w   A1T{mChannel}
    stz.w   A1B{mChannel}

    ldy.w   #1
    sty.w   DAS{mChannel}


    jsr     WaitUntilVBlank

    jsr     SetupHdma


    // Setup IRQ
    stz.w   NMITIMEN
    cli

    ldy.w   #{irqXpos}
    sty.w   HTIME

    lda.b   #NMITIMEN.hCounter
    sta.w   NMITIMEN


    ldy.w   #testStatus.size - 1

    Loop:
        // Y = number of tests to process

        wai

        // Do not do the test if we are in VBlank
        assert(HVBJOY.vBlank == 0x80)
        bit.w   HVBJOY
        bmi     Loop


        // Disable HDMA
        // (Confirm the bug still happens if HDMA is disabled)
        stz.w   HDMAEN


        lda.b   #1
        sta.w   DAS{mChannel}L

        lda.b   #MDMAEN.dma{mChannel}
        sta.w   MDMAEN


        // Check if the MDMAEN failed
        ldx.w   DAS{mChannel}L
        beq     +
            if {defined try_mdma_again} {
                // Do a second attempt at a MDMA transfer
                sta.w   MDMAEN

                // Check if the second MDMA failed
                ldx.w   DAS{mChannel}L
                beq     +
            }

            lda.b   #FAILURE_TILE_ID
            sta.w   WMDATA

            incrementErrorCount()
        +


        // Reenable HDMA
        lda.b   #HDMAEN.dma{hChannel}
        sta.w   HDMAEN


        dey
        bpl     Loop


    // Diable IRQ
    stz.w NMITIMEN
    sei


    // Confirm the last byte in `testStatus` was written to
    lda.l   testStatus + testStatus.size - 1
    cmp.b   #WRITE_TEST_VALUE
    beq     Fail

    // Confirm `WMDATA` did not write to the byte after `testStatus`
    lda.l   byteAfterTestStatus
    cmp.b   #WRITE_TEST_VALUE
    bne     Fail


    rts


Fail:
    brk     #0
}



a8()
i16()
code()
function ShowTestResults {

    jsr     WaitUntilVBlank

    stz.w   HDMAEN

    lda.b   #INIDISP.force | 15
    sta.w   INIDISP


    // Copy testStatus data to BG1 MAP
    lda.b   #VMAIN.increment.by1 | VMAIN.incrementMode.low
    sta.w   VMAIN

    ldx.w   #VRAM_BG1_MAP_WADDR
    stx.w   VMADD


    ldy.w   #DMAP.direction.toPpu | DMAP.transfer.one | (VMDATAL << 8)
    sty.w   DMAP0               // also sets BBAD0

    ldx.w   #testStatus
    stx.w   A1T0
    lda.b   #testStatus >> 16
    sta.w   A1B0

    ldy.w   #testStatus.size
    sty.w   DAS0

-
    lda.b   #MDMAEN.dma0
    sta.w   MDMAEN

    // Retry DMA if it failed
    ldy.w   DAS0
    bne     -


    jsr     SetupHdma


    lda.b   #15
    sta.w   INIDISP

    rts
}



au()
iu()
code()
function WaitUntilVBlank {
    php
    sep     #$30
a8()
i8()

    // Wait until VBlank
    lda.b   #NMITIMEN.vBlank
    sta.w   NMITIMEN

    Loop:
        wai

        assert(HVBJOY.vBlank == 0x80)
        bit.w   HVBJOY
        bpl     Loop

    stz.w   NMITIMEN

    plp
    rts
}



au()
iu()
code()
function Main {
    rep     #$30
    sep     #$20
a8()
i16()

    jsr     SetupPpu


    ldx.w   #0
    stx.b   errorCount


    TestLoop:
        jsr     DoTest

        jsr     ShowTestResults

        ldx.b   errorCount
        beq     TestLoop


    // We encountered a bad DMA transfer
    // Disable HDMA and stop testing.
    stz.w   HDMAEN
-
    bra     -
}



PaletteData:
    dw  ToPalette(24, 24,  15)
    dw  ToPalette( 0, 15,  0)
    dw  ToPalette(31,  0,  0)
    dw  ToPalette( 8,  8,  8)

constant PaletteData.size = pc() - PaletteData


TileData:
// Blank tile
    fill    16, 0

// Success tile
    db  %11111111, %00000001
    db  %11111111, %00000001
    db  %11111111, %00000001
    db  %11111111, %00000001
    db  %11111111, %00000001
    db  %11111111, %00000001
    db  %11111111, %00000001
    db  %11111111, %11111111

// Failure tile
    db  %00000000, %11111111
    db  %01000010, %11111111
    db  %00100100, %11111111
    db  %00011000, %11111111
    db  %00011000, %11111111
    db  %00100100, %11111111
    db  %01000010, %11111111
    db  %00000000, %11111111

constant TileData.size = pc() - TileData
assert(TileData.size == 16 * 3)

constant SUCCESS_TILE_ID = 1
constant FAILURE_TILE_ID = 2


SuccessByte:
    db  SUCCESS_TILE_ID


