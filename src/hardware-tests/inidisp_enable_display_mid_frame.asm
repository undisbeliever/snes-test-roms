// A simple test to show what happens when you enable the display mid frame
//
// Controls:
//          D-pad: move enable display time
//         Select: Move enable display to H-Blank
//              A: Change background/tile modes
//
//
// Copyright (c) 2019, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "ENABLE DISPLAY MID FRAME"
define VERSION = 2

define USES_IRQ_INTERRUPTS


architecture wdc65816-strict

include "../common.inc"

createCodeBlock(code,       0x808000, 0x80ffaf)

createRamBlock(lowram,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)

include "../reset_handler.inc"
include "../break_handler.inc"
include "../nmi_handler.inc"
include "../dma_forceblank.inc"

// BG2-4 uses WADDR 0
constant VRAM_OBJ_TILES_WADDR = 0x6000
constant VRAM_BG1_TILES_WADDR = 0x1000
constant VRAM_BG1_MAP_WADDR   = 0x1400


// Temporary variables
allocate(_tmp, lowram, 2)

// The current DisplayModeSettings entry to load
// (word index)
allocate(displayModeIndex, lowram, 2)

// The current joypad state
// Call `UpdateJoypad` to update this variable
// (uint16, JOY state)
allocate(joypad, lowram, 2)


// The current X/Y position to fire IRQ interrupt at
// (2x uint16)
allocate(irq_x, lowram, 2)
allocate(irq_y, lowram, 2)

constant IRQ_X_MAX = 339
constant IRQ_Y_MAX = 261

constant IRQ_X_START = 15
constant IRQ_Y_START = 89



// IRQ ISR
//
// Enable display (at full brightness)
IrqHandler:
    sep     #$20
a8()
    pha
        // This ISR uses long addressing (faster than `phk : plb`)

        // Enable display - full brightness
        lda.b   #0x0f
        sta.l   INIDISP

        lda.l   TIMEUP  // Required to escape IrqHandler

    pla
    rti



// Waits until the start of VBlank
// REQUIRES: NMI enabled
au()
iu()
code()
function WaitFrame {
    php
    sep     #$20
a8()
    // Wait until end of vBlank (if in vBlank)
    -
        lda.l   HVBJOY
        bmi     -

    // Wait until start of next vBlank
    -
        wai
        assert(HVBJOY.vBlank == 0x80)
        lda.l   HVBJOY
        bpl     -

    plp

    rts
}


// Reads the state of the joypad 1, saving it in the `joypad` variable
// REQUIRES: 8 bit A, 16 bit Index, DB access registers
a8()
i16()
code()
function UpdateJoypad {

    Loop:
        // Wait until autoJoy bit is cleared
        lda.b   #HVBJOY.autoJoy

        -
            bit.w   HVBJOY
            bne     -

        ldx.w   JOY1

        // Confirm we have not entered autoJoy when readying JOY1
        // We need to do this as this program does very little during vBlank
        bit.w   HVBJOY
        bne     Loop

        // Confirm this is a stable read
        cpx.w   JOY1
        bne     Loop

    rep     #$30
a16()
    txa
    bit.w   #JOY.type.mask
    beq     +
        lda.w   #0
    +
    tax
    sta.w   joypad

    sep     #$20
a8()

    rts
}


