// HDMA textbox wipe animation.
//
// This animation is preformed by modifying a HDMA buffer in the VBlank routine
// (as opposed to a double-buffered HDMA effect).
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "HDMA TEXTBOX WIPE"
define VERSION = 1


architecture wdc65816-strict


include "../common.inc"


createCodeBlock(code,       0x808000, 0x80ffaf)

createRamBlock(zeropage,    0x000000, 0x0000ff)
createRamBlock(lowram,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)
createRamBlock(wram7e,      0x7e2000, 0x7effff)


include "../reset_handler.inc"
include "../break_handler.inc"
include "../dma_forceblank.inc"


constant VRAM_BG1_MAP_WADDR   = 0x0000
constant VRAM_BG2_MAP_WADDR   = 0x0400
constant VRAM_BG3_MAP_WADDR   = 0x0800

constant VRAM_BG1_TILES_WADDR = 0x1000
constant VRAM_BG2_TILES_WADDR = 0x3000
constant VRAM_BG3_TILES_WADDR = 0x5000

constant VRAM_OBJ_TILES_WADDR = 0x6000


namespace AnimationState {
    createEnum()
        enum(SHOW_TEXTBOX_ANIMATION)
        enum(TEXTBOX_OPEN_WAIT)
        enum(HIDE_TEXTBOX_ANIMATION)
        enum(TEXTBOX_CLOSED_WAIT)
    endEnum()
}

// Number of frames to wait between animations
constant ANIMATION_WAIT_FRAMES = 60

// Height of the textbox before switching to `TEXTBOX_OPEN_WAIT` state.
constant MAX_TEXTBOX_HEIGHT = 64



constant HDMA_BUFFER_SIZE = 32

// HDMA buffer (in RAM)
// (in low-RAM)
allocate(hdmaBuffer, lowram, HDMA_BUFFER_SIZE)


// Animation state variable
//
// (`AnimationState` enum, low-RAM)
allocate(animationState, lowram, 1)


// Animation timer, used by the TEXTBOX_OPEN and TEXTBOX_CLOSED states.
//
// (uint8, lowRAM)
allocate(animationTimer, lowram, 1)



// Visible textbox height, in scanlines.
//
// Used by the VBlank routine to preform the textbox wipe animation.
//
// This value MUST BE < 128.
//
// If this value is 0, there will be no textbox on screen.
//
// (uint8, low-RAM)
allocate(textboxHeight, lowram, 1)



// Setup the textbox wipe animation HDMA effect.
//
// Uses DMA channel 7.
//
// REQUIRES: 8 bit A, 16 bit Index, DB = 0x80, DP = 0
// REQUIRES: In force-blank, HDMA disabled
a8()
i16()
code()
function SetupHdma {

    // Copy `HdmaTable` (in ROM) to `hdmaBuffer` (in low-RAM)
    ldx.w   #HdmaTable.size - 1
    Loop:
        lda.l   HdmaTable,x
        sta.w   hdmaBuffer,x
        dex
        bpl     Loop


    // Reset `textboxHeight` and `animationState`
    stz.w   textboxHeight

    assert(AnimationState.SHOW_TEXTBOX_ANIMATION == 0)
    stz.w   animationState


    // HDMA to `TM`
    lda.b   #DMAP.direction.toPpu | DMAP.transfer.one
    sta.w   DMAP7

    lda.b   #TM
    sta.w   BBAD7

    // HDMA table address
    assertLowRam(hdmaBuffer)
    ldx.w   #hdmaBuffer
    stx.w   A1T7
    stz.w   A1B7

    rts
}




// VBlank routine.
//
// REQUIRES: 8 bit A, 16 bit Index, DB = 0x80, DP = 0
macro VBlank() {
    assert8a()
    assert16i()

    assertLowRam(hdmaBuffer)
    assertLowRam(textboxHeight)

    // Update the height of the textbox in the hdmaBuffer's HDMA-Table
    //
    // This is safe as HDMA is not active during VBlank.

    lda.w   textboxHeight
    sta.w   hdmaBuffer + TEXTBOX_HEIGHT_OFFSET


    // Enable HDMA.
    // HDMA should be enabled during VBlank.
    // There is no need to write to `HDMAEN` on every VBlank, it can be written to on a single VBlank.
    lda.b   #HDMAEN.dma7
    sta.w   HDMAEN
}

include "../vblank_interrupts.inc"



