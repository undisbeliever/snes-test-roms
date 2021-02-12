// Tests if writing to INIDISP when the previous value on the data bus
// has bit 7 set would cause a sprite glitch.
//
// This is an interactive test:
//      * if A/B/X/Y button is not pressed then the test will write
//        0x80 to $20ff and `0x0f` to INIDISP.
//
//      * if A/B/X/Y button is pressed then the test will write
//        0x00 to $20ff and `0x0f` to INIDISP.
//
// Copyright (c) 2021, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "INIDISP D7 GLITCH TEST"
define VERSION = 1


architecture wdc65816-strict

include "../common.inc"

createCodeBlock(code,       0x808000, 0x80ffaf)

createRamBlock(stack,       0x7e1f80, 0x7e1fff)


include "../reset_handler.inc"
include "../dma_forceblank.inc"


// BG2-4 uses WADDR 0
constant VRAM_OBJ_TILES_WADDR = 0x6000
constant VRAM_BG1_TILES_WADDR = 0x1000
constant VRAM_BG1_MAP_WADDR   = 0x1400



// Break ISR
// Red screen of death on error
au()
iu()
code()
CopHandler:
IrqHandler:
NmiHandler:
EmptyHandler:
BreakHandler:
function RSOD {
    rep     #$30
    sep     #$20
i16()
a8()
    assert(pc() >> 16 == 0x80)
    phk
    plb

    jsr     ResetRegisters

    stz.w   CGADD
    lda.b   #0x1f
    sta.w   CGDATA
    stz.w   CGDATA

    lda.b   #0x0f
    sta.w   INIDISP

-
    bra     -
}



// Setup and initialize the PPU
// REQUIRES: 8 bit A, 16 bit Index, DB access registers
// MODIFIES: enables force-blank
macro SetupPpu() {
    assert8a()
    assert16i()

    stz.w   NMITIMEN


    // Set PPU registers

    lda.b   #INIDISP.force | 0xf
    sta.w   INIDISP

    lda.b   #1
    sta.w   BGMODE

    lda.b   #(VRAM_BG1_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG1SC

    lda.b   #(VRAM_BG1_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg1.shift
    sta.w   BG12NBA

    // BG2-BG4 have a TILE & MAP WADDR of 0 (as set by ResetRegisters)

    lda.b   #OBSEL.size.s8_32 | (VRAM_OBJ_TILES_WADDR / OBSEL.base.walign) << OBSEL.base.shift
    sta.w   OBSEL

    lda.b   #TM.bg1 | TM.obj
    sta.w   TM


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


    // Transfer tiles and map to VRAM

    ldx.w   #VRAM_BG1_MAP_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg1_Tilemap)


    ldx.w   #VRAM_OBJ_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Obj_Tiles)


    ldx.w   #VRAM_BG1_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Tiles_4bpp)


    // Transfer palette to CGRAM
    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Palette_4bpp)
}



au()
iu()
code()
function Main {
    rep     #$30
    sep     #$20
a8()
i16()
    sei

    SetupPpu()

    lda.b   #0x0f
    sta.w   INIDISP

    lda.b   #NMITIMEN.autoJoy
    sta.w   NMITIMEN


    MainLoop:
        // Check if a button is pressed
        // There is not need to check `HVBJOY`, bad `JOY1` reads affect non-visible scanlines.
        lda.b   #JOYH.b | JOYH.y
        bit.w   JOY1H
        bne     ButtonPressed

        lda.b   #JOYL.a | JOYL.x
        bit.w   JOY1L
        bne     ButtonPressed
            // No button pressed, write to 2100 with data bus b7 set
            ldx.w   #0x0f80

            bra     EndIf

        ButtonPressed:
            // No button pressed, write to 2100 with data bus b7 clear
            ldx.w   #0x0f00

        EndIf:


        // Wait until hBlank
        -
            assert(HVBJOY.hBlank == 0x40)
            bit.w   HVBJOY
            bvc     -


        stx.w   INIDISP - 1


        // Wait until the end of hBlank
        -
            assert(HVBJOY.hBlank == 0x40)
            bit.w   HVBJOY
            bvs     -


        bra     MainLoop
}



namespace Resources {
    insert Bg1_Tilemap,  "../../gen/example-backgrounds/bricks-tilemap.bin"

    insert Tiles_4bpp,   "../../gen/example-backgrounds/bricks-4bpp-tiles.tiles"
    insert Palette_4bpp, "../../gen/example-backgrounds/bricks-4bpp-tiles.pal"

    insert Obj_Tiles,    "../../gen/example-backgrounds/obj-4bpp-tiles.tiles"
    insert Obj_Palette,  "../../gen/example-backgrounds/obj-4bpp-tiles.pal"
    insert Obj_Oam,      "../../gen/example-backgrounds/obj-oam.bin"
}


