// Copyright (c) 2021, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


// This example uses HDMA indirect mode to repeat a 37 scanline HDMA
// effect across the entire display.
//
// HDMA indirect addressing mode allows me to write a HDMA table that
// contains multiple pointers to the same data.  This allows me to
// repeat a dynamic HDMA pattern multiple times while only calculating
// the HDMA data values once per frame.
//
// This example also employs double buffering of the HDMA pattern data
// to prevent screen tearing and/or glitches.



define ROM_NAME = "REPEATING HDMA PATTERN"
define VERSION = 0

define MEMORY_MAP = LOROM
define ROM_SIZE = 1

define ROM_SPEED = fast
define REGION = Japan


architecture wdc65816-strict

include "../common.inc"



createCodeBlock(code,       0x808000, 0x80ffaf)

createRamBlock(lowram,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)


include "../reset_handler.inc"
include "../break_handler.inc"
include "../dma_forceblank.inc"



// VRAM Map
constant VRAM_BG3_MAP_WADDR   = 0x0000
constant VRAM_BG3_TILES_WADDR = 0x1000


constant DISPLAY_HEIGHT = 224


// Using a prime number to demonstrate the code works for any size pattern
constant HDMA_PATTERN_LINES = 37


// Velocity of the cloud background
// (2x 16:16 unsigned fractional integer)
constant CLOUDS_X_VELOCITY = -0x018000;
constant CLOUDS_Y_VELOCITY =  0x00cccc;



// BG3 horizontal and vertical offset shadows (with storage for fractional-subpixels)
// (2x 16:16 unsigned fractional integer)
allocate(bg3_hofs_sx, lowram, 2)
allocate(bg3_hofs, lowram, 2)
allocate(bg3_vofs_sx, lowram, 2)
allocate(bg3_vofs, lowram, 2)


// A double-buffer to store the HDMA pattern to.
//
// The `activeHdmaPatternBuffer` flag is used to determine which buffer
// to write to.
//
// (2x uint16[HDMA_PATTERN_LINES] )
allocate(hdmaPatternBuffer_A, lowram, 2 * HDMA_PATTERN_LINES)
allocate(hdmaPatternBuffer_B, lowram, 2 * HDMA_PATTERN_LINES)


// Flag to determine which of the two HDMA Pattern buffers is active.
//
// Zero     = hdmaPatternBuffer_A
// Non-Zero = hdmaPatternBuffer_B
//
// (byte flag)
allocate(activeHdmaPatternBuffer, lowram, 1)



// NMI Handler - does nothing
au()
iu()
code()
function NmiHandler {
    rti
}



// Waits until the start of VBlank
// REQUIRES: NMI enabled
// REQUIRES: DB access registers
au()
iu()
code()
function WaitFrame {
    php
    sep     #$20
a8()

    // Wait until end of vBlank (if in vBlank)
    assert(HVBJOY.vBlank == 0x80)
    -
        lda.l   HVBJOY
        bmi     -


    // Wait until start of the next vBlank
    -
        wai
        assert(HVBJOY.vBlank == 0x80)
        lda.l   HVBJOY
        bpl     -

    plp

    rts
}



au()
iu()
code()
function Main {
    sei

    rep     #$30
    sep     #$20
a8()
i16()
    phk
    plb
// DB = 0x80


    jsr     WaveyCloudEffect__Setup


    // Enable NMI interrupts
    // (required by WaitFrame)
    lda.b   #NMITIMEN.vBlank
    sta.w   NMITIMEN


    // Wait until VBlank before enabling the screen
    jsr     WaitFrame

    lda.b   #0x0f
    sta.w   INIDISP



    Loop:
        jsr     WaveyCloudEffect__Process

        jsr     WaitFrame
            // In VBlank
            jsr     WaveyCloudEffect__VBlank

        bra     Loop
}



// Effect setup routine.
//
// Reset effect variables, initialize the PPU and upload data to the PPU.
//
// REQUIRES: 8 bit A, 16 bit Index, DB access registers
// MODIFIES: enables force-blank
a8()
i16()
code()
function WaveyCloudEffect__Setup {
    stz.w   NMITIMEN


    // Force blank

    lda.b   #INIDISP.force | 0xf
    sta.w   INIDISP



    // Reset variables

    // reset 16 bit variables
    ldx.w   #0
    stx.w   bg3_hofs_sx
    stx.w   bg3_hofs
    stx.w   bg3_vofs_sx
    stx.w   bg3_vofs

    // reset 8 bit variables
    stz.w   activeHdmaPatternBuffer



    // Set PPU registers

    lda.b   #1
    sta.w   BGMODE

    lda.b   #(VRAM_BG3_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG3SC

    lda.b   #(VRAM_BG3_TILES_WADDR / BG34NBA.walign) << BG34NBA.bg3.shift
    sta.w   BG34NBA

    lda.b   #TM.bg3
    sta.w   TM



    // Transfer tiles and map to VRAM

    ldx.w   #VRAM_BG3_MAP_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Clouds_Tilemap)


    ldx.w   #VRAM_BG3_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Clouds_Tiles)


    // Transfer palette to CGRAM
    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Clouds_Palette)


    rts
}



