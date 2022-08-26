// This code tests what happens when you write to the `WRMPYB` register while a previous
// multiplication is still being processed by the 5A22.  Each test input is processed 8 times,
// with a differing number of CPU cycles between `WEMPYB` writes.
//
//
// TEST INPUTS:
//      A  = value to write to `WRMPYA`
//      B1 = the first write to `WRMPYB`
//      B2 = the second write to `WRMPYB` after 2-9 CPU cycles 
//
// TEST OUTPUTS:
//      2cy = The `RDMPY` output when there are 2 CPU cycles between `WRMPYB` writes
//            (after waiting 8+ cycles after the second `WRMPYB` write)
//      ...
//      9cy = The `RDMPY` output when there are 9 CPU cycles between `WRMPYB` writes
//
//
// Controls:
//    B / Y - change selected value
//    D-Pad - adjust selected value
//
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "WRMPYB IN FLIGHT"
define VERSION = 0

architecture wdc65816-strict

include "../common.inc"


createCodeBlock(code,       0x808000, 0x80ffaf)
createCodeBlock(rodata0,    0x818000, 0x81ffff)

createRamBlock(zeropage,        0x00,     0xff)
createRamBlock(lowram,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)
createRamBlock(wram7e,      0x7e2000, 0xfeffff)


constant VRAM_BG1_MAP_WADDR   = 0x0000
constant VRAM_BG1_TILES_WADDR = 0x1000

constant VRAM_TEXTBUFFER_MAP_WADDR   = VRAM_BG1_MAP_WADDR
constant VRAM_TEXTBUFFER_TILES_WADDR = VRAM_BG1_TILES_WADDR


define USES_IRQ_INTERRUPTS


include "../reset_handler.inc"
include "../break_handler.inc"
include "../dma_forceblank.inc"
include "../textbuffer.inc"


// zero-page temporary word variables
allocate(zpTmp0, zeropage, 2)
allocate(zpTmp1, zeropage, 2)
allocate(zpTmp2, zeropage, 2)
allocate(zpTmp3, zeropage, 2)

// zero-page temporary far pointer
allocate(zpTmpPtr, zeropage, 3)



constant N_TESTS = 10

constant BYTES_PER_TEST = 19



// Buffer to store the text results to
allocate(results, lowram, 1024)
assert(N_TESTS * BYTES_PER_TEST < 1024)



// The three input values for the test
// (3x uint8)
allocate(test_a,  lowram, 1)
allocate(test_b1, lowram, 1)
allocate(test_b2, lowram, 1)

constant testInputs      = test_a
constant testInputs.size = 3


// The currently selected value for controller input
// (byte index into testInputs)
allocate(selectedInput, lowram, 1)



// Loop Counter when printing results
// (uint8)
allocate(loopCounter, lowram, 1)



// Taken from Anomie's timing document
constant DRAM_REFRESH_CYCLE = 538

// Horizontal IRQ position.
//
// This position is after the DRAM refresh to ensure DRAM refresh does not interfere with the test.
//
// If `IRQ_X_POS` is between 53 and 62 (inclusive), the test output changes every frame as the
// DRAM refresh occurs in the middle of one or more tests.
//
constant IRQ_X_POS = DRAM_REFRESH_CYCLE / 4 + 10


// IRQ ISR
//
// Does nothing.
// Used to synchronise the test to ensure the DRAM refresh does not occur in the middle of the test.
//
// DP unknown
// DB unknown
au()
iu()
code()
function IrqHandler {
    sep     #$20
a8()
    pha
    lda.l   TIMEUP
    pla

    rti
}



// VBlank routine
//
// REQUIRES: 8 bit A, 16 bit Index, DB = 0x80, DP = 0
macro VBlank() {
    assert8a()
    assert16i()

    TextBuffer.VBlank()
}

define VBLANK_READS_JOYPAD

include "../vblank_interrupts.inc"



// Wait 8 cycles and log the value of `RDMPY` to `WMDATA`
//
// KEEP: A, Y
//
// DB = registers
// DP = 0x4200
inline RunOneTest.__WaitAndLogRDMPY_dp4200() {
    assert16a()
    assert8i()

    // Wait 8 cycles
    nop
    nop
    nop
    nop

    // MUST NOT CHANGE the A or Y registers

    // Log `RDMPY` to `WMDATA`
    ldx.b   RDMPYL
    stx.w   WMDATA
    ldx.b   RDMPYH
    stx.w   WMDATA
}