// Setup and initialize the PPU
// REQUIRES: 8 bit A, 16 bit Index, DB access registers
// MODIFIES: enables force-blank
macro SetupPpu() {
    assert8a()
    assert16i()

    // Enable NMI and autoJoy (just in case)
    lda.b   #NMITIMEN.vBlank | NMITIMEN.autoJoy
    sta.w   NMITIMEN

    jsr     WaitFrame


    // Set PPU registers

    lda.b   #INIDISP.force | 0xf
    sta.w   INIDISP

    lda.b   #(VRAM_BG1_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG1SC

    lda.b   #(VRAM_BG1_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg1.shift
    sta.w   BG12NBA

    // BG2-BG4 have a TILE & MAP WADDR of 0 (as set by ResetRegisters)

    lda.b   #OBSEL.size.s8_32 | (VRAM_OBJ_TILES_WADDR / OBSEL.base.walign) << OBSEL.base.shift
    sta.w   OBSEL


    // Fill bottom half of CGRAM with a red pattern.
    // 16 colour gradient of mid-red to bright-red, repeated 8 times
    stz.w   CGADD

    ldx.w   #128
    -
        txa
        dec
        eor.b   #0xff
        and.b   #0x0f
        ora.b   #0x10
        sta.w   CGDATA
        stz.w   CGDATA

        dex
        bne     -


    // Fill top half of CGRAM with a bright green pattern.
    // 16 colour gradient of mid-green to bright-green, repeated 8 times
    sep     #$30
    rep     #$20
a16()
i8()
    ldx.b   #128
    -
        txa
        dec
        eor.w   #0xffff
        and.w   #0x000f
        ora.w   #0x0010
        asl
        asl
        asl
        asl
        asl

        tay
        sty.w   CGDATA
        xba
        tay
        sty.w   CGDATA

        dex
        bne     -

    rep     #$30
    sep     #$20
a8()
i16()


    // Load obj palette
    lda.b   #128
    sta.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Obj_Palette)

    // Load OAM
    stz.w   OAMADDL
    stz.w   OAMADDH
    Dma.ForceBlank.ToOam(Resources.Obj_Oam)

    // Set size of sprites used in Obj_Oam to large (32x32)
    lda.b   #1
    stz.w   OAMADDL
    sta.w   OAMADDH

    ldx.w   #Resources.Obj_Oam.size / 4 / 4
    lda.b   #%10101010
    -
        sta.w   OAMDATA
        dex
        bne     -


    // Load Tiles
    ldx.w   #VRAM_BG1_MAP_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg1_Tilemap)

    ldx.w   #VRAM_OBJ_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Obj_Tiles)

    // Load DisplayMode tiles/Settings
    // -------------------------------

    // Verify displayModeIndex in bounds
    ldx.w   displayModeIndex
    cpx.w   #DisplayModeSettings.TableSize
    bcc     +
        ldx.w   #0
    +
    stx.w   displayModeIndex

    lda.w   DisplayModeSettings.BgMode,x
    sta.w   BGMODE

    lda.w   DisplayModeSettings.Tm,x
    sta.w   TM


    // Transfer tiles to VRAM

    ldx.w   #VRAM_BG1_TILES_WADDR
    stx.w   VMADD

    rep     #$30
a16()

    ldx.w   displayModeIndex
    lda.l   DisplayModeSettings.Tiles,x
    sta.w   _tmp
    lda.l   DisplayModeSettings.Tiles.size,x
    tay

    sep     #$20
a8()
    lda.l   DisplayModeSettings.Tiles + 2,x
    ldx.w   _tmp

    jsr     Dma.ForceBlank.TransferToVram


    // Transfer palette to CGRAM

    rep     #$30
a16()

    ldx.w   displayModeIndex
    lda.l   DisplayModeSettings.Palette,x
    sta.w   _tmp
    lda.l   DisplayModeSettings.Palette.size,x
    tay

    sep     #$20
a8()
    lda.l   DisplayModeSettings.Palette + 2,x
    ldx.w   _tmp

    stz.w   CGADD
    jsr     Dma.ForceBlank.TransferToCgram


    // Enable NMI and autoJoy
    lda.b   #NMITIMEN.vBlank | NMITIMEN.autoJoy
    sta.w   NMITIMEN

    jsr     WaitFrame

    lda.b   #0x0f
    sta.w   INIDISP
}



