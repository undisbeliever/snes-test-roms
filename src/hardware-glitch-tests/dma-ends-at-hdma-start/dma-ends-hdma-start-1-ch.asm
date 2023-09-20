// DMA Ends at HDMA start test
// 1 HDMA channel with a DMA channel reading a constant (0) `MPYL` value to a fixed A-Bus address.
//
//
// The SNES Development Discord was discussing Ramsis's DMA<>HDMA crash test[1] and noticed the
// test displays a flicking HDMA gradient on S-CPU-A (CPU version 2) console.  Investigating the
// test revealed the flicking gradient occurs when the DMA finishes at around the same time HDMA
// is initialized (shortly after the start of scanline 0).
//
// [1]: Test ROM that lets you trigger the infamous DMA<>HDMA clash by Ramsis
//      https://forums.nesdev.org/viewtopic.php?p=155872#p155872
//
//
// This test is designed to confirm or deny a HDMA can be interrupted by a DMA if the DMA finishes
// when HDMA starts.
//
// On every VBlank this test will:
//    * Read the value of the HDMA state registers and stores them in Work-RAM.
//
//    * Reset the `A2An` and `NLTRn` HDMA state registers.
//
//    * Set the `BG2HOFS` register to a value that is not used by the HDMA.
//
//    * Preform 2 DMA transfers on every Vertical Blank interrupt.
//      The first DMA transfers a text buffer to VRAM, while the second DMA will repeatedly read the
//      `MPYL` register `dmaDelay` times.
//
// After VBlank:
//    * Test the copy of a `A2An` HDMA state variable matched the expected value.
//      If the value was incorrect, a HDMA failure occurred.
//
//    * If no error has been detected, increase the `dmaDelay` value every `DMA_DELAY_REPEAT` frames
//      (so the end of the second DMA will slowly approach and then pass the HDMA start time).
//
//
// Please wait until the tests prints a success (HDMA OK) or failure (HDMA FAILURE DETECTED) message
// before publishing results.
//
//
// Test Results:
//    * Straight vertical green line on the left: no HDMA
//    * Wavy green line on the right: HDMA completed successfully
//    * Green line on the right: HDMA was interrupted
//    * Red screen: Break interrupt (crash)
//
//
// My Observations (on version 1 of this test):
//    * Model-1 1/1/1 Super Famicom: No crash.  HDMA Failure detected.
//    * S-CPU-A Super Famicom: HDMA Failure detected.
//    * 1-CHIP Super Famicom: HDMA Failure detected.
//
//
// Copyright (c) 2023, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "DMA ENDS AT HDMA START"
define VERSION = 2

architecture wdc65816-strict

include "../../common.inc"

createCodeBlock(code,       0x808000, 0x80bfff)
createDataBlock(rodata0,    0x80c000, 0x80ff80)

createRamBlock(zeropage,        0x00,     0xff)
createRamBlock(lowram,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)
createRamBlock(wram7e,      0x7e2000, 0xfeffff)


constant MIN_DMA_DELAY = 0x1310
constant MAX_DMA_DELAY = 0x1350


// The HDMA failure does not occur on every frame (most likely caused by NMI interrupt jitter).
//
// Repeat each `dmaDelay` test `DMA_DELAY_REPEAT` times to ensure the HDMA failure is detected quickly.
constant DMA_DELAY_REPEAT = 4


constant DMA_CHANNEL = 0
constant DMA_DELAY_CHANNEL = 1
constant HDMA_CHANNEL = 2


// zero-page temporary word variables (used by TextBuffer)
allocate(zpTmp0, zeropage, 2)

// zero-page temporary far pointer (used by TextBuffer)
allocate(zpTmpPtr, zeropage, 3)


// If non-zero a HDMA failure was detected
allocate(hdmaFailureDetected, lowram, 1)

// The number of bytes to read
allocate(dmaDelay,          lowram, 2)

allocate(dmaDelayCountdown, lowram, 1)


// The value of the HDMA A2AN register for the HDMA channel at the start of VBlank.
allocate(hdmaA2an,          lowram, 2)
allocate(hdmaA2anOnFailure, lowram, 2)

// The value of the HDMA NLTR register for the HDMA channel at the start of VBlank.
allocate(hdmaNltr,          lowram, 1)
allocate(hdmaNltrOnFailure, lowram, 1)


// The PPU time at the end of the NMI routine, just after the DMA_DELAY DMA.
allocate(dmaEndTime_opvct,  lowram, 2)
allocate(dmaEndTime_ophct,  lowram, 2)


// The memory location to write the DMA writes to
allocate(dmaDelay_target,   lowram, 1)


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
    db  "\n", "one HDMA channel version {TEST_VERSION}"
    db  "\n"
    db  "\n"
    db  "\n"
    db  "\n"
    db  "\n"
    db  "\n", " DMA {dma_delay_channel} (MPYL read)"
    db  "\n", "        bytes read:  $"
    db  "\n"
    db  "\n", "             OPVCT:  $"
    db  "\n"
    db  "\n", "             OPHCT: ~$"
    db  "\n"
    db  "\n"
    db  "\n", " HDMA Table Address: $"
    db  "\n"
    db  "\n", " HDMA {hdma_channel} A2A{hdma_channel}:        $"
    db  "\n",
    db  "\n", " HDMA {hdma_channel} NLTR{hdma_channel}:       $"
    db  0

    constant VALUE_X = 22

    constant TEST_RESULT_Y = 5
    constant TEST_RESULT_X = 3

    constant DMA_DELAY_Y = 9
    constant DMA_END_OPVCT_Y = 11
    constant DMA_END_OPHCT_Y = 13

    constant HDMA_TABLE_ADDR_Y = 16
    constant HDMA_A2AN_Y = 18
    constant HDMA_NLTR_Y = 20

    constant HDMA_A2AN_ON_FAILURE_Y = 23
    constant HDMA_NLTR_ON_FAILURE_Y = 25

