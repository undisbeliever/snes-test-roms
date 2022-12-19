// Test ROM showing how to implement a double buffered parallax HDMA effect.
//
// This test ROM was used to generate a GIF for the SNESdev wiki.
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT



define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "HDMA PARALLAX EXAMPLE"
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
constant VRAM_BG1_TILES_WADDR = 0x1000



constant HDMA_BUFFER_SIZE = 512

// Flag to determine which of the two HDMA buffers is active.
//
//            Used by MainLoop      Used by the HDMA controller
// Zero     = hdmaBuffer_A          hdmaBuffer_B
// Non-Zero = hdmaBuffer_B          hdmaBuffer_A
//
// (byte flag)
allocate(activeHdmaBuffer, lowram, 1)

// 2 HDMA buffers
// (2x u8[HDMA_BUFFER_SIZE] buffers)
allocate(hdmaBuffer_A, wram7e, HDMA_BUFFER_SIZE)
allocate(hdmaBuffer_B, wram7e, HDMA_BUFFER_SIZE)


// Camera x position
// (16.16 fixed point)
allocate(camera_xpos, wram7e, 4)

// Camera subpixel x position
constant camera_xpos.sx = camera_xpos

// Camera pixel x position
constant camera_xpos.px = camera_xpos + 2


// Camera's x-axis speed (in subpixels/frame).
//
// This specific speed was chosen so the effect repeats every 10 seconds.
//
// (16.16 fixed point)
constant CAMERA_XPOS_SPEED = 0x000369d0



// Setup the HDMA registers.
//
// Uses HDMA channel 7.
//
// NOTE: `BuildHdmaTable` MUST be called before the next `WaitFrame` call.
//
// REQUIRES: 8 bit A, 16 bit Index, DB = 0x80, DP = 0
// REQUIRES: HDMA disabled
a8()
i16()
code()
// DB = REGISTERS
function SetupHdma {
    // HDMA to `BG1HOFS`
    lda.b   #DMAP.direction.toPpu | DMAP.transfer.writeTwice
    sta.w   DMAP7

    lda.b   #BG1HOFS
    sta.w   BBAD7

    // Set HDMA table bank
    assert(hdmaBuffer_A >> 16 == hdmaBuffer_B >> 16)
    lda.b   #hdmaBuffer_A >> 16
    sta.w   A1B7

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

    // Set HDMA table address (depending on which buffer was last used by the MainLoop)
    lda.w   activeHdmaBuffer
    beq     +
        ldx.w   #hdmaBuffer_A
        bra     ++
    +
        ldx.w   #hdmaBuffer_B
    +
    stx.w   A1T7


    // Enable HDMA.
    // HDMA should be enabled during VBlank.
    // There is no need to write to `HDMAEN` on every VBlank, it can be written to on a single VBlank.
    lda.b   #HDMAEN.dma7
    sta.w   HDMAEN
}

include "../vblank_interrupts.inc"



// Retrieve the next HDMA buffer.
//
// MUST ONLY be called 0 or 1 times between `WaitFrame` calls.
//
// RETURN: X = HDMA buffer address
//
// REQUIRES: 8 bit A, 16 bit Index, DB = 0x7e, DP = 0
a8()
i16()
code()
// DB = 0x7e
function GetNextHdmaBuffer {
    lda.w   activeHdmaBuffer
    beq     +
        ldx.w   #hdmaBuffer_B
        lda.b   #0
        bra     ++
    +
        ldx.w   #hdmaBuffer_A
        lda.b   #1
    +
    sta.w   activeHdmaBuffer

    rts
}



// Build the HDMA table
//
// REQUIRES: 8 bit A, 16 bit Index, DB = 0x7e, DP = 0
a8()
i16()
code()
// DB = 0x7e
function BuildHdmaTable {

    // Confirm the HDMA table can fit inside a HDMA buffer
    assert(HDMA_BUFFER_SIZE >= 12 + 1)


    // hdmaTable = GetNextHdmaBuffer()
    // hdmaTable[ 0] as u8  = 45
    // hdmaTable[ 1] as u16 = camera_xpos_px >> 3
    // hdmaTable[ 3] as u8  = 22
    // hdmaTable[ 4] as u16 = camera_xpos_px >> 2
    // hdmaTable[ 6] as u8  = 128
    // hdmaTable[ 7] as u16 = camera_xpos_px
    // hdmaTable[ 9] as u8  = 128
    // hdmaTable[10] as u16 = int(camera_xpos << 1)
    // hdmaTable[12] as u8  = 0


    jsr     GetNextHdmaBuffer
    // X = address of HDMA buffer


    // Set line counters
    // NOTE: All values MUST BE <= 128
    lda.b   #45
    sta.w   0,x

    lda.b   #22
    sta.w   3,x

    lda.b   #128
    sta.w   6,x

    lda.b   #1
    sta.w   9,x

    stz.w   12,x


    // Calculate BG1HOFS values
    rep     #$30
a16()
    lda.w   camera_xpos.px
    sta.w   7,x
    lsr
    lsr
    sta.w   4,x
    lsr
    sta.w   1,x


    // Read the MSB of camera subpixel word
    lda.w   camera_xpos.sx
    asl
    lda.w   camera_xpos.px
    rol
    sta.w   10,x


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

    lda.b   #(VRAM_BG1_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
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


    // Build the HDMA table before the first VBlank call
    jsr     BuildHdmaTable


    // Enable screen (on the next VBlank)
    // Long addressing is required, DB cannot access INIDISP register
    jsr     WaitFrame
    lda.b   #0x0f
    sta.l   INIDISP


    MainLoop:
        jsr     WaitFrame

        // Increment the camera's x position
        rep     #$31
    a16()
        // carry clear
        lda.w   camera_xpos
        adc.w   #CAMERA_XPOS_SPEED
        sta.w   camera_xpos

        lda.w   camera_xpos + 2
        adc.w   #CAMERA_XPOS_SPEED >> 16
        sta.w   camera_xpos + 2

        sep     #$20
    a8()

        jsr     BuildHdmaTable

        jmp     MainLoop
}



// Resources
// =========

namespace Resources {
    insert Bg1_Palette,  "../../gen/hdma-hoffset-examples/two-vertical-bars-2bpp.palette"
    insert Bg1_Tiles,   "../../gen/hdma-hoffset-examples/two-vertical-bars-2bpp.2bpp"
    insert Bg1_Tilemap, "../../gen/hdma-hoffset-examples/two-vertical-bars-2bpp.tilemap"
}