au()
iu()
code()
function Main {
    rep     #$30
a16()
i16()

    stz.w   displayModeIndex

    // Initialize IRQ position
    ldx.w   #IRQ_X_START
    stx.w   irq_x
    stx.w   HTIME

    ldy.w   #IRQ_Y_START
    sty.w   irq_y
    sty.w   VTIME

Setup:
    rep     #$30
    sep     #$20
a8()
i16()
    cli     // Enable IRQ interrupts

    SetupPpu()

    // Enable NMI, IRQ and autoJoy
    lda.b   #NMITIMEN.vBlank | NMITIMEN.vCounter | NMITIMEN.hCounter | NMITIMEN.autoJoy
    sta.w   NMITIMEN

    // Wait until user lets go of A
    -
        jsr     WaitFrame
        jsr     UpdateJoypad

        lda.w   joypad
        and.b   #JOYL.a
        bne     -

    a8()
    i16()
    MainLoop:
        jsr     WaitFrame

        // Force-blank, full brightness
        // (IRQ will enable screen mid frame)
        lda.b   #INIDISP.force | 0x0f
        sta.w   INIDISP

        jsr     UpdateJoypad

        lda.w   joypad
        bit.b   #JOYL.a
        bne     GotoNextDisplayMode


        // Update IRQ x/y position
        ldx.w   irq_x
        ldy.w   irq_y

        lda.w   joypad + 1

        bit.b   #JOYH.select
        beq     +
            // select pressed

            // Mesen-S event viewer shows 24 dots between IRQ triggering and the store to INIDISP.
            // -16 dots for tile buffer pre-load.
            // -8 dots produces the most interesting glitches on my SFC.

            cpx.w   #256
            ldx.w   #IRQ_X_MAX - 24 - 16 - 8

            // Go to the previous scanline if not in VBlank
            bcc     MoveUp
        +
        bit.b   #JOYH.up
        beq     +
        MoveUp:
            // up pressed
            dey
            bpl     +
                ldy.w   #IRQ_Y_MAX
        +
        bit.b   #JOYH.down
        beq     +
            // down pressed
            iny
            cpy.w   #IRQ_Y_MAX + 1
            bcc     +
                ldy.w   #0
        +
        bit.b   #JOYH.left
        beq     +
            // left pressed
            dex
            bpl     +
                ldx.w   #IRQ_X_MAX
                dey
        +
        bit.b   #JOYH.right
        beq     +
            // right pressed
            inx
            cpx.w   #IRQ_X_MAX + 1
            bcc     +
                ldx.w   #0
                iny
        +

        stx.w   irq_x
        stx.w   HTIME

        sty.w   irq_y
        sty.w   VTIME

        jmp     MainLoop


GotoNextDisplayMode:
    rep     #$31
a16()
i16()
    lda.w   displayModeIndex
    // carry clear
    adc.w   #DisplayModeSettings.size
    sta.w   displayModeIndex

    jmp     Setup
}




DisplayModeSettings:
namespace DisplayModeSettings {
    struct(pc())
        field(BgMode, 1)
        field(Tm, 1)
        field(Tiles,  3)
        field(Tiles.size, 2)
        field(Palette, 3)
        field(Palette.size, 2)
    endstruct()

    macro _entry(tiles, palette, bgMode, evaluate tm) {
        db  {bgMode}
        db  {tm}
        dl  Resources.{tiles}
        dw  Resources.{tiles}.size
        dl  Resources.{palette}
        dw  Resources.{palette}.size
    }

    _entry(Tiles_4bpp, Palette_4bpp, 1, TM.bg1 | TM.obj)
    _entry(Tiles_4bpp, Palette_4bpp, 1, TM.bg1)
    _entry(Tiles_2bpp, Palette_2bpp, 0, TM.bg1 | TM.obj)
    _entry(Tiles_2bpp, Palette_2bpp, 0, TM.bg1)
    _entry(Tiles_8bpp, Palette_8bpp, 3, TM.bg1 | TM.obj)
    _entry(Tiles_8bpp, Palette_8bpp, 3, TM.bg1)
    _entry(Tiles_8bpp, Palette_8bpp, 3, TM.obj)

    constant TableSize = pc() - DisplayModeSettings.BgMode
    assert(TableSize % size == 0)
}

namespace Resources {
    insert Bg1_Tilemap,  "../../gen/example-backgrounds/bricks-tilemap.bin"

    insert Tiles_8bpp,   "../../gen/example-backgrounds/bricks-8bpp-tiles.tiles"
    insert Palette_8bpp, "../../gen/example-backgrounds/bricks-8bpp-tiles.pal"
    insert Tiles_4bpp,   "../../gen/example-backgrounds/bricks-4bpp-tiles.tiles"
    insert Palette_4bpp, "../../gen/example-backgrounds/bricks-4bpp-tiles.pal"
    insert Tiles_2bpp,   "../../gen/example-backgrounds/bricks-2bpp-tiles.tiles"
    insert Palette_2bpp, "../../gen/example-backgrounds/bricks-2bpp-tiles.pal"

    insert Obj_Tiles,    "../../gen/example-backgrounds/obj-4bpp-tiles.tiles"
    insert Obj_Palette,  "../../gen/example-backgrounds/obj-4bpp-tiles.pal"
    insert Obj_Oam,      "../../gen/example-backgrounds/obj-oam.bin"
}

finalizeMemory()

