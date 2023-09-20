// DMA Ends at HDMA start test
// Testing the previous value read by the DMA controller.
//
// While working on the `dma-ends-hdma-start-1-ch.asm` test, I wondered if the previous value read
// by the DMA controller contributed to the HDMA failure.
//
// This test will setup a DMA from Work-RAM to the PPU that is designed to end when HDMA starts.
// The last value read by the DMA controller is slowly incremented from 0x00 to 0xff. The HDMA state
// registers are checked during VBlank to detect any HDMA failures and the results for each test
// value are displayed on screen.
//
// To eliminate NMI jitter and other timing issues, each test value is repeated multiple times with
// multiple DMA lengths to ensure at least one DMA transfer ends at the target time.
//
// If no HDMA failures are detected when the last DMA value is 0 (a known failure value), the test
// will display an error message.
//
//
// Copyright (c) 2023, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "HDMA FAILURE TEST"
define VERSION = 2

architecture wdc65816-strict

include "../../common.inc"

createCodeBlock(code,       0x808000, 0x80bfff)
createDataBlock(rodata0,    0x80c000, 0x80ff80)

createRamBlock(zeropage,        0x00,     0xff)
createRamBlock(lowram,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)
createRamBlock(wram7e,      0x7e2000, 0xfeffff)


// MAX_DMA_DELAY selected based off the `dma-ends-at-hdma-start-1-ch` test.
// MIN_DMA_DELAY selected to ensure the DMA_DELAY ends before scanline 0 starts (and confirmed with Mesen's Event Viewer).
constant MIN_DMA_DELAY = 0x1330
constant MAX_DMA_DELAY = 0x133A


// The HDMA failure does not occur on every frame (most likely caused by NMI interrupt jitter).
//
// Repeat each `dmaDelay` test `DMA_DELAY_REPEAT` times to ensure the HDMA failure is detected quickly.
constant DMA_DELAY_REPEAT = 4


// Using a different channel order then the `dma-ends-at-hdma-start-1-ch` test.
constant DMA_CHANNEL = 7
constant DMA_DELAY_CHANNEL = 6
constant HDMA_CHANNEL = 0


// $2104 (OAMDATA) is chosen because there are no Objects on screen and it is visible in the Mesen Event Viewer.
constant DMA_DELAY_TARGET = 0x2104


// zero-page temporary word variables (used by TextBuffer)
allocate(zpTmp0, zeropage, 2)

// zero-page temporary far pointer (used by TextBuffer)
allocate(zpTmpPtr, zeropage, 3)


// The value to test (last byte read by the DMA controller before HDMA starts)
// (this value will cycle through 0x00-0xff throughout the test)
allocate(valueToTest,         lowram, 1)

// The number of bytes to read
allocate(dmaDelay,          lowram, 2)

allocate(dmaDelayCountdown, lowram, 1)


// The value of the HDMA A2AN register for the HDMA channel at the start of VBlank.
allocate(hdmaA2an,          lowram, 2)

// The value of the HDMA NLTR register for the HDMA channel at the start of VBlank.
// (unused)
allocate(hdmaNltr,          lowram, 1)


allocate(testResults,       lowram, 256)


// The buffer read by the DMA_DELAY_CHANNEL DMA.
// (Populated by `PopulateDmaBuffer`)
constant dmaBuffer.size = MAX_DMA_DELAY + 16
allocate(dmaBuffer,         wram7e, dmaBuffer.size)


constant DISPLAY_HEIGHT = 224


constant VRAM_BG1_TILES_WADDR = 0x1000
constant VRAM_BG2_TILES_WADDR = 0x2000

constant VRAM_BG1_MAP_WADDR   = 0x0000
constant VRAM_BG2_MAP_WADDR   = 0x0400

constant VRAM_TEXTBUFFER_MAP_WADDR   = VRAM_BG1_MAP_WADDR
constant VRAM_TEXTBUFFER_TILES_WADDR = VRAM_BG1_TILES_WADDR

include "../../reset_handler.inc"
include "../../break_handler.inc"
include "../../dma_forceblank.inc"
include "../../textbuffer.inc"



rodata(rodata0)
namespace Text {
    constant TEST_VERSION = 2
    evaluate TEST_VERSION = TEST_VERSION