HDMA_OK:
    db  "HDMA OK", 0

HDMA_FAILURE_DETECTED:
    // Must be larger then HDMA_OK_STR
    db  "HDMA FAILURE DETECTED", 0

A2AN_ON_FAILURE:
    db  " A2A{hdma_channel} on failure:    $", 0

NLTR_ON_FAILURE:
    db  " NLTR{hdma_channel} on failure:   $", 0
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

    TextBuffer.SetCursor(Text.VALUE_X, Text.HDMA_TABLE_ADDR_Y)
    ldy.w   #HdmaTable_BG2HOFS
    jsr     TextBuffer.PrintHexSpace_16Y

    // Reset state

    stz.w   hdmaFailureDetected

    ldx.w   #MIN_DMA_DELAY
    stx.w   dmaDelay

    lda.b   #DMA_DELAY_REPEAT
    sta.w   dmaDelayCountdown

    ldx.w   #0xffff
    stx.w   hdmaA2an
    stx.w   hdmaA2anOnFailure

    lda.b   #0xff
    sta.w   hdmaNltr
    sta.w   hdmaNltr


    // Set value by read the DMA Delay to 0
    stz.w   M7A
    stz.w   M7A
    stz.w   M7B
    stz.w   M7B


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


    // Do a DMA read of MPYL for `dmaDelay` bytes so the DMA could end as HDMA starts.
    ldx.w   #DMAP.direction.toCpu | DMAP.fixed | DMAP.transfer.one | (MPYL << 8)
    stx.w   DMAP{dma_delay_channel}         // also sets BBAD{dma_delay_channel}

    ldx.w   #dmaDelay_target
    stx.w   A1T{dma_delay_channel}
    lda.b   #dmaDelay_target >> 16
    sta.w   A1B{dma_delay_channel}

    ldx.w   dmaDelay
    stx.w   DAS{dma_delay_channel}

    lda.b   #MDMAEN.dma{dma_delay_channel}
    sta.w   MDMAEN


    // Read DMA end time from PPU
    lda.w   SLHV

    lda.w   OPVCT
    sta.w   dmaEndTime_opvct
    lda.w   OPVCT
    and.b   #OPVCT.mask >> 8
    sta.w   dmaEndTime_opvct + 1

    lda.w   OPHCT
    sta.w   dmaEndTime_ophct
    lda.w   OPHCT
    and.b   #OPHCT.mask >> 8
    sta.w   dmaEndTime_ophct + 1
}



// DB = 0x80
au()
i16()
code()
function ProcessTestResults {
    // This value must be incremented whenever this subroutine is changed
    constant TEST_VERSION = 2

    // Use `A2An` to detect if HDMA was processed in the previous frame.
    ldx.w   hdmaA2an
    cpx.w   #HdmaTable_BG2HOFS.EXPECTED_A2An
    beq     +
        lda.b   #1
        sta.w   hdmaFailureDetected

        stx.w   hdmaA2anOnFailure

        lda.b   hdmaNltr
        sta.w   hdmaNltrOnFailure
    +

    lda.w   hdmaFailureDetected
    bne     Return
        dec.w   dmaDelayCountdown
        bne     ++
            ldx.w   dmaDelay
            inx
            cpx.w   #MAX_DMA_DELAY + 1
            bcc     +
                ldx.w   #MIN_DMA_DELAY
            +
            stx.w   dmaDelay

            lda.b   #DMA_DELAY_REPEAT
            sta.w   dmaDelayCountdown
        +
Return:
    rts
}



// DB = 0x80
a8()
i16()
code()
function PrintTestResults {

    inline print_u8(yPosConst, var) {
        TextBuffer.SetCursor(Text.VALUE_X + 2, Text.{yPosConst})
        lda.w   {var}
        jsr     TextBuffer.PrintHexSpace_8A
    }

    inline print_u16(yPosConst, var) {
        TextBuffer.SetCursor(Text.VALUE_X, Text.{yPosConst})
        ldy.w   {var}
        jsr     TextBuffer.PrintHexSpace_16Y
    }

    print_u16(DMA_DELAY_Y,      dmaDelay)
    print_u16(DMA_END_OPVCT_Y,  dmaEndTime_opvct)
    print_u16(DMA_END_OPHCT_Y,  dmaEndTime_ophct)
    print_u16(HDMA_A2AN_Y,      hdmaA2an)
    print_u8(HDMA_NLTR_Y,       hdmaNltr)


    TextBuffer.SetCursor(Text.TEST_RESULT_X, Text.TEST_RESULT_Y)

    lda.w   hdmaFailureDetected
    beq     +
        TextBuffer.PrintString(Text.HDMA_FAILURE_DETECTED)

        TextBuffer.SetCursor(0, Text.HDMA_A2AN_ON_FAILURE_Y)
        TextBuffer.PrintString(Text.A2AN_ON_FAILURE)

        TextBuffer.SetCursor(0, Text.HDMA_NLTR_ON_FAILURE_Y)
        TextBuffer.PrintString(Text.NLTR_ON_FAILURE)

        print_u8(HDMA_NLTR_ON_FAILURE_Y,    hdmaNltrOnFailure)
        print_u16(HDMA_A2AN_ON_FAILURE_Y,   hdmaA2anOnFailure)

        bra EndIf
    +
        ldx.w   dmaDelay
        cpx.w   #MAX_DMA_DELAY
        bne     EndIf
            // String must be smaller then failure detected string
            TextBuffer.PrintString(Text.HDMA_OK)
    EndIf:

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
        jsr     PrintTestResults

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


