// Reset position test
//
// This test determines the PPU position at reset using the PPU H/V counters and spinloop cycle
// counting.
//
// Copyright (c) 2023, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define ROM_NAME = "RESET POSITION TEST"
define VERSION = 1
define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan


architecture wdc65816-strict

include "../common.inc"


createCodeBlock(code,       0x808000, 0x80bfff)
createDataBlock(rodata0,    0x80c000, 0x80ff80)

createRamBlock(zeropage,        0x00,     0xff)
createRamBlock(stack,       0x7e0100, 0x7e01ff)
createRamBlock(lowram,      0x7e0200, 0x7e1fff)
createRamBlock(wram7e,      0x7e2000, 0xfeffff)


constant DISPLAY_HEIGHT = 224


constant VRAM_BG1_TILES_WADDR = 0x1000
constant VRAM_BG1_MAP_WADDR   = 0x0000

constant VRAM_TEXTBUFFER_MAP_WADDR   = VRAM_BG1_MAP_WADDR
constant VRAM_TEXTBUFFER_TILES_WADDR = VRAM_BG1_TILES_WADDR


include "../break_handler.inc"
include "../dma_forceblank.inc"
include "../reset_registers.inc"
include "../textbuffer.inc"

// This demo does not use VBlank Interrupts.
constant NmiHandler = BreakHandler


constant N_HBLANKS_TO_COUNT = 36


// zero-page temporary variables (used by TextBuffer)
allocate(zpTmp0, zeropage, 2)
allocate(zpTmpPtr, zeropage, 3)


// Test result variables
allocate(startOpvct, lowram, 2)
allocate(startOphct, lowram, 2)

allocate(hblankCountAtVBlank, lowram, 2)

allocate(cycleCounts, lowram, N_HBLANKS_TO_COUNT)


// DP = 0
// DB = 0
// SP = 0x01ff
// e = 1
// d = 0
// i = 1
a8()
i8()
code()
function ResetHandler {
    // Latch PPU counters as early as possible
    lda.w   SLHV

    clc
    xce


    // Start spin-loop cycle counting to H-blank start time
    rep     #$30
a16()
    lda.w   #HVBJOY & 0xff00
    tcd
// DP = 0x4200

    sep     #$30
a8()
i8()

    variable _i = 0
    while _i < N_HBLANKS_TO_COUNT {
        ldx.b   #0

        if _i != 0 {
            // Wait until the end of H-Blank
            assert(HVBJOY.hBlank == 0x40)
            -
                inx
                bit.b   HVBJOY
                bvs     -
        }

        // Wait until the start of H-Blank
        assert(HVBJOY.hBlank == 0x40)
        -
            inx
            bit.b   HVBJOY
            bvc     -

        stx.w   cycleCounts + _i

        _i = _i + 1
    }


    rep     #$30
a16()
i16()
    lda.w   #0
    tcd
// DP = 0

    sep     #$20
a8()


    // Save PPU H/V counters
    lda.w   OPVCT
    sta.w   startOpvct
    lda.w   OPVCT
    and.b   #OPVCT.mask >> 8
    sta.w   startOpvct + 1

    lda.w   OPHCT
    sta.w   startOphct
    lda.w   OPHCT
    and.b   #OPHCT.mask >> 8
    sta.w   startOphct + 1


    // Measure the number of h-blanks until the start of VBlank

    // Assumes the PPU is not in H-Blank at the start of this loop
    ldx.w   #N_HBLANKS_TO_COUNT
    Loop:
        // Wait until the start of H-Blank
        assert(HVBJOY.hBlank == 0x40)
        -
            bit.w   HVBJOY
            bvc     -

        // Wait until the end of H-Blank
        assert(HVBJOY.hBlank == 0x40)
        -
            bit.w   HVBJOY
            bvs     -

        inx

        assert(HVBJOY.vBlank == 0x80)
        bit.w   HVBJOY
        bpl     Loop

    stx.w   hblankCountAtVBlank



    // Setup PPU
    jsr     ResetRegisters

    lda.b   #BGMODE.mode0
    sta.w   BGMODE

    lda.b   #TM.bg1
    sta.w   TM

    lda.b   #(VRAM_BG1_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG1SC

    lda.b   #(VRAM_BG1_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg1.shift
    sta.w   BG12NBA

    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Palette)



    // Print test results
    jsr     TextBuffer.ClearCharBufferAndResetCursor
    jsr     TextBuffer.ClearAttrBuffer

    TextBuffer.PrintStringLiteral("\nReset position test v{VERSION}\n\n\n")

    TextBuffer.PrintStringLiteral("OPVCT: 0x")
    ldy.w   startOpvct
    jsr     TextBuffer.PrintHexSpace_16Y

    TextBuffer.PrintStringLiteral(" OPHCT: 0x")
    ldy.w   startOphct
    jsr     TextBuffer.PrintHexSpace_16Y

    TextBuffer.PrintStringLiteral("\n\nHBlanks until VBlank: 0x")
    ldy.w   hblankCountAtVBlank
    jsr     TextBuffer.PrintHexSpace_16Y
   

    TextBuffer.PrintStringLiteral("\n\n\nLoops until HBlank:\n\n")

    ldx.w   #0
    -
        phx

        lda.w   cycleCounts,x
        jsr     TextBuffer.PrintHexSpace_8A

        plx
        inx
        cpx.w   #N_HBLANKS_TO_COUNT
        bcc     -

    jsr     TextBuffer.TransferFontAndBuffersToVram



    lda.b   #0xf
    sta.w   INIDISP

    -
        wai
        bra     -
}


rodata(rodata0)
Palette:
    // BG1 palette
    dw  ToPalette(0, 0, 0)
    dw  ToPalette(31, 31, 31)

constant Palette.size = pc() - Palette


finalizeMemory()