    evaluate dma_channel = DMA_CHANNEL
    evaluate dma_delay_channel = DMA_DELAY_CHANNEL
    evaluate hdma_channel = HDMA_CHANNEL

TEST_STRING:
    db  "\n", "DMA ends at HDMA start test"
    db  "\n", "previous DMA value test, v{TEST_VERSION}"
    db  "\n",
    db  "\n",
    db  "\n",
    db  "\n", "      0123456789abcdef"
    db  "\n", "     0"
    db  "\n", "     1"
    db  "\n", "     2"
    db  "\n", "     3"
    db  "\n", "     4"
    db  "\n", "     5"
    db  "\n", "     6"
    db  "\n", "     7"
    db  "\n", "     8"
    db  "\n", "     9"
    db  "\n", "     a"
    db  "\n", "     b"
    db  "\n", "     c"
    db  "\n", "     d"
    db  "\n", "     e"
    db  "\n", "     f"
    db  "\n",
    db  "\n", " X = Failure    . = HDMA OK"
    db  "\n",
    db  0


    constant RESULTS_X = 6
    constant RESULTS_Y = 7

    constant NO_FAILURE_DETECTED_X = 1
    constant NO_FAILURE_DETECTED_Y = 4
}


// DB = 0x80
a8()
i16()
code()
function SetupTest {
    // This value must be incremented whenever `SetupTest` is changed
    constant TEST_VERSION = 2

    evaluate hdma_channel = HDMA_CHANNEL


    // Setup HDMA channels

    // BG2 HOFS HDMA
    ldx.w   #DMAP.direction.toPpu | DMAP.transfer.writeTwice | (BG2HOFS << 8)
    stx.w   DMAP{hdma_channel}               // also sets BBAD{hdma_channel}

    ldx.w   #HdmaTable_BG2HOFS
    stx.w   A1T{hdma_channel}
    lda.b   #HdmaTable_BG2HOFS >> 16
    sta.w   A1B{hdma_channel}


    TextBuffer.PrintString(Text.TEST_STRING)


    // Reset state

    stz.w   valueToTest

    ldx.w   #MIN_DMA_DELAY
    stx.w   dmaDelay

    lda.b   #DMA_DELAY_REPEAT
    sta.w   dmaDelayCountdown

    ldx.w   #0xffff
    stx.w   hdmaA2an

    lda.b   #0xff
    sta.w   hdmaNltr

    jsr     PopulateDmaBuffer


    // Clear test results
    ldx.w   #0xff
    -
        stz.w   testResults,x
        dex
        bpl     -


    // Clear NMI flag
    lda.w   RDNMI

    // Enable VBlank interrupts
    lda.b   #NMITIMEN.vBlank
    sta.w   NMITIMEN

    rts
}



