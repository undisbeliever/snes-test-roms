// Test ROM showing how to implement a indirect double buffered HDMA effect.
//
// This test ROM was used to generate an animated image for the SNESdev wiki.
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT



define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "HDMA SHEAR ANIMATION"
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


// zero-page temporary word variables
allocate(zpTmp0, zeropage, 2)



constant VRAM_BG1_MAP_WADDR   = 0x0000
constant VRAM_BG1_TILES_WADDR = 0x1000



// Number of frames to execute before resetting the demo
// (time in frames)
constant RESET_DELAY = 60 * 8



constant HDMA_BYTES_PER_TRANSFER = 2
constant N_HDMA_SCANLINES = 224


// Flag to determine which of the two scanline arrays is used by the MainLoop.
//
// (byte flag)
allocate(activeScanlineArray, lowram, 1)


// A contiguous array of word values for each scanline.
//
// These variables can be used for any 2 byte HDMA transfer pattern.
//
// (2x u16[H_HDMA_SCANLINES] buffers)
allocate(scanlineArray_A, wram7e, HDMA_BYTES_PER_TRANSFER * N_HDMA_SCANLINES)
allocate(scanlineArray_B, wram7e, HDMA_BYTES_PER_TRANSFER * N_HDMA_SCANLINES)


// (uint16)
allocate(animationTimer, wram7e, 2)



// Setup the HDMA registers.
//
// Uses HDMA channel 7.
//
// NOTE: `ProcessShearAnimation` MUST be called before the next `WaitFrame` call.
//
// REQUIRES: 8 bit A, 16 bit Index, DB = 0x80, DP = 0
// REQUIRES: HDMA disabled
a8()
i16()
code()
// DB = REGISTERS
function SetupHdma {
    // HDMA to `BG1HOFS`
    lda.b   #DMAP.direction.toPpu | DMAP.addressing.indirect | DMAP.transfer.writeTwice
    sta.w   DMAP7

    lda.b   #BG1HOFS
    sta.w   BBAD7

    // Set HDMA table bank
    // (assumes HdmaTable_A and HdmaTable_B are in the same bank)
    lda.b   #HdmaTable_A >> 16
    sta.w   A1B7

    // HDMA indirect bank
    assert(scanlineArray_A >> 16 == scanlineArray_B >> 16)
    lda.b   #scanlineArray_A >> 16
    sta.w   DASB7

    rts
}



// VBlank routine.
//
// Uses HDMA channel 7.
//
// MUST NOT be executed in a lag-frame
//
// REQUIRES: 8 bit A, 16 bit Index, DB = 0x80, DP = 0
macro VBlank() {
    assert8a()
    assert16i()

    // Set HDMA table address (depending on which scanline-array was last used by the MainLoop)
    lda.w   activeScanlineArray
    beq     +
        ldx.w   #HdmaTable_A
        bra     ++
    +
        ldx.w   #HdmaTable_B
    +
    stx.w   A1T7


    // Enable HDMA.
    // HDMA should be enabled during VBlank.
    // There is no need to write to `HDMAEN` on every VBlank, it can be written to on a single VBlank.
    lda.b   #HDMAEN.dma7
    sta.w   HDMAEN
}

include "../vblank_interrupts.inc"



// Retrieve the next scanline array.
//
// MUST ONLY be called 0 or 1 times between `WaitFrame` calls.
//
// RETURN: X = Scanline Array address
//
// REQUIRES: 8 bit A, 16 bit Index, DB = 0x7e, DP = 0
a8()
i16()
code()
// DB = 0x7e
function GetNextScanlineArray {
    lda.w   activeScanlineArray
    beq     +
        ldx.w   #scanlineArray_B
        lda.b   #0
        bra     ++
    +
        ldx.w   #scanlineArray_A
        lda.b   #1
    +
    sta.w   activeScanlineArray

    rts
}



// Setup the shear animation.
//
// NOTE: This function does setup the PPU or HDMA.
//
// REQUIRES: 8 bit A, 16 bit Index, DB = 0x7e, DP = 0
a8()
i16()
code()
// DB = 0x7e
function SetupShearAnimation {
    ldx.w   #0
    stx.w   animationTimer

    bra     ProcessShearAnimation
}