// Process one frame of the textbox-wipe animation.
//
// REQUIRES: 8 bit A, 16 bit Index, DP = 0, DB access low-RAM
a8()
i16()
code()
function Process {
    lda.w   animationState

    cmp.b   #AnimationState.SHOW_TEXTBOX_ANIMATION
    beq     ShowTextboxAnimation

    cmp.b   #AnimationState.TEXTBOX_OPEN_WAIT
    beq     TextboxOpenWait

    cmp.b   #AnimationState.HIDE_TEXTBOX_ANIMATION
    beq     HideTextboxAnimation

    assert(AnimationState.__ENUM__.count == 4)
    bra     TextboxClosedWait



ShowTextboxAnimation:
    lda.w   textboxHeight
    inc
    sta.w   textboxHeight
    cmp.b   #MAX_TEXTBOX_HEIGHT
    bcc     +
        // textbox is completely visible, change animation state
        lda.b   #AnimationState.TEXTBOX_OPEN_WAIT
        sta.w   animationState

        lda.b   #ANIMATION_WAIT_FRAMES
        sta.w   animationTimer
    +
    rts


TextboxOpenWait:
    dec.w   animationTimer
    bne     +
        wdm #1

        // Timer has ended, change animation state
        lda.b   #AnimationState.HIDE_TEXTBOX_ANIMATION
        sta.w   animationState
    +
    rts


HideTextboxAnimation:
    dec.w   textboxHeight
    bne     +
        // textboxHeight == 0, change animation state

        lda.b   #AnimationState.TEXTBOX_CLOSED_WAIT
        sta.w   animationState

        lda.b   #ANIMATION_WAIT_FRAMES
        sta.w   animationTimer
    +
    rts


TextboxClosedWait:
    dec.w   animationTimer
    bne     +
        // Timer has ended, change animation state
        stz.w   textboxHeight

        lda.b   #AnimationState.SHOW_TEXTBOX_ANIMATION
        sta.w   animationState
    +
    rts
}



// Setup PPU registers and load data to the PPU.
//
// REQUIRES: 8 bit A, 16 bit Index, DB = 0x80, DP = 0
// REQUIRES: In force-blank
a8()
i16()
code()
function SetupPpu {
    lda.b   #BGMODE.mode1
    sta.w   BGMODE

    lda.b   #OBSEL.size.s8_16 | (VRAM_OBJ_TILES_WADDR / OBSEL.base.walign) << OBSEL.base.shift
    sta.w   OBSEL

    lda.b   #(VRAM_BG1_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG1SC

    lda.b   #(VRAM_BG2_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG2SC

    lda.b   #(VRAM_BG3_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG3SC

    lda.b   #((VRAM_BG1_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg1.shift) | ((VRAM_BG2_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg2.shift)
    sta.w   BG12NBA

    lda.b   #(VRAM_BG3_TILES_WADDR / BG34NBA.walign) << BG34NBA.bg3.shift
    sta.w   BG34NBA


    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Bg_Palette)

    lda.b   #128
    sta.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Obj_Palette)


    ldx.w   #VRAM_BG1_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg1_Tiles)

    ldx.w   #VRAM_BG2_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg2_Tiles)

    ldx.w   #VRAM_BG3_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg3_Tiles)

    ldx.w   #VRAM_BG1_MAP_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg1_Tilemap)

    ldx.w   #VRAM_BG2_MAP_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg2_Tilemap)

    ldx.w   #VRAM_BG3_MAP_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg3_Tilemap)


    ldx.w   #VRAM_OBJ_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Obj_Tiles)

    stz.w   OAMADDL
    stz.w   OAMADDH
    Dma.ForceBlank.ToOam(Resources.Obj_Oam)



    lda.b   #TM.bg1 | TM.bg2 | TM.bg3 | TM.obj
    sta.w   TM

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

    jsr     SetupPpu
    jsr     SetupHdma

    EnableVblankInterrupts()

    jsr     WaitFrame

    lda.b   #0x0f
    sta.w   INIDISP


    MainLoop:
        jsr     Process

        jsr     WaitFrame

        jmp     MainLoop
}




// The byte offset, within HdmaTable, for the height of the textbox.
constant TEXTBOX_HEIGHT_OFFSET = 2


// HDMA Table for the `TM` register (one register transfer pattern).
HdmaTable:
    db  32              // 32 scanlines, non-repeat entry
        db  0x13        // TM = BG1, BG2, OBJ

    db  64              // 64 scanlines, non-repeat entry
        db  0x04        // TM = BG3

    db  1               // 1 scanline
        db  0x13        // TM = BG1, BG2, OBJ

    db  0               // End HDMA table

constant HdmaTable.size = pc() - HdmaTable

assert(HDMA_BUFFER_SIZE > HdmaTable.size)




// Resources
// =========

namespace Resources {
    insert Bg_Palette,  "../../gen/hdma-textbox-wipe/bg1.palette"

    insert Bg1_Tiles,   "../../gen/hdma-textbox-wipe/bg1.4bpp"
    insert Bg1_Tilemap, "../../gen/hdma-textbox-wipe/bg1.tilemap"

    insert Bg2_Tiles,   "../../gen/hdma-textbox-wipe/bg2.4bpp"
    insert Bg2_Tilemap, "../../gen/hdma-textbox-wipe/bg2.tilemap"

    insert Bg3_Tiles,   "../../gen/hdma-textbox-wipe/bg3.2bpp"
    insert Bg3_Tilemap, "../../gen/hdma-textbox-wipe/bg3.tilemap"

    insert Obj_Tiles,   "../../gen/hdma-textbox-wipe/obj-4bpp-tiles.tiles"
    insert Obj_Palette, "../../gen/hdma-textbox-wipe/obj-4bpp-tiles.pal"
    insert Obj_Oam,     "../../gen/hdma-textbox-wipe/oam.bin"

    assert(Obj_Oam.size == 544)
}


