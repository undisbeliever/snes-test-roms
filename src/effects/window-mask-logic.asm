// An interactive test rom to demonstrate all of the window mask logic settings.
//
// Copyright (c) 2023, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define ROM_NAME = "WINDOW MASK LOGIC"
define VERSION = 0

define MEMORY_MAP = LOROM
define ROM_SIZE = 1

define ROM_SPEED = fast
define REGION = Japan


define VBLANK_READS_JOYPAD


architecture wdc65816-strict

include "../common.inc"


createCodeBlock(code,       0x808000, 0x80bfff)
createCodeBlock(rodata0,    0x80c000, 0x80ffaf)

createRamBlock(zeropage,    0x000000, 0x0000ff)
createRamBlock(lowram,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)
createRamBlock(wram7e,      0x7e2000, 0x7effff)


constant VRAM_BG1_MAP_WADDR   = 0x0000
constant VRAM_BG1_TILES_WADDR = 0x1000

constant VRAM_TEXTBUFFER_MAP_WADDR   = VRAM_BG1_MAP_WADDR
constant VRAM_TEXTBUFFER_TILES_WADDR = VRAM_BG1_TILES_WADDR


include "../reset_handler.inc"
include "../break_handler.inc"
include "../dma_forceblank.inc"
include "../textbuffer.inc"


// zero-page temporary word variables
allocate(zpTmp0, zeropage, 2)
allocate(zpTmp1, zeropage, 2)

// zero-page temporary far pointer
allocate(zpTmpPtr, zeropage, 3)


// The selected logic and invert settings for the backdrop layer
//
//  ----21ll
//      1 = invert window 1
//      2 = invert window 2
//     ll = window mask logic
allocate(selectedMaskLogic, zeropage, 1)
    constant selectedMaskLogic.LOGIC_MASK   = 0b0011
    constant selectedMaskLogic.INVERT_WIN_1 = 0b0100
    constant selectedMaskLogic.INVERT_WIN_2 = 0b1000


// Options
allocate(options, zeropage, 1)
    constant options.SHOW_WIN1         = WSEL.win1.enable << WOBJSEL.color.shift
    constant options.SHOW_WIN2         = WSEL.win2.enable << WOBJSEL.color.shift
    constant options.SHOW_INSTRUCTIONS = 1


// Register shadow variable for the WOBJSEL register
allocate(wobjselShadow, zeropage, 1)

// Register shadow variable for the WOBJLOG register
allocate(wobjlogShadow, zeropage, 1)



// Setup PPU
//
// REQUIRES: 8 bit A, 16 bit Index, DB access registers, DP = 0
a8()
i16()
code()
function SetupPpu {
    jsr     ResetRegisters

    // Window settings

    // Disable windows for backgrounds and objects
    stz.w   TMW
    stz.w   TSW

    // Color math settings

    // Clip colors to black inside the color window
    // Disable color math outside the color window
    // Use fixed color for color math
    lda.b   #CGWSEL.clip.inside | CGWSEL.prevent.outside
    sta.w   CGWSEL

    // Color math addition
    // Enable color math on backdrop
    lda.b   #CGADSUB.color.add | CGADSUB.enable.backdrop
    sta.w   CGADSUB

    // Set fixed color to violet
    lda.b   #COLDATA.plane.blue  | 31
    sta.w   COLDATA
    lda.b   #COLDATA.plane.green | 0
    sta.w   COLDATA
    lda.b   #COLDATA.plane.red   | 15
    sta.w   COLDATA


    // Setup and HDMA channels 6 & 7 to the 2 windows

    // HDMA channel 6 to WH0 & WH1
    ldx.w   #DMAP.direction.toPpu | DMAP.transfer.two | (WH0 << 8)
    stx.w   DMAP6       // also sets BBAD6

    ldx.w   #HdmaTables.Window1
    lda.b   #HdmaTables.Window1 >> 16
    stx.w   A1T6
    sta.w   A1B6

    // HDMA channel 7 to WH2 & WH3
    ldx.w   #DMAP.direction.toPpu | DMAP.transfer.two | (WH2 << 8)
    stx.w   DMAP7       // also sets BBAD7

    ldx.w   #HdmaTables.Window2
    lda.b   #HdmaTables.Window2 >> 16
    stx.w   A1T7
    sta.w   A1B7


    // Setup text buffer

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

    jmp     TextBuffer.InitAndTransferToVram
}



