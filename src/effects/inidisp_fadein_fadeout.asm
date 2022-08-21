// An INIDISP fade-in, fade-to-force-blank screen transition demo.
//
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "FADEIN FADEOUT DEMO"
define VERSION = 1


architecture wdc65816-strict


include "../common.inc"


createCodeBlock(code,       0x808000, 0x80ffaf)

createRamBlock(lowram,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)


include "../reset_handler.inc"
include "../break_handler.inc"
include "../dma_forceblank.inc"


// VRAM Map
constant VRAM_BG1_MAP_WADDR   = 0x0000
constant VRAM_BG1_TILES_WADDR = 0x1000



// Frame counter.  Incremented every NMI interrupt
// (uint32)
allocate(frameCounter, lowram, 4)


// INIDISP shadow variable
allocate(inidisp_shadow, lowram, 1)


// Execute V-Blank Routine flag
//
// The VBlank routine will be executed if this value is non-zero.
//
// (byte flag)
allocate(vBlankFlag, lowram, 1)



// NMI ISR
au()
iu()
code()
function NmiHandler {
    // Jump to FastROM bank
    jml     FastRomNmiHandler
FastRomNmiHandler:

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
// DB = 0x80

    lda.w   #0
    tcd
// DP = 0


    sep     #$20
a8()

    // Only execute the VBlank routine if `vBlankFlag` is non-zero.
    // (prevents corruption during force-blank setup or a lag frame)
    lda.w   vBlankFlag
    bne     +
        jmp     EndVBlankRoutine
    +

        // Enable force-blank (and set brightness bits)
        lda.w   inidisp_shadow
        ora.b   #INIDISP.force
        sta.w   INIDISP


        // VBlank routine goes here


        // Only write to `INIDISP` when `vBlankFlag` is set.
        //
        // We do not want to accidentally enable/disable the screen (or change the brightness)
        // in the middle of a setup routine or a lag-frame.
        assert8a()
        lda.w   inidisp_shadow
        sta.w   INIDISP


        stz.w   vBlankFlag


EndVBlankRoutine:


    rep     #$30
a16()
i16()

    // Increment 32 bit frameCounter
    inc.w   frameCounter
    bne     +
        inc.w   frameCounter + 2
    +


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



// Wait until the start of a new display frame
// (or the end of the VBlank routine (NmiHandler)).
//
// REQUIRES: NMI enabled, DB access low-RAM
au()
iu()
code()
function WaitFrame {
    php
    sep     #$20
a8()

    lda.b   #1
    sta.w   vBlankFlag


    // Loop until frameCounter has changed
    lda.w   frameCounter
    -
        wai

        cmp.w   frameCounter
        beq     -

    plp

    rts
}



// Fade-in screen transition.
//
// ASSUMES: In force-blank or screen brightness is 0.
//
// REQUIRES: 8 bit A, 16 bit Index, DB access registers
a8()
i16()
code()
function FadeInTransition {

    lda.b   #0

    Loop:
        sta.w   inidisp_shadow

        jsr     WaitFrame
        jsr     WaitFrame
        jsr     WaitFrame
        jsr     WaitFrame

        lda.w   inidisp_shadow
        inc
        cmp.b   #INIDISP.brightness.mask + 1
        bne     Loop

    rts
}



// Fade-to-black screen transition.
//
// Returns with force-blank enabled.
//
// ASSUMES: Screen active and at full brightness
//
// REQUIRES: 8 bit A, 16 bit Index, DB access registers
a8()
i16()
code()
function FadeToForceBlank {

    lda.b   #INIDISP.brightness.mask

    Loop:
        sta.w   inidisp_shadow

        jsr     WaitFrame
        jsr     WaitFrame
        jsr     WaitFrame
        jsr     WaitFrame

        lda.w   inidisp_shadow
        dec
        bpl     Loop


    lda.b   #INIDISP.force
    sta.w   inidisp_shadow

    // Must wait until the end of the VBlank routine before Force-Blank is enabled
    jsr     WaitFrame

    rts
}



// Pause execution for 60 frames.
//
// REQUIRES: 8 bit A, 16 bit Index, DB access registers
a8()
i16()
code()
function WaitOneSecond {

    lda.b   #60

    Loop:
        pha

        jsr     WaitFrame

        pla
        dec
        bne     Loop

    rts
}



// Transfer MapImage to VRAM and CGRAM
//
// REQUIRES: Force-Blank
//
// REQUIRES: 8 bit A, 16 bit Index, DB access registers
a8()
i16()
code()
function LoadImage_Map {

    ldx.w   #VRAM_BG1_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.MapImage_Tiles)


    ldx.w   #VRAM_BG1_MAP_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.MapImage_Tilemap)

    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.MapImage_Palette)

    rts
}



// Transfer GameImage to VRAM and CGRAM
//
// REQUIRES: Force-Blank
//
// REQUIRES: 8 bit A, 16 bit Index, DB access registers
a8()
i16()
code()
function LoadImage_Game {
    ldx.w   #VRAM_BG1_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.GameImage_Tiles)


    ldx.w   #VRAM_BG1_MAP_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.GameImage_Tilemap)

    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.GameImage_Palette)

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

    // Enable NMI interrupt
    lda.b   #NMITIMEN.vBlank
    sta.w   NMITIMEN


    // Setup PPU registers
    lda.b   #INIDISP.force | 0xf
    sta.w   inidisp_shadow
    sta.w   INIDISP

    lda.b   #1
    sta.w   BGMODE

    lda.b   #(VRAM_BG1_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG1SC

    lda.b   #(VRAM_BG1_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg1.shift
    sta.w   BG12NBA

    lda.b   #TM.bg1
    sta.w   TM


    MainLoop:
        jsr     LoadImage_Map

        jsr     FadeInTransition
        jsr     WaitOneSecond
        jsr     FadeToForceBlank

        jsr     LoadImage_Game

        jsr     FadeInTransition
        jsr     WaitOneSecond
        jsr     FadeToForceBlank

        bra     MainLoop
}



namespace Resources {
    insert MapImage_Tiles,   "../../gen/inidisp-fadein-fadeout/map.4bpp"
    insert MapImage_Tilemap, "../../gen/inidisp-fadein-fadeout/map.tilemap"
    insert MapImage_Palette, "../../gen/inidisp-fadein-fadeout/map.palette"

    insert GameImage_Tiles,   "../../gen/inidisp-fadein-fadeout/game.4bpp"
    insert GameImage_Tilemap, "../../gen/inidisp-fadein-fadeout/game.tilemap"
    insert GameImage_Palette, "../../gen/inidisp-fadein-fadeout/game.palette"
}


finalizeMemory()

