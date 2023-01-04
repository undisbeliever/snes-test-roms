// HDMA to CGRAM example.
//
// This example shows two different techniques for creating a single colour gradient using HDMA.
//
// This example will alternate between the two HDMA techniques to prove they both output the exact
// same gradient.
//
//
// Copyright (c) 2023, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "HDMA TO CGRAM"
define VERSION = 0


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


constant VRAM_BG3_MAP_WADDR   = 0x0000
constant VRAM_BG3_TILES_WADDR = 0x1000


rodata(code)


// A HDMA gradient for a single colour that uses two HDMA channels.
//
// The first HDMA channel will set the CGADD colour index.
// The second HDMA channel will write the CGDATA colour data.
//
// Both HDMA tables MUST have the same line-count bytes for all HDMA entries.
//
// (See `VBlank.TwoHdmaChannels` for HDMA register settings)
namespace Gradient_TwoHdmaChannels {
    constant COLOR_TO_CHANGE = 1


    // HDMA Table to CGDATA (byte register pattern)
    CGADD_HdmaTable:
        db  32                          // 32 scanlines, non-repeat entry
            db  COLOR_TO_CHANGE

        variable i = 0
        while i < 28 {
            db  2                       // 6 scanlines, non-repeat entry
                db  COLOR_TO_CHANGE
            i = i + 1
        }

        db  0                           // end of HDMA table


    // HDMA Table to CGDATA (write twice pattern)
    //
    // This HDMA table MUST be processed after `CGADD_HdmaTable`.
    //
    // The HDMA entries MUST have the same line-count as `CGADD_HdmaTable`.
    //
    CGDATA_HdmaTable:
        db  32                          // 32 scanlines, non-repeat entry
            dw  0

        variable i = 0
        while i < 28 {
            db  2                       // 2 scanlines, non-repeat entry
                dw  (28 - i) << 10
            i = i + 1
        }

        db  0                           // end of HDMA table
}



// A HDMA gradient using a single HDMA channel to CGADD & CGDATA using a two-registers write-twice HDMA pattern.
//
// This HDMA will write to CGADD twice.
// The CGADD first write is ignored and the second CGADD write contains the colour index to change.
//
// (See `VBlank.OneHdmaChannel` for HDMA register settings)
namespace Gradient_OneHdmaChannel {
    constant COLOR_TO_CHANGE = 1


    // HDMA Table to CGADD & CGDATA (two registers, write twice pattern)
    HdmaTable:
        db  32                      // 32 scanlines, non-repeat entry
            db  0, COLOR_TO_CHANGE      // two writes to CGADD
            dw  0                       // CGDATA data (color value)

        variable i = 0
        while i < 28 {
            db  2                       // 2 scanlines, non-repeat entry
                db  0, COLOR_TO_CHANGE      // two writes to CGADD
                dw  (28 - i) << 10         // CGDATA data (color value)
            i = i + 1
        }

        db  0                       // end of HDMA table
}



// VBlank routine.
//
// DMA: Uses HDMA channels 6 & 7
//
// REQUIRES: 8 bit A, 16 bit Index, DB = 0x80, DP = 0
macro VBlank() {
    assert8a()
    assert16i()

    // Alternate between `Gradient_TwoHdmaChannels` and `Gradient_OneHdmaChannel` every frame.
    lda.w   frameCounter
    and.b   #1
    beq     OneHdmaChannel

    TwoHdmaChannels:
        // Setup HDMA for Gradient_TwoHdmaChannels

        // Setup HDMA Channel 6
        // HDMA to `CGADD` (byte register pattern)
        lda.b   #DMAP.direction.toPpu | DMAP.transfer.one
        sta.w   DMAP6

        // HDMA target
        lda.b   #CGADD
        sta.w   BBAD6

        // HDMA table address
        ldx.w   #Gradient_TwoHdmaChannels.CGADD_HdmaTable
        lda.b   #Gradient_TwoHdmaChannels.CGADD_HdmaTable >> 16
        stx.w   A1T6
        sta.w   A1B6


        // Setup HDMA Channel 7
        // HDMA to `CGDATA` (write twice pattern)
        lda.b   #DMAP.direction.toPpu | DMAP.transfer.writeTwice
        sta.w   DMAP7

        // HDMA target
        lda.b   #CGDATA
        sta.w   BBAD7

        // HDMA table address
        ldx.w   #Gradient_TwoHdmaChannels.CGDATA_HdmaTable
        lda.b   #Gradient_TwoHdmaChannels.CGDATA_HdmaTable >> 16
        stx.w   A1T7
        sta.w   A1B7

        // Enable HDMA
        lda.b   #HDMAEN.dma6 | HDMAEN.dma7
        sta.w   HDMAEN

        bra     EndIf


    OneHdmaChannel:
        // Setup HDMA for Gradient_OneHdmaChannel

        // HDMA to `CGADD` & `CGDATA` (two registers, write twice pattern)
        lda.b   #DMAP.direction.toPpu | DMAP.transfer.twoWriteTwice
        sta.w   DMAP7

        // HDMA target
        lda.b   #CGADD
        sta.w   BBAD7

        // HDMA table address
        ldx.w   #Gradient_OneHdmaChannel.HdmaTable
        lda.b   #Gradient_OneHdmaChannel.HdmaTable >> 16
        stx.w   A1T7
        sta.w   A1B7

        // Enable HDMA
        lda.b   #HDMAEN.dma7
        sta.w   HDMAEN

    EndIf:
}

include "../vblank_interrupts.inc"



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

    lda.b   #(VRAM_BG3_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG3SC

    lda.b   #(VRAM_BG3_TILES_WADDR / BG34NBA.walign) << BG34NBA.bg3.shift
    sta.w   BG34NBA


    ldx.w   #VRAM_BG3_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg3_Tiles)

    ldx.w   #VRAM_BG3_MAP_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg3_Tilemap)

    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Bg3_Palette)



    lda.b   #TM.bg3
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

    EnableVblankInterrupts()

    jsr     WaitFrame

    lda.b   #0x0f
    sta.w   INIDISP


    MainLoop:
        jsr     WaitFrame

        jmp     MainLoop
}



// Resources
// =========

namespace Resources {
    insert Bg3_Tiles,   "../../gen/hdma-textbox-wipe/bg3.2bpp"
    insert Bg3_Tilemap, "../../gen/hdma-textbox-wipe/bg3.tilemap"

    // Only write 3 colours to the ROM
    // The 4th colour is red and is used for invalid tiles that
    // would be hidden in the textbox-wipe-animation demo.
    insert Bg3_Palette,  "../../gen/hdma-textbox-wipe/bg3.palette", 0, 6
}