// VBlank routine
//
// REQUIRES: 8 bit A, 16 bit Index, DB = 0x80, DP = 0
macro VBlank() {
    assert8a()
    assert16i()

    // Enable HDMA 6 & 7
    // (Must occur in VBlank to prevent glitches)
    lda.b   #HDMAEN.dma7 | HDMAEN.dma6
    sta.w   HDMAEN


    // Update window mask logic
    lda.b   wobjselShadow
    sta.w   WOBJSEL

    lda.b   wobjlogShadow
    sta.w   WOBJLOG


    TextBuffer.VBlank()


    // Enable display, full brightness
    lda.b   #0x0f
    sta.w   INIDISP
}

include "../vblank_interrupts.inc"



a8()
i16()
code()
function Init {
    stz.b   selectedMaskLogic

    lda.b   #0xff
    sta.b   options

FallThrough:
}



a8()
i16()
code()
function UpdateWindowLogicAndText {
    assert(Init.FallThrough == pc())

    lda.b   options
    and.b   #(WSEL.win1.enable | WSEL.win2.enable) << WOBJSEL.color.shift
    sta.b   wobjselShadow

    lda.b   selectedMaskLogic
    bit.b   #selectedMaskLogic.INVERT_WIN_1
    beq     +
        lda.b   #WSEL.win1.outside << WOBJSEL.color.shift
        tsb.b   wobjselShadow
    +

    lda.b   selectedMaskLogic
    bit.b   #selectedMaskLogic.INVERT_WIN_2
    beq     +
        lda.b   #WSEL.win2.outside << WOBJSEL.color.shift
        tsb.b   wobjselShadow
    +

    lda.b   selectedMaskLogic
    and.b   #selectedMaskLogic.LOGIC_MASK
    assert(WOBJLOG.color.shift == 2)
    asl
    asl
    sta.b   wobjlogShadow


    // Update text

    jsr     TextBuffer.ClearCharBufferAndResetCursor

    TextBuffer.SetCursor(0, 1)
    TextBuffer.PrintString(Strings.Header)


    TextBuffer.SetCursor(0, 5)

    rep     #$30
a16()
    lda.b   selectedMaskLogic
    and.w   #selectedMaskLogic.LOGIC_MASK
    asl
    tax
    lda.l   Strings.LogicMaskStringTable,x
    tax

    sep     #$20
a8()
    lda.b   #Strings.LogicMaskStringTable << 16
    jsr     TextBuffer.PrintString


    lda.b   options
    bit.b   #options.SHOW_WIN1
    beq     ++
        TextBuffer.SetCursor(0, 7)
        lda.b   selectedMaskLogic
        bit.b   #selectedMaskLogic.INVERT_WIN_1
        beq     +
            TextBuffer.PrintString(Strings.Invert)
        +
        TextBuffer.PrintString(Strings.Window1)
    +


    lda.b   options
    bit.b   #options.SHOW_WIN2
    beq     ++
        TextBuffer.SetCursor(0, 8)
        lda.b   selectedMaskLogic
        bit.b   #selectedMaskLogic.INVERT_WIN_2
        beq     +
            TextBuffer.PrintString(Strings.Invert)
        +
        TextBuffer.PrintString(Strings.Window2)
    +

    lda.b   options
    bit.b   #options.SHOW_INSTRUCTIONS
    beq     +
        TextBuffer.SetCursor(0, 18)
        TextBuffer.PrintString(Strings.Instructions)
    +

    rts
}


a8()
i16()
code()
function Process {
    lda.w   joypadPressed + 1

    bit.b   #JOYH.right
    beq     +
        inc.b   selectedMaskLogic
        jmp     UpdateWindowLogicAndText
    +

    bit.b   #JOYH.left
    beq     +
        dec.b   selectedMaskLogic
        jmp     UpdateWindowLogicAndText
    +

    bit.b   #JOYH.select
    beq     +
        lda.b   #options.SHOW_INSTRUCTIONS
        bra     ToggleOptionFlag
    +


    lda.w   joypadPressed

    bit.b   #JOYL.l
    beq     +
        lda.b   #options.SHOW_WIN1
        bra     ToggleOptionFlag
    +

    bit.b   #JOYL.r
    beq     +
        lda.b   #options.SHOW_WIN2
        bra     ToggleOptionFlag
    +

    rts


ToggleOptionFlag:
    // A = option flag to flip
    eor.b   options
    sta.b   options
    jmp     UpdateWindowLogicAndText
}