// Process a single `WRMPYB` test, storing the results in `WMDATA`
//
// REQUIRES: H-IRQ enabled with HTIME = IRQ_X_POS
//
// INPUT: A     = WRMPYA
// INPUT: X     = First WRMPYB value
// INPUT: Y     = Second WRMPYB value
// INPUT: WMADD = Buffer to store the results into
//
// OUTPUT: WMADD = buffer after test results
//
// DB = registers
a8()
i8()
code()
function RunOneTest {
    // Access multiplication registers via direct page
    pea     WRMPYA & 0xff00
    pld
// DP = $4200

    // Using Y to retrieve `RDMPY` (and to log inputs)

    // Log inputs
    sta.w   WMDATA      // WRMPYA
    stx.w   WMDATA      // First WRMPYB write
    sty.w   WMDATA      // Second WRMPYB write


    // Transfer X to high byte of A (keep low byte of A unchanged)
    xba
    txa
    xba

    rep     #$20
a16()

    // AA = `WRMPYA` and first `WRMPYB`
    //  Y = second `WRMPYB` value


    // Using `wai` to sleep until after the DRAM-refresh to ensure the DRAM-refresh does
    // not interfere with the test.


    // Wait 2 cycles between WRMPYB writes
    wai
    sta.b   WRMPYA  // Also sets WRMPYB
    sty.b   WRMPYB  // 2 cycles reading `sty.b $03`
    __WaitAndLogRDMPY_dp4200()


    // Wait 3 cycles between WRMPYB writes
    wai
    sta.b   WRMPYA  // Also sets WRMPYB
    sty.w   WRMPYB  // 3 cycles reading `sty.w $4203`
    __WaitAndLogRDMPY_dp4200()


    // Wait 4 cycles between WRMPYB writes
    wai
    sta.b   WRMPYA  // Also sets WRMPYB
    nop             // 2 cycles
    sty.b   WRMPYB  // 2 cycles reading `sty.b $03`
    __WaitAndLogRDMPY_dp4200()


    // Wait 5 cycles between WRMPYB writes
    wai
    sta.b   WRMPYA  // Also sets WRMPYB
    nop             // 2 cycles
    sty.w   WRMPYB  // 3 cycles reading `sty.w $4203`
    __WaitAndLogRDMPY_dp4200()


    // Wait 6 cycles between WRMPYB writes
    wai
    sta.b   WRMPYA  // Also sets WRMPYB
    nop             // 2 cycles
    nop             // 2 cycles
    sty.b   WRMPYB  // 2 cycles reading `sty.b $03`
    __WaitAndLogRDMPY_dp4200()


    // Wait 7 cycles between WRMPYB writes
    wai
    sta.b   WRMPYA  // Also sets WRMPYB
    nop             // 2 cycles
    nop             // 2 cycles
    sty.w   WRMPYB  // 3 cycles reading `sty.w $4203`
    __WaitAndLogRDMPY_dp4200()


    // Wait 8 cycles between WRMPYB writes
    wai
    sta.b   WRMPYA  // Also sets WRMPYB
    nop             // 2 cycles
    nop             // 2 cycles
    nop             // 2 cycles
    sty.b   WRMPYB  // 2 cycles reading `sty.b $03`
    __WaitAndLogRDMPY_dp4200()


    // Wait 9 cycles between WRMPYB writes
    wai
    sta.b   WRMPYA  // Also sets WRMPYB
    nop             // 2 cycles
    nop             // 2 cycles
    nop             // 2 cycles
    sty.w   WRMPYB  // 3 cycles reading `sty.w $4203`
    __WaitAndLogRDMPY_dp4200()


    sep     #$30
a8()
i8()
    pea     0
    pld
// DP = 0
    rts
}



// Preform the `WRMPYB` tests
//
// DB = registers
a8()
i16()
code()
function RunTests {

    // Set `WMDATA` address to `results`
    ldx.w   #results
    lda.b   #results >> 16
    stx.w   WMADD
    sta.w   WMADD + 2


    // Wait until the start of a new frame
    -
        assert(HVBJOY.vBlank == 0x80)
        bit.w   HVBJOY
        bmi     -


    // Setup IRQ interrupts

    ldx.w   #IRQ_X_POS
    stx.w   HTIME

    // Enable IRQ Interrupts (and disable NMI interrupts)
    lda.b   #NMITIMEN.hCounter
    sta.w   NMITIMEN

    cli
    wai


    sep     #$30
a8()
i8()
    assert(N_TESTS == 1 + 9)

    lda.w   test_a
    ldx.w   test_b1
    ldy.w   test_b2
    jsr     RunOneTest

    variable _i = 0
    while _i < 9 {
        lda.w   test_a
        ldx.w   test_b1
        ldy.b   #0x80 >> _i
        jsr     RunOneTest

        _i = _i + 1
    }


    rep     #$10
i16()

    // Disable IRQ interrupts and re-enable VBlank interrupts
    stz.w   NMITIMEN
    EnableVblankInterrupts()

    rts
}



