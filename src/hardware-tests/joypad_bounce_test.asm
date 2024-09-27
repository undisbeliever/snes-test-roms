// A test ROM design to display the contact bound on key-press and key-release.
//
// It reads 12 bits of controller port 1 every scanline, writes the data to a buffer and waits for
// no button presses for 262 scanlines (1 frame).  Then it builds four HDMA tables to display ~200
// scanlines after button-press and ~200 scanlines before button-release.
//
// For each pair of vertical lines represents one button.
// The left line is scanlines after button press and the right line is scanlines before release.
//
// CAUTION: This test is designed for one button at a time.
// CAUTION: This test cannot read controller data and build the HDMA tables at the same time.
//
// SPDX-FileCopyrightText: © 2024 Marcus Rowe <undisbeliever@gmail.com>
// SPDX-License-Identifier: Zlib
//
// Copyright © 2024 Marcus Rowe <undisbeliever@gmail.com>
//
// This software is provided 'as-is', without any express or implied warranty.
// In no event will the authors be held liable for any damages arising from the
// use of this software.
//
// Permission is granted to anyone to use this software for any purpose, including
// commercial applications, and to alter it and redistribute it freely, subject to
// the following restrictions:
//
//    1. The origin of this software must not be misrepresented; you must not
//       claim that you wrote the original software. If you use this software in
//       a product, an acknowledgment in the product documentation would be
//       appreciated but is not required.
//
//    2. Altered source versions must be plainly marked as such, and must not be
//       misrepresented as being the original software.
//
//    3. This notice may not be removed or altered from any source distribution.


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "JOYPAD BOUNCE TEST"
define VERSION = 0


architecture wdc65816-strict

include "../common.inc"

createCodeBlock(code,       0x808000, 0x80ffaf)

createRamBlock(zeropage,        0x00,     0xff)
createRamBlock(lowram,      0x7e0100, 0x7e1eff)
createRamBlock(stack,       0x7e1f00, 0x7e1fff)


include "../reset_handler.inc"
include "../break_handler.inc"
include "../dma_forceblank.inc"

// This test does not use interrupts
constant NmiHandler = BreakHandler.ISR


// All four backgrounds use the same tilemap and tiles
constant VRAM_BG_TILES_WADDR = 0x1000
constant VRAM_BG_MAP_WADDR   = 0x0000


constant N_BITS = 12;
constant SPACING_BETWEEN_BITS = 12
constant SPACING_BETWEEN_LINES = 4
constant TOTAL_WIDTH = (N_BITS - 1) * SPACING_BETWEEN_BITS + SPACING_BETWEEN_LINES + 2

constant BG1_X_OFFSET = -(256 - TOTAL_WIDTH) / 2
constant BG2_X_OFFSET = BG1_X_OFFSET - 4 * SPACING_BETWEEN_BITS
constant BG3_X_OFFSET = BG1_X_OFFSET - SPACING_BETWEEN_LINES
constant BG4_X_OFFSET = BG2_X_OFFSET - SPACING_BETWEEN_LINES

constant DISPLAY_HEIGHT = 224
constant Y_OFFSET = 10
constant N_SCANLINES_TO_DISPLAY = DISPLAY_HEIGHT - Y_OFFSET


// Number of scanlines of no-button presses to wait if the MainLoop starts with a button pressed
constant WAIT_FOR_RELEASE_THREASHOLD = 262

// Number of scanlines with 0 depressed buttons before displaying data.
constant RELEASE_THREASHOLD = 262  // 1 frame

constant PRESS_BUFFER_SIZE = N_SCANLINES_TO_DISPLAY
constant RELEASE_BUFFER_SIZE = 0x600

assert(RELEASE_BUFFER_SIZE > DISPLAY_HEIGHT + RELEASE_THREASHOLD + 32)


allocate(zpTmpByte, zeropage, 1)

// Used to determine if the release buffer is empty

// HDMA double buffer control variable
// (word index into `HdmaTable*_TableAddr`)
allocate(currentHdmaTable, zeropage, 2)


// Determines if the `buttonReleaseBuffer` is full or not.
// (byte flag)
allocate(releaseBufferNotFull, zeropage, 1)

// Index of the first line to of the release buffer to draw.
// (word index into `buttonReleaseBuffer_*`).
allocate(releaseBufferIndex, zeropage, 2)


// Button press buffer
allocate(buttonPressBuffer_l, lowram, PRESS_BUFFER_SIZE)
allocate(buttonPressBuffer_h, lowram, PRESS_BUFFER_SIZE)