a8()
i16()
code()
function Main {
    jsr     SetupPpu

    jsr     Init

    EnableVblankInterrupts()


    MainLoop:
        jsr     WaitFrame
        jsr     Process
        bra     MainLoop
}



namespace HdmaTables {

constant N_SEGMENTS = 5
constant W1_HEIGHT = 35
constant W1_PADDING = (224 - W1_HEIGHT * N_SEGMENTS) / (N_SEGMENTS + 1)

constant W1_LEFT = 160
constant W1_RIGHT = 210
constant W2_WIDTH = W1_RIGHT - W1_LEFT + 1

constant W2_MARGIN = 5
constant W2_HEIGHT = W1_HEIGHT - W2_MARGIN * 2
constant W2_PADDING = W1_PADDING + W2_MARGIN * 2

constant W2_X_START = W1_LEFT - W2_HEIGHT / 2 - 4
constant W2_X_END   = W1_RIGHT + W2_HEIGHT / 2 + 4

Window1:
    assert(W1_PADDING < 0x80)
    assert(W1_HEIGHT < 0x80)

    variable _segment = 0
    while _segment < N_SEGMENTS {
        db  W1_PADDING, 0xff,    0          // disable window
        db  W1_HEIGHT,  W1_LEFT, W1_RIGHT   // rectangle window

        _segment = _segment + 1
    }
    db  1, 0xff, 0                          // disable window
    db  0                                   // end HDMA table


// Window 2 - diamonds
// (Chose diamonds over circles as diamonds have a sharper intersection then circles)
Window2:
    assert(W2_PADDING < 0x80)
    assert(W2_HEIGHT < 0x80)

    db  W2_PADDING - W2_MARGIN, 0xff, 0     // disable window

    variable _segment = 0
    while _segment < N_SEGMENTS {
        variable _left = W2_X_START + (W2_X_END - W2_X_START) * _segment / (N_SEGMENTS - 1)
        variable _right = _left
        variable _j = 0
                                                // Diamond
        db  0x80 | W2_HEIGHT                    // HDMA repeat mode
        while _j < W2_HEIGHT {
            db  _left, _right                         // left/right window values

            if _j < W2_HEIGHT / 2 {
                _left = _left - 1
                _right = _right + 1
            } else {
                _left = _left + 1
                _right = _right - 1
            }
            _j = _j + 1
        }

        db  W2_PADDING, 0xff, 0             // disable window

        _segment = _segment + 1
    }
    db  0                                   // end HDMA table

}


namespace Resources {

rodata(rodata0)
Palette:
    dw  ToPalette(31, 31, 31)
    dw  ToPalette(0, 0, 0)
constant Palette.size = pc() - Palette
}


rodata(rodata0)
namespace Strings {
    Header:
        db  "WINDOW MASK\nLOGIC", 0


    LogicMaskStringTable:
        dw  Mask0
        dw  Mask1
        dw  Mask2
        dw  Mask3

    Mask0:
        assert(WOBJLOG.logic.or == 0)
        db  "OR", 0

    Mask1:
        assert(WOBJLOG.logic.and == 1)
        db  "AND", 0

    Mask2:
        assert(WOBJLOG.logic.xor == 2)
        db  "XOR", 0

    Mask3:
        assert(WOBJLOG.logic.xnor == 3)
        db  "XNOR", 0


    Invert:
        db  "INVERT ", 0

    Window1:
        db  "WIN 1", 0

    Window2:
        db  "WIN 2", 0


    Instructions:
        db        "RIGHT: Next"
        db  "\n", "LEFT:  Previous"
        db  "\n",
        db  "\n", "Toggle:"
        db  "\n", "  L: WIN 1"
        db  "\n", "  R: WIN 2"
        db  "\n", "SEL: Instructions"
        db  0
}


finalizeMemory()