// Process a single frame of the shear animation
//
// REQUIRES: 8 bit A, 16 bit Index, DB = 0x7e, DP = 0
a8()
i16()
code()
// DB = 0x7e
function ProcessShearAnimation {
// sint16
constant _tmp   = zpTmp0

    // NOTE: tmp is signed

    //  scanlineArray = GetNextScanlineArray()
    //
    //  animationTimer = animationTimer + 2
    //  if animationTimer > 512 + N_HDMA_SCANLINES:
    //      animationTimer = 512 + N_HDMA_SCANLINES
    //
    //  tmp = animationTimer
    //
    //  for i = 0 to N_HDMA_SCANLINES-1:
    //      tmp = tmp - 2
    //      scanlineArray[i] = clamp(tmp, 0, 256)
    //


    jsr     GetNextScanlineArray
    // X = address of scanline array

    rep     #$30
a16()
i16()

    lda.w   animationTimer
    inc
    inc
    cmp.w   #512 + N_HDMA_SCANLINES
    bcc     +
        lda.w   #512 + N_HDMA_SCANLINES
    +
    sta.w   animationTimer

    sta.b   _tmp


    ldy.w   #N_HDMA_SCANLINES
    Loop:
        // X = scanline array pointer
        // Y = number of scanlines left

        lda.b   _tmp
        dec
        dec
        sta.b   _tmp

        bpl     +
            lda.w   #0
            bra     ++
        +
            cmp.w   #256
            bcc     +
                lda.w   #256
        +

        sta.w   0,x
        inx
        inx

        dey
        bne     Loop


    sep     #$20
a8()
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
    lda.b   #BGMODE.mode0
    sta.w   BGMODE

    lda.b   #(VRAM_BG1_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s64x32
    sta.w   BG1SC

    lda.b   #(VRAM_BG1_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg1.shift
    sta.w   BG12NBA


    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Bg1_Palette)


    ldx.w   #VRAM_BG1_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg1_Tiles)

    ldx.w   #VRAM_BG1_MAP_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg1_Tilemap)


    lda.b   #TM.bg1
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


    lda.b   #0x7e
    pha
    plb
// DB = 0x7e


    jsr     SetupShearAnimation


    // Enable screen (on the next VBlank)
    // Long addressing is required, DB cannot access INIDISP register
    jsr     WaitFrame
    lda.b   #0x0f
    sta.l   INIDISP


    MainLoop:
        jsr     WaitFrame

        // Reset the demo after RESET_DELAY frames
        // Must be done immediately after WaitFrame to prevent screen tearing.
        ldx.w   frameCounter
        cpx.w   #RESET_DELAY
        bcc     +
            jmp     ResetHandler
        +

        jsr     ProcessShearAnimation

        jmp     MainLoop
}



// Indirect HDMA table to the data in `scanlineArray_A`
// NOTE: This table can only be used on 2-byte HDMA transfer patterns
HdmaTable_A:
    db  0x80 | 112      // 112 scanlines, repeat entry
        // Word address pointing to the first half of `scanlineArray_A`
        dw  scanlineArray_A

    db  0x80 | 112      // 112 scanlines, repeat entry
        // Word address pointing to the second half of `scanlineArray_A`
        dw  scanlineArray_A + 112 * 2

    db  0               // End HDMA table



// Indirect HDMA table to the data in `scanlineArray_B`
// NOTE: This table can only be used on 2-byte HDMA transfer patterns
HdmaTable_B:
    db  0x80 | 112      // 112 scanlines, repeat entry
        // Word address pointing to the first half of `scanlineArray_B`
        dw  scanlineArray_B

    db  0x80 | 112      // 112 scanlines, repeat entry
        // Word address pointing to the second half of `scanlineArray_B`
        dw  scanlineArray_B + 112 * 2

    db  0               // End HDMA table



// Resources
// =========

namespace Resources {
    insert Bg1_Palette,  "../../gen/hdma-hoffset-examples/shear-titlescreen-2bpp.palette"
    insert Bg1_Tiles,   "../../gen/hdma-hoffset-examples/shear-titlescreen-2bpp.2bpp"
    insert Bg1_Tilemap, "../../gen/hdma-hoffset-examples/shear-titlescreen-2bpp.tilemap"
}