// Button release circular buffer
allocate(buttonReleaseBuffer_l, lowram, RELEASE_BUFFER_SIZE)
allocate(buttonReleaseBuffer_h, lowram, RELEASE_BUFFER_SIZE)



assert(DISPLAY_HEIGHT * 2 + 32 < 0x200)
allocate(hdmaTable1_a, lowram, 0x200)
allocate(hdmaTable1_b, lowram, 0x200)
allocate(hdmaTable2_a, lowram, 0x200)
allocate(hdmaTable2_b, lowram, 0x200)
allocate(hdmaTable3_a, lowram, 0x200)
allocate(hdmaTable3_b, lowram, 0x200)
allocate(hdmaTable4_a, lowram, 0x200)
allocate(hdmaTable4_b, lowram, 0x200)


// DB = 0x80
macro WaitForStartOfVBlank() {
    assert8a()

    InVBlankLoop{#}:
        assert(HVBJOY.vBlank == 0x80)
        bit.w   HVBJOY
        bmi     InVBlankLoop{#}

    WaitForVBlankLoop{#}:
        assert(HVBJOY.vBlank == 0x80)
        bit.w   HVBJOY
        bpl     WaitForVBlankLoop{#}
}


// DB = 0x80
macro WaitForHBlank() {
    assert8a()

    // Wait for H-Blank
    Loop{#}:
        assert(HVBJOY.hBlank == 0x40)
        bit.w   HVBJOY
        bvc     Loop{#}
}


// OUT: A = joypad low byte
// KEEP: X, Y
// DB = 0x80
macro ReadJoypadBits_l() {
    assert8a()

    // Latch the joypad
    lda.b   #JOYSER0.latch
    sta.w   JOYSER0
    stz.w   JOYSER0


    variable _i = 0
    while _i < 7 {
        lda.w   JOYSER0
        lsr
        rol.b   zpTmpByte
        _i = _i + 1
    }
    lda.w   JOYSER0
    lsr
    lda.b   zpTmpByte
    rol
}



// OUT: A = joypad hight byte (CAUTION: not rotated)
// KEEP: X, Y
// DB = 0x80
macro ReadJoypadBits_h() {
    variable _i = 0
    while _i < 3 {
        lda.w   JOYSER0
        lsr
        rol.b   zpTmpByte
        _i = _i + 1
    }

    lda.w   JOYSER0
    lsr
    lda.b   zpTmpByte
    and.b   #0b111
    rol
}



// DB = 0x80
au()
iu()
code()
function Main {
    rep     #$30
    sep     #$20
a8()
i16()

    stz.w   NMITIMEN


    // Set PPU registers


    lda.b   #INIDISP.force | 0xf
    sta.w   INIDISP

    lda.b   #(VRAM_BG_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG1SC
    sta.w   BG2SC
    sta.w   BG3SC
    sta.w   BG4SC

    lda.b   #((VRAM_BG_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg1.shift) | ((VRAM_BG_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg2.shift)
    sta.w   BG12NBA
    sta.w   BG34NBA

    lda.b   #TM.bg1 | TM.bg2 | TM.bg3 | TM.bg4
    sta.w   TM


    lda.b   #BG1_X_OFFSET
    sta.w   BG1HOFS
    lda.b   #BG1_X_OFFSET >> 16
    sta.w   BG1HOFS

    lda.b   #BG2_X_OFFSET
    sta.w   BG2HOFS
    lda.b   #BG2_X_OFFSET >> 16
    sta.w   BG2HOFS

    lda.b   #BG3_X_OFFSET
    sta.w   BG3HOFS
    lda.b   #BG3_X_OFFSET >> 16
    sta.w   BG3HOFS

    lda.b   #BG4_X_OFFSET
    sta.w   BG4HOFS
    lda.b   #BG4_X_OFFSET >> 16
    sta.w   BG4HOFS



    ldx.w   #VRAM_BG_MAP_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg_Tilemap)


    ldx.w   #VRAM_BG_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg_Tiles)

    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Palette)
    Dma.ForceBlank.ToCgram(Resources.Palette)


    ldx.w   #0
    jsr     BuildAndDisplayHdmaTables

    lda.b   #15
    sta.w   INIDISP


    MainLoop:
        lda.b   #1
        sta.b   releaseBufferNotFull

        // If a button has been pressed, Wait for WAIT_FOR_RELEASE_THREASHOLD scanlines of no button presses.
        // (To ensure buttonPressBuffer contains the initial key-press and contact bounce data)
        ldx.w   #1
        WaitForKeyRelease:
            WaitForHBlank()

            ReadJoypadBits_l()
            sta.b   zpTmpByte

            ReadJoypadBits_h()
            ora.b   zpTmpByte
            beq     +
                ldx.w   #WAIT_FOR_RELEASE_THREASHOLD
            +
            dex
            bne     WaitForKeyRelease


        // Wait until a button has been pressed
        WaitForKeyPressLoop:
            WaitForHBlank()

            ReadJoypadBits_l()
            sta.w   buttonPressBuffer_l + PRESS_BUFFER_SIZE - 1

            ReadJoypadBits_h()
            sta.w   buttonPressBuffer_h + PRESS_BUFFER_SIZE - 1
            ora.w   buttonPressBuffer_l + PRESS_BUFFER_SIZE - 1
            beq     WaitForKeyPressLoop


        // Read `N_KEYDOWN_SCANLINES`
        ldx.w   #PRESS_BUFFER_SIZE - 2
        KeyPressLoop:
            WaitForHBlank()

            ReadJoypadBits_l()
            sta.w   buttonPressBuffer_l,x

            ReadJoypadBits_h()
            sta.w   buttonPressBuffer_h,x

            dex
            bpl     KeyPressLoop


        ldy.w   #RELEASE_THREASHOLD
        ldx.w   #RELEASE_BUFFER_SIZE
        KeyReleaseLoop:
            dex
            bpl     +
                ldx.w   #RELEASE_BUFFER_SIZE - 1

                stz.b   releaseBufferNotFull
            +

            WaitForHBlank()

            ReadJoypadBits_l()
            sta.w   buttonReleaseBuffer_l,x

            ReadJoypadBits_h()
            sta.w   buttonReleaseBuffer_h,x

            ora.w   buttonReleaseBuffer_l,x
            beq     +
                ldy.w   #RELEASE_THREASHOLD

                jmp     KeyReleaseLoop
            +
            dey
            bne     KeyReleaseLoop

        rep     #$10
    i16()
        jsr     BuildAndDisplayHdmaTables

        jmp     MainLoop
}



// IN: X = buttonReleaseBuffer index
// DB = 0x7e
a8()
i16()
function BuildAndDisplayHdmaTables {
    lda.b   releaseBufferNotFull

    rep     #$30
a16()

    beq     +
    cpx.w   #RELEASE_BUFFER_SIZE - RELEASE_THREASHOLD - N_SCANLINES_TO_DISPLAY
    bcc     +
        lda.w   #RELEASE_BUFFER_SIZE - 1
        bra     ++
    +
        // The release buffer is full or contains enough data to display
        txa
        clc
        adc.w   #RELEASE_THREASHOLD + N_SCANLINES_TO_DISPLAY - 1
        cmp.w   #RELEASE_BUFFER_SIZE
        bcc     +
            // carry set
            sbc.w   #RELEASE_BUFFER_SIZE
    +
    sta.b   releaseBufferIndex

    sep     #$20
a8()


    ldy.b   currentHdmaTable
    beq     +
        ldy.w   #0
        bra     ++
    +
        ldy.w   #2
    +
    sty.w   currentHdmaTable


    // IN: X = table offset
    macro _BuildTable(evaluate table, evaluate data, evaluate bufferSize, evaluate yOffset) {
        assert8a()
        assert16i()

        ldy.b   currentHdmaTable
        lda.w   HdmaTable{table}_TableAddr,y
        sta.w   WMADDL
        lda.w   HdmaTable{table}_TableAddr + 1,y
        sta.w   WMADDM
        stz.w   WMADDH


        ldy.w   #-1

        if {yOffset} > 0 {
            // HDMA table entry - repeat mode, yOffset lines
            lda.b   #0x80 | {yOffset}
            sta.w   WMDATA

            -
                tya
                sta.w   WMDATA
                stz.w   WMDATA
                dey
                cpy.w   #-1 - {yOffset}
                bne     -
        }

        // Use a different `nScanlines1` value for each table to stagger HDMA entries
        // and the reduce maximum HDMA time in H-Blank.
        evaluate nScanlines1 = 127 - {table}
        evaluate nScanlines2 = DISPLAY_HEIGHT - {nScanlines1} - {yOffset}
        assert({nScanlines2} < 127)

        // HDMA table entry - repeat mode, nScanlines1 lines
        lda.b   #0x80 | {nScanlines1}
        sta.w   WMDATA

        -
            tya
            clc
            adc.w   {data},x
            sta.w   WMDATA
            stz.w   WMDATA

            dex
            bpl     +
                ldx.w   #{bufferSize} - 1
            +

            dey
            cpy.w   #-1 - {yOffset} - {nScanlines1}
            bne     +
                // HDMA table entry - repeat mode, nScanlines2 lines
                lda.b   #0x80 | {nScanlines2}
                sta.w   WMDATA
            +
            cpy.w   #-1 - DISPLAY_HEIGHT
            bne     -

        // HDMA end
        stz.w   WMDATA
    }
    ldx.w   #PRESS_BUFFER_SIZE - 1
    _BuildTable(1, buttonPressBuffer_l, PRESS_BUFFER_SIZE, Y_OFFSET)
    ldx.w   #PRESS_BUFFER_SIZE - 1
    _BuildTable(2, buttonPressBuffer_h, PRESS_BUFFER_SIZE, Y_OFFSET)
    ldx.b   releaseBufferIndex
    _BuildTable(3, buttonReleaseBuffer_l, RELEASE_BUFFER_SIZE, 0)
    ldx.b   releaseBufferIndex
    _BuildTable(4, buttonReleaseBuffer_h, RELEASE_BUFFER_SIZE, 0)


    // Clear release buffer
    ldx.w   #RELEASE_BUFFER_SIZE - 1
    -
        stz.w   buttonReleaseBuffer_l,x
        stz.w   buttonReleaseBuffer_h,x
        dex
        bpl     -


    WaitForStartOfVBlank()

    ldy.b   currentHdmaTable

    macro _SetupHdmaChannel(evaluate c, evaluate bBusAddr, addrTable) {
        assert8a()
        assert16i()

        lda.b   #DMAP.direction.toPpu | DMAP.transfer.writeTwice
        sta.w   DMAP{c}

        lda.b   #{bBusAddr}
        sta.w   BBAD{c}

        ldx.w   {addrTable},y
        stx.w   A1T{c}
        stz.w   A1B{c}
    }
    _SetupHdmaChannel(7, BG1VOFS, HdmaTable1_TableAddr)
    _SetupHdmaChannel(6, BG2VOFS, HdmaTable2_TableAddr)
    _SetupHdmaChannel(5, BG3VOFS, HdmaTable3_TableAddr)
    _SetupHdmaChannel(4, BG4VOFS, HdmaTable4_TableAddr)

    lda.b   #HDMAEN.dma7 | HDMAEN.dma6 | HDMAEN.dma5 | HDMAEN.dma4
    sta.w   HDMAEN

    rts
}


HdmaTable1_TableAddr:
    dw  hdmaTable1_a, hdmaTable1_b

HdmaTable2_TableAddr:
    dw  hdmaTable2_a, hdmaTable2_b

HdmaTable3_TableAddr:
    dw  hdmaTable3_a, hdmaTable3_b

HdmaTable4_TableAddr:
    dw  hdmaTable4_a, hdmaTable4_b


namespace Resources {
    insert Bg_Tiles,       "../../gen/test-patterns/scanline-bit-pattern.2bpp"
    insert Bg_Tilemap,     "../../gen/test-patterns/scanline-bit-pattern.tilemap"

    Palette:
        dw  0, 0, ToPalette( 6,  6,  0), ToPalette(31, 31,  0)  // B (yellow)
        dw  0, 0, ToPalette( 0,  8,  0), ToPalette( 0, 24,  0)  // Y (green)
        dw  0, 0, ToPalette( 6,  0,  6), ToPalette(31,  0, 31)  // select
        dw  0, 0, ToPalette( 6,  0,  6), ToPalette(31,  0, 31)  // start
        dw  0, 0, ToPalette( 6,  6,  6), ToPalette(31, 31, 31)  // up
        dw  0, 0, ToPalette( 6,  6,  6), ToPalette(31, 31, 31)  // down
        dw  0, 0, ToPalette( 6,  6,  6), ToPalette(31, 31, 31)  // left
        dw  0, 0, ToPalette( 6,  6,  6), ToPalette(31, 31, 31)  // right

        // Shifting BG2 4 lines saves me 4 rol instructions
        dw  0, 0, 0, 0
        dw  0, 0, 0, 0
        dw  0, 0, 0, 0
        dw  0, 0, 0, 0

        dw  0, 0, ToPalette( 8,  0,  0), ToPalette(31,  0,  0)  // A (red)
        dw  0, 0, ToPalette( 0,  0,  8), ToPalette( 6,  6, 31)  // X (blue)
        dw  0, 0, ToPalette( 6,  4,  6), ToPalette(25, 20, 25)  // L
        dw  0, 0, ToPalette( 6,  4,  6), ToPalette(25, 20, 25)  // R

    constant Palette.size = pc() - Palette
    assert(Palette.size == 16 * 4 * 2)
}

finalizeMemory()

