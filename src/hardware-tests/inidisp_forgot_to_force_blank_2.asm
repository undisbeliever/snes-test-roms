// A simple test to show what happens when you forget to force-blank
// before uploading data to the PPU.
//
// Copyright (c) 2020, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "FORGOT FORCE BLANK 2"
define VERSION = 0

define USES_IRQ_INTERRUPTS


architecture wdc65816-strict

include "../common.inc"

createCodeBlock(code,       0x808000, 0x80ffaf)

createRamBlock(lowram,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)


include "../reset_handler.inc"
include "../break_handler.inc"
include "../dma_forceblank.inc"


constant VRAM_OBJ_TILES_WADDR = 0x6000
constant VRAM_BG1_TILES_WADDR = 0x1000
constant VRAM_BG1_MAP_WADDR   = 0x1400


// This demo does not use VBlank Interrupts.
constant NmiHandler = BreakHandler



// IRQ ISR
//
// Does not do anything.
function IrqHandler {
    sep     #$20
a8()
    pha

    lda.l   TIMEUP

    pla
    rti
}



// Sets PPU registers and load data into VRAM/CGRAM/OAM
//
// REQUIRES: 8 bit A, 16 bit Index, DB access registers
a8()
i16()
code()
function SetupPpu {

    lda.b   #BGMODE.mode1
    sta.w   BGMODE

    lda.b   #TM.bg1 | TM.obj
    sta.w   TM

    lda.b   #(VRAM_BG1_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG1SC

    lda.b   #(VRAM_BG1_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg1.shift
    sta.w   BG12NBA

    lda.b   #OBSEL.size.s8_32 | (VRAM_OBJ_TILES_WADDR / OBSEL.base.walign) << OBSEL.base.shift
    sta.w   OBSEL


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


    // Transfer tilemap to VRAM
    ldx.w   #VRAM_BG1_MAP_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg1_Tilemap)


    // Transfer tiles to VRAM
    ldx.w   #VRAM_BG1_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Tiles_4bpp)

    ldx.w   #VRAM_OBJ_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Obj_Tiles)


    // Transfer palettes to CGRAM
    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Palette_4bpp)

    lda.b   #128
    sta.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Obj_Palette)


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

    // Fill the VRAM with data
    // (If the VRAM is empty then the there is little to no corruption)
    lda.b   #INIDISP.force | 0x0f
    sta.w   INIDISP

    jsr     Dma.ForceBlank.ClearVram
    jsr     Dma.ForceBlank.ClearCgram

    jsr     SetupPpu


    // Enable display, full brightness.
    // Forget to force blank
    lda.b   #0x0f
    sta.w   INIDISP


    // Wait until the screen is active
    // (This position produces a nice looking glitch)
    ldy.w   #103
    sty.w   VTIME

    ldy.w   #137
    sty.w   HTIME

    lda.b   #NMITIMEN.vCounter | NMITIMEN.hCounter
    sta.w   NMITIMEN

    wai


    // Transfer data to PPU during active display period
    jsr     SetupPpu


    // Loop forever
    Loop:
        wai
        jmp     Loop
}


namespace Resources {
    insert Bg1_Tilemap,  "../../gen/example-backgrounds/bricks-tilemap.bin"

    insert Tiles_4bpp,   "../../gen/example-backgrounds/bricks-4bpp-tiles.tiles"
    insert Palette_4bpp, "../../gen/example-backgrounds/bricks-4bpp-tiles.pal"

    insert Obj_Tiles,    "../../gen/example-backgrounds/obj-4bpp-tiles.tiles"
    insert Obj_Palette,  "../../gen/example-backgrounds/obj-4bpp-tiles.pal"
    insert Obj_Oam,      "../../gen/example-backgrounds/obj-oam.bin"
}

finalizeMemory()