// DB = 0x80
macro VBlank() {
    // This macro MUST NOT use any branch or index-addressing instructions.
    //
    // This ensures the only variables in execution time are:
    //   * When the NMI interrupt starts (unavoidable)
    //   * When DMA starts (unavoidable)
    //   * `dmaDelay` (the variable I am testing)


    // This value must be incremented whenever the VBlank macro is changed
    constant TEST_VERSION = 2

    evaluate dma_channel = DMA_CHANNEL
    evaluate dma_delay_channel = DMA_DELAY_CHANNEL
    evaluate hdma_channel = HDMA_CHANNEL

    assert8a()
    assert16i()

    // Read HDMA state registers
    ldx.w   A2A{hdma_channel}
    stx.w   hdmaA2an

    lda.w   NLTR{hdma_channel}
    sta.w   hdmaNltr


    // Reset HDMA state registers
    ldx.w   #0
    stx.w   A2A{hdma_channel}

    lda.b   #0
    sta.w   NLTR{hdma_channel}



    // Enable display, full brightness
    lda.b   #0xf
    sta.w   INIDISP


    // Setup BG2 H-scroll to the left side of the screen.
    //
    // HDNA will override this value if HDMA is active.
    lda.b   #256 - 10
    sta.w   BG2HOFS
    stz.w   BG2HOFS

    // Enable HDMA channels
    lda.b   #HDMAEN.dma{hdma_channel}
    sta.w   HDMAEN


    // Transfer `charBuffer` to the low-bytes of VRAM at word-address `VRAM_TEXTBUFFER_MAP_WADDR`.
    ldx.w   #VRAM_TEXTBUFFER_MAP_WADDR
    stx.w   VMADD

    assert(VMAIN.incrementMode.low | VMAIN.increment.by1 == 0)
    stz.w   VMAIN

    ldx.w   #DMAP.direction.toPpu | DMAP.transfer.one | (VMDATAL << 8)
    stx.w   DMAP{dma_channel}               // also sets BBAD{dma_channel}

    ldx.w   #TextBuffer.charBuffer
    stx.w   A1T{dma_channel}
    lda.b   #TextBuffer.charBuffer >> 16
    sta.w   A1B{dma_channel}

    ldx.w   #TextBuffer.charBuffer.size
    stx.w   DAS{dma_channel}

    lda.b   #MDMAEN.dma{dma_channel}
    sta.w   MDMAEN


    // Do a DMA write from `valueToTest` to the B-Bus `dmaDelay` bytes so the DMA could end as HDMA starts.
    assert(DMA_DELAY_TARGET & ~0xff == 0x2100)
    ldx.w   #DMAP.direction.toPpu | DMAP.transfer.one | (DMA_DELAY_TARGET << 8)
    stx.w   DMAP{dma_delay_channel}         // also sets BBAD{dma_delay_channel}

    ldx.w   #dmaBuffer
    stx.w   A1T{dma_delay_channel}
    lda.b   #dmaBuffer >> 16
    sta.w   A1B{dma_delay_channel}

    ldx.w   dmaDelay
    stx.w   DAS{dma_delay_channel}

    lda.b   #MDMAEN.dma{dma_delay_channel}
    sta.w   MDMAEN
}


a8()
i16()
code()
function PopulateDmaBuffer {
    lda.w   valueToTest

    ldx.w   #MIN_DMA_DELAY - 8
    -
        sta.l   dmaBuffer,x
        inx
        cpx.w   #dmaBuffer.size
        bcc     -

    rts
}



// DB = 0x80
a8()
i16()
code()
function ProcessTestResults {
    // This value must be incremented whenever this subroutine is changed
    constant TEST_VERSION = 2

    // Use `A2An` to detect if HDMA was processed in the previous frame.
    ldx.w   hdmaA2an
    cpx.w   #HdmaTable_BG2HOFS.EXPECTED_A2An
    beq     NoFailureDetected
        sep     #$30
    i8()
        ldx.w   valueToTest

        lda.b   #1
        sta.w   testResults,x

        rep     #$10
    i16()
NoFailureDetected:

    dec.w   dmaDelayCountdown
    bne     Return
        ldx.w   dmaDelay
        inx
        cpx.w   #MAX_DMA_DELAY + 1
        bcc     +
            lda.w   valueToTest
            jsr     PrintTestResult

            // Test the next value
            inc.w   valueToTest

            jsr     PopulateDmaBuffer

            lda.w   valueToTest
            jsr     SetCurosrPosAndGetResults
            TextBuffer.PrintStringLiteral("?")

            jsr     ConfirmHdmaFailureDetected

            ldx.w   #MIN_DMA_DELAY
        +
        stx.w   dmaDelay

        lda.b   #DMA_DELAY_REPEAT
        sta.w   dmaDelayCountdown

Return:
    rts
}


a8()
i16()
code()
function ConfirmHdmaFailureDetected {
    lda.w   valueToTest
    beq     Return

        lda.w   testResults + 0
        bne     Return

            TextBuffer.SetCursor(Text.NO_FAILURE_DETECTED_X, Text.NO_FAILURE_DETECTED_Y)
            TextBuffer.PrintStringLiteral("ERROR: No HDMA failure!!!")

Return:
    rts
}


// INPUT: A - test index
a8()
i16()
code()
function PrintTestResult {
    jsr     SetCurosrPosAndGetResults
    beq     +
        TextBuffer.PrintStringLiteral("X")
        bra     ++
    +
        TextBuffer.PrintStringLiteral(".")
    +

    rts
}