// Horizontal offset offsets for the HDMA effect
//
// Each byte contains the value to shift the BG3HOFS register by.
//
//
// Calculated using python:
//
//      >>> [ int((math.sin(i / 37 * math.tau) + 1) * 5.5) for i in range(37) ]
//
//
// (const uint8 array)
HOffset_Table:
    db  5, 6, 7, 8, 8, 9, 10, 10, 10, 10, 10, 10, 10, 9, 9, 8, 7, 6, 5, 5, 4, 3, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 2, 2, 3, 4
constant HOffset_Table.size = pc() - HOffset_Table

assert(HOffset_Table.size == HDMA_PATTERN_LINES)



// Effect process routine.
//
// This routine is to be called once per frame.
//
// REQUIRES: 8 bit A, 16 bit Index, DB access registers
a8()
i16()
code()
function WaveyCloudEffect__Process {


    // Get address of the next pattern buffer
    // (ie, get the non-active buffer)
    lda.w   activeHdmaPatternBuffer
    bne     +
        // A == 0
        ldy.w   #hdmaPatternBuffer_B
        bra     ++
    +
        // A != 0
        ldy.w   #hdmaPatternBuffer_A
    +
    // Y = pattern Buffer Address


    rep     #$20
a16()


    // Update BG scroll offset

    // MUST NOT MODIFY Y

    // 32 bit addition
    // bg3_hofs += CLOUDS_X_VELOCITY
    clc
    lda.w   bg3_hofs_sx
    adc.w   #CLOUDS_X_VELOCITY
    sta.w   bg3_hofs_sx

    lda.w   bg3_hofs
    adc.w   #CLOUDS_X_VELOCITY >> 16
    sta.w   bg3_hofs


    // 32 bit addition
    // bg3_vofs += CLOUDS_Y_VELOCITY
    clc
    lda.w   bg3_vofs_sx
    adc.w   #CLOUDS_Y_VELOCITY
    sta.w   bg3_vofs_sx

    lda.w   bg3_vofs
    adc.w   #CLOUDS_Y_VELOCITY >> 16
    sta.w   bg3_vofs



    // Populate HDMA pattern buffer
    //
    // Y = pattern Buffer Address

    //  for x in 0 to HOffset_Table.size:
    //      *bufferPtr++ = HOffset_Table[x] + bg3_hofs
    //

    ldx.w   #0

    Loop:
        // Y = pattern Buffer Address

        lda.l   HOffset_Table,x
        and.w   #0xff
        clc
        adc.w   bg3_hofs

        sta.w   0,y
        iny
        iny

        inx
        cpx.w   #HOffset_Table.size
        bcc     Loop



    sep     #$20
a8()


    // Swap active pattern buffer
    lda.w   activeHdmaPatternBuffer
    bne     +
        // activeHdmaPatternBuffer == 0
        lda.b   #0xff
        sta.w   activeHdmaPatternBuffer
        bra     ++
    +
        // activeHdmaPatternBuffer != 0
        stz.w   activeHdmaPatternBuffer
    +

    rts
}



// Create a repeating HDMA indirect table for the given `patternBuffer`.
macro buildHdmaTable(patternBuffer) {
    assert(HDMA_PATTERN_LINES < 127)

    evaluate n = (DISPLAY_HEIGHT + HDMA_PATTERN_LINES - 1) / HDMA_PATTERN_LINES

    while {n} > 0 {
        // HDMA_PATTERN_LINES scanlines in repeat mode
        db  0x80 | HDMA_PATTERN_LINES
            // pointer to pattern data
            dw  {patternBuffer}

        evaluate n = {n} - 1
    }

    // end of HDMA table
    db  0
}

HdmaTable_Pattern_A:
    buildHdmaTable(hdmaPatternBuffer_A)

HdmaTable_Pattern_B:
    buildHdmaTable(hdmaPatternBuffer_B)



// Effect VBlank routine.
//
//
// NOTE: Uses DMA Channel 7 for HDMA
//
// REQUIRES: In VBlank
//
// REQUIRES: 8 bit A, 16 bit Index, DB access registers
a8()
i16()
code()
function WaveyCloudEffect__VBlank {

    // Disable HDMA
    stz.w   HDMAEN



    // Update BG3VOFS
    lda.w   bg3_vofs
    sta.w   BG3VOFS
    lda.w   bg3_vofs + 1
    sta.w   BG3VOFS



    // Setup HDMA

    // Get HDMA Table address
    lda.w   activeHdmaPatternBuffer
    bne     +
        // A == 0
        ldx.w   #HdmaTable_Pattern_A
        bra     ++
    +
        // A != 0
        ldx.w   #HdmaTable_Pattern_B
    +


    lda.b   #DMAP.direction.toPpu | DMAP.addressing.indirect | DMAP.transfer.writeTwice
    sta.w   DMAP7

    lda.b   #BG3HOFS
    sta.w   BBAD7

    // X = HDMA Table address
    stx.w   A1T7

    lda.b   #HdmaTable_Pattern_A >> 16
    sta.w   A1B7


    // Indirect address bank (Pattern data in Work-RAM)
    lda.b   #0x7e
    sta.w   DASB7


    // Enable HDMA
    lda.b   #HDMAEN.dma7
    sta.w   HDMAEN


    rts
}



namespace Resources {
    insert Clouds_Tilemap,  "../../gen/example-backgrounds/clouds-tilemap.bin"

    insert Clouds_Tiles,   "../../gen/example-backgrounds/clouds-2bpp-tiles.tiles"
    insert Clouds_Palette, "../../gen/example-backgrounds/clouds-2bpp-tiles.pal"
}


finalizeMemory()

