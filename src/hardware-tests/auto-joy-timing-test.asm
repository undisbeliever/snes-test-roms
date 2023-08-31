// Auto joypad read timing test
//
// This test is used to help determine the H-Time that the
// HVBJOY auto-joy read flag is set and cleared.
//
// Copyright (c) 2023, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "AUTOJOY TIMING TEST"
define VERSION = 0

architecture wdc65816-strict

include "../common.inc"

createCodeBlock(code,       0x808000, 0x80bfff)
createDataBlock(rodata0,    0x80c000, 0x80ff80)

createRamBlock(zeropage,        0x00,     0xff)
createRamBlock(lowram,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)
createRamBlock(wram7e,      0x7e2000, 0xfeffff)


constant VRAM_BG1_TILES_WADDR = 0x1000
constant VRAM_BG1_MAP_WADDR   = 0x0000

constant VRAM_TEXTBUFFER_MAP_WADDR   = VRAM_BG1_MAP_WADDR
constant VRAM_TEXTBUFFER_TILES_WADDR = VRAM_BG1_TILES_WADDR


include "../reset_handler.inc"
include "../break_handler.inc"
include "../dma_forceblank.inc"
include "../textbuffer.inc"

// No Vblank interrupts
constant NmiHandler = BreakHandler


constant TB_STATE_WIDTH   = 3 * 5 - 1
constant TB_LABEL_WIDTH   = 8

constant TB_LABEL_X       = (TextBuffer.N_TEXT_COLUMNS - TB_STATE_WIDTH - TB_LABEL_WIDTH)/2
constant TB_STATE_X       = TB_LABEL_X + TB_LABEL_WIDTH
constant TB_START_STATE_Y = 12
constant TB_END_STATE_Y   = TB_START_STATE_Y + 2


// zero-page temporary word variables (used by TextBuffer)
allocate(zpTmp0, zeropage, 2)

// zero-page temporary far pointer (used by TextBuffer)
allocate(zpTmpPtr, zeropage, 3)


namespace state {
    struct()
        field(current, 2)
        field(min, 2)
        field(max, 2)
    endstruct()
}

// State values for the auto-read start test and the auto-read end test.
//
// NOTE: These values are the OPHCT values after the test has completed.
//
// Not storing these in zeropage as I use a non-zero DP in `DoTest`.
allocate(autoJoyStart, lowram, state.size)
allocate(autoJoyEnd, lowram, state.size)



// DB = 0x80
a8()
i16()
code()
function SetupTest {
    TextBuffer.PrintString(TitleAndVersionStr)

    TextBuffer.SetCursor(TB_STATE_X, TB_START_STATE_Y - 4)
    TextBuffer.PrintStringLiteral("OPHCT after test")

    TextBuffer.SetCursor(TB_STATE_X, TB_START_STATE_Y - 2)
    TextBuffer.PrintStringLiteral("cur  min  max")

    TextBuffer.SetCursor(TB_LABEL_X, TB_START_STATE_Y)
    TextBuffer.PrintStringLiteral("start")

    TextBuffer.SetCursor(TB_LABEL_X, TB_END_STATE_Y)
    TextBuffer.PrintStringLiteral("end")

    lda.b   #NMITIMEN.autoJoy
    sta.w   NMITIMEN


    // Reset state
    ldx.w   #0xffff
    stx.w   autoJoyStart + state.min
    stx.w   autoJoyEnd + state.min

    ldx.w   #0
    stx.w   autoJoyStart + state.max
    stx.w   autoJoyEnd + state.max

    rts
}



// DB = 0x80
a8()
i16()
code()
function DoTest {
    // MUST Update this constant if the test changes
    constant TEST_VERSION = 1

    sep     #$30
a8()
i8()
    // Wait until we are at scanline 200 (well before autojoy starts)
    -
        assert8i()
        ldx.w   SLHV

        ldx.w   OPVCT
        ldy.w   OPVCT

        assert(OPVCT.max & 0xff < 200)
        cpx.b   #200
        bne     -

    rep     #$10
i16()

    // Set DP to to save a cycle reading HVBJOY registers
    assert(HVBJOY & 0xff00 == 0x4200)
    pea     0x4200
    pld
// DP = 0x4200

        // Using a macro to ensure the set and clear tests are the same
        macro _autoJoyTest(branch, stateVar) {
            // Loop until autojoy starts
            lda.b   #HVBJOY.autoJoy
            _Loop_{stateVar}:
                bit.b   HVBJOY
                {branch}    _Loop_{stateVar}

            // Read h-time from PPU
            lda.w   SLHV

            lda.w   OPHCT
            sta.w   {stateVar} + state.current

            lda.w   OPHCT
            sta.w   {stateVar} + state.current + 1
        }

        _autoJoyTest(beq, autoJoyStart)
        _autoJoyTest(bne, autoJoyEnd)

    // Restore DP
    pea     0
    pld
// DP = 0

    rts
}



// DB = 0x80
au()
i16()
code()
function ProcessState {
    // Update the test buffer
    TextBuffer.SetCursor(TB_STATE_X, TB_START_STATE_Y)
    ldx.w   #autoJoyStart
    jsr     UpdateAndPrintState

    TextBuffer.SetCursor(TB_STATE_X, TB_END_STATE_Y)
    ldx.w   #autoJoyEnd
    jsr     UpdateAndPrintState

    rts
}



// DB = 0x80
a8()
i16()
code()
// INPUT: X = state struct address
function UpdateAndPrintState {
    allocate(currentStateIndex, zeropage, 2)

    stx.b   currentStateIndex

    rep     #$30
a16()
        // Update state
        lda.b   state.current,x
        and.w   #OPHCT.mask
        sta.b   state.current,x

        cmp.b   state.min,x
        bcs     +
            sta.b   state.min,x
        +

        cmp.b   state.max,x
        bcc     +
            sta.b   state.max,x
        +

    sep     #$20
a8()

    ldy.b   state.current,x
    jsr     TextBuffer.PrintHexSpace_16Y

    ldx.b   currentStateIndex
    ldy.b   state.min,x
    jsr     TextBuffer.PrintHexSpace_16Y

    ldx.b   currentStateIndex
    ldy.b   state.max,x
    jsr     TextBuffer.PrintHexSpace_16Y

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

    lda.b   #TM.bg1
    sta.w   TM

    lda.b   #(VRAM_BG1_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG1SC

    lda.b   #(VRAM_BG1_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg1.shift
    sta.w   BG12NBA

    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Palette)

    jsr     TextBuffer.InitAndTransferToVram

    lda.b   #0xf
    sta.w   INIDISP


    jsr     SetupTest

    MainLoop:
        jsr     DoTest

        // The PPU is still VBlank, update the text buffer
        TextBuffer.VBlank()

        jsr     ProcessState

        bra     MainLoop
}


rodata(rodata0)
TitleAndVersionStr:
evaluate TEST_VERSION = DoTest.TEST_VERSION
    db  "\n", "HVBJOY autojoy timing test", "\n", "version {TEST_VERSION}", 0

namespace Resources {

rodata(rodata0)
Palette:
    dw  ToPalette(0, 0, 0)
    dw  ToPalette(31, 31, 31)
constant Palette.size = pc() - Palette
}

finalizeMemory()