// INPUT: A - test index
// OUTPUT: A - test results
// OUTPUT: z - set if no results
a8()
i16()
code()
function SetCurosrPosAndGetResults {
    sep     #$30
i8()
    pha

    and.b   #0x0f
    clc
    adc.b   #Text.RESULTS_X
    tax

    lda     1,s
    lsr
    lsr
    lsr
    lsr
    clc
    adc.b   #Text.RESULTS_Y
    tay

    jsr     TextBuffer.SetCursor


    plx
    lda.w   testResults,x

    rep     #$10
i16()

    rts
}



// DB = 0x80
au()
iu()
code()
function Main {
    rep     #$30
    sep     #$20
a8()
i16()
    // Setup PPU
    lda.b   #INIDISP.force | 0x0f
    sta.w   INIDISP

    lda.b   #BGMODE.mode0
    sta.w   BGMODE

    lda.b   #TM.bg1 | TM.bg2
    sta.w   TM

    lda.b   #(VRAM_BG1_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG1SC

    lda.b   #(VRAM_BG2_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG2SC

    lda.b   #(VRAM_BG1_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg1.shift | (VRAM_BG2_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg2.shift
    sta.w   BG12NBA

    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Palette)

    jsr     TextBuffer.InitAndTransferToVram

    ldx.w   #VRAM_BG2_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg2Tiles)

    ldx.w   #VRAM_BG2_MAP_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg2Map)


    jsr     SetupTest

    // Must wait 1 frame before processing results to avoid a false positive
    wai

    MainLoop:
        wai
        jsr     ProcessTestResults

        bra     MainLoop
}


// DB unknown
au()
iu()
code()
function NmiHandler {
    constant TEST_VERSION = 2

    // This ISR must not use any branch or index-addressing instructions.

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

    // No lag frame detection
    // The VBlank routine must execute each frame in a consistent manner.
    VBlank()

    rep     #$30
a16()
i16()

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



namespace Resources {

rodata(rodata0)
Palette:
    // BG1 palette
    dw  ToPalette(0, 0, 0)
    dw  ToPalette(31, 31, 31)
    fill 60, 0

    // BG2 palette
    dw  ToPalette(0, 0, 0)
    dw  ToPalette(0, 31, 0)

constant Palette.size = pc() - Palette


Bg2Tiles:
    db  %00000000, 0
    db  %00000000, 0
    db  %00000000, 0
    db  %00000000, 0
    db  %00000000, 0
    db  %00000000, 0
    db  %00000000, 0
    db  %00000000, 0

    db  %11000000, 0
    db  %11000000, 0
    db  %11000000, 0
    db  %11000000, 0
    db  %11000000, 0
    db  %11000000, 0
    db  %11000000, 0
    db  %11000000, 0
constant Bg2Tiles.size = pc() - Bg2Tiles


Bg2Map:
    variable _i = 0
    while _i < 32 {
        dw      1
        fill    31*2, 0

        _i = _i + 1
    }

constant Bg2Map.size = pc() - Bg2Tiles
}


// Write twice HDMA table to BG2 HOFS
HdmaTable_BG2HOFS:
namespace HdmaTable_BG2HOFS {
    macro hofs_24() {
        // Calculated using python
        // >>> import math
        // >>> [ round(20 + 4 * math.sin(i / 24 * math.tau)) for i in range(24) ]
        dw   20, 21, 22, 23, 23, 24, 24, 24, 23, 23, 22, 21, 20, 19, 18, 17, 17, 16, 16, 16, 17, 17, 18, 19
    }

    db  0x80 | 120      // HDMA repeat mode, 120 scanlines
        hofs_24()
        hofs_24()
        hofs_24()
        hofs_24()
        hofs_24()

    db  0x80 | 120      // HDMA repeat mode, 120 scanlines
        hofs_24()
        hofs_24()
        hofs_24()
        hofs_24()
        hofs_24()

    db  0               // End HDMA table


    // The expected A2An value at VBlank if the HDMA table is active
    constant EXPECTED_A2An = HdmaTable_BG2HOFS + 2 + (DISPLAY_HEIGHT + 1) * 2
}


finalizeMemory()


assert(SetupTest.TEST_VERSION == Text.TEST_VERSION)
assert(NmiHandler.TEST_VERSION == Text.TEST_VERSION)
assert(NmiHandler.VBlank.TEST_VERSION == Text.TEST_VERSION)
assert(ProcessTestResults.TEST_VERSION == Text.TEST_VERSION)