// Print the results to the TextBuffer.
//
// DB = registers
a8()
i16()
code()
function PrintResults {

    // Set `WMDATA` address to `results`
    ldx.w   #results
    lda.b   #results >> 16
    stx.w   WMADD
    sta.w   WMADD + 2


    // Print the "selectedInput" cursor
    TextBuffer.SetCursor(0, 0)

    lda.b   #0
    CursorLoop:
        sta.w   loopCounter

        cmp.w   selectedInput
        bne     +
            TextBuffer.PrintStringLiteral("__ ")
            bra     ++
        +
            TextBuffer.PrintStringLiteral("   ")
        +

        lda.w   loopCounter
        inc
        cmp.b   #testInputs.size
        bcc     CursorLoop


    // Print header
    TextBuffer.SetCursor(0, 1)
    TextBuffer.PrintStringLiteral(" A B1 B2  2cy  3cy  4cy  5cy")
    TextBuffer.PrintStringLiteral("          6cy  7cy  8cy  9cy")

    jsr     TextBuffer.NewLine


    // Print test results
    lda.b   #N_TESTS
    sta.w   loopCounter

    Loop:
        assert(BYTES_PER_TEST == 3 + 8 * 2)

        jsr     _PrintByte
        jsr     _PrintByte
        jsr     _PrintByte

        jsr     _PrintWord
        jsr     _PrintWord
        jsr     _PrintWord
        jsr     _PrintWord

        TextBuffer.PrintStringLiteral("         ")

        jsr     _PrintWord
        jsr     _PrintWord
        jsr     _PrintWord
        jsr     _PrintWord

        dec.w   loopCounter
        bne     Loop

    rts
}



// Print the next byte from `WMDATA` to the TextBuffer
//
// INPUT: WMADD  = byte to print
// OUTPUT: WMADD = data after byte
//
// DB = registers
a8()
i16()
code()
function _PrintByte {
    lda.w   WMDATA
    jmp     TextBuffer.PrintHexSpace_8A
}



// Print the next word from `WMDATA` to the TextBuffer
//
// INPUT: WMADD  = byte to print
// OUTPUT: WMADD = data after byte
//
// DB = registers
a8()
i16()
code()
function _PrintWord {
    lda.w   WMDATA
    xba
    lda.w   WMDATA
    xba
    tay
    jmp     TextBuffer.PrintHexSpace_16Y
}



// Process control pad
//
// DB = registers
a8()
i16()
code()
function ProcessJoypad {
    sep     #$10
i8()
    ldx.w   selectedInput

    // Process B and Y buttons
    lda.w   joypadPressed + 1
    bit.b   #JOYH.b
    beq     +
        inx
    +
    bit.b   #JOYH.y
    beq     +
        dex
        bpl     +
            ldx.b   #testInputs.size - 1
    +

    cpx.b   #testInputs.size
    bcc     +
        ldx.b   #0
    +
    stx.w   selectedInput


    // Process D-Pad

    lda.w   joypadPressed + 1
    bit.b   #JOYH.left
    beq     +
        dec.w   testInputs,x
    +

    bit.b   #JOYH.right
    beq     +
        inc.w   testInputs,x
    +

    bit.b   #JOYH.up
    beq     +
        lda.w   testInputs,x
        clc
        adc.b   #0x10
        sta.w   testInputs,x

        lda.w   joypadPressed + 1
    +

    bit.b   #JOYH.down
    beq     +
        lda.w   testInputs,x
        sec
        sbc.b   #0x10
        sta.w   testInputs,x

        lda.w   joypadPressed + 1
    +

    rep     #$10
i16()

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


    EnableVblankInterrupts()

    jsr     WaitFrame

    lda.b   #0x0f
    sta.w   INIDISP


    // Set initial test values
    lda.b   #0xff
    sta.w   test_a

    lda.b   #0xff
    sta.w   test_b1
    sta.w   test_b2


    MainLoop:
        jsr     WaitFrame

        jsr     ProcessJoypad
        jsr     RunTests
        jsr     PrintResults

        jmp     MainLoop
}


namespace Resources {

Palette:
    dw  ToPalette(0, 0, 0)
    dw  ToPalette(31, 31, 31)
constant Palette.size = pc() - Palette
}

finalizeMemory()



