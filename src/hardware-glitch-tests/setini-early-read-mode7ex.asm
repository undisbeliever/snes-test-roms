// Tests if the `SETINI` (`$2133`) register reads the data-bus too early.
//
// This tests constantly writes the value `0x40` to `SETINI` (enable Mode 7
// EXTBG) while the previous value on the data-bus is `0x00`.
//
// Mode 7 EXTBG only uses 7 bits for the tile colour data.  This means a mode 7
// tile with a data value of `0x81` will use colour 1 in EXTBG mode or colour
// 129 in non-EXTBG mode.  Secondly, Mode 7 EXTBG is only available on Mode 7
// BG2 which is disabled if bit 6 of `SETINI` is clear.
//
//
// TEST OUTPUT:
//   * If the PPU reads the register at the correct time then the console will
//     only output a light green background.
//
//   * If the PPU reads the register early then the console will output a light
//     green background with either red or blue dots.
//      * a red dot means BG2 is disabled.
//      * a blue dot mean BG2 is enabled and the PPU is erroneously rendering an
//        8 bit mode 7 tile.
//
// You may need to reset your console a dozen times for the glitch to appear.
//
// The glitch appears ~20% of the time on both my 3-Chip 2/1/3 SFC console and
// my 1-Chip SFC console.
//
//
// Copyright (c) 2021, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define ROM_NAME = "SETINI EARLY RD M7EX"
define VERSION = 1
define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan


architecture wdc65816-strict

include "../common.inc"

createCodeBlock(code,       0x808000, 0x80ffaf)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)

include "../reset_handler.inc"
include "../break_handler.inc"
include "../dma_forceblank.inc"



// This demo does not use VBlank Interrupts.
constant NmiHandler = BreakHandler



// Setup and initialize the PPU
// REQUIRES: 8 bit A, 16 bit Index, DB access registers
macro SetupPpu() {
    assert8a()
    assert16i()

    stz.w   HDMAEN
    stz.w   NMITIMEN


    // Set PPU registers

    // Disable the display
    lda.b   #INIDISP.force | 0xf
    sta.w   INIDISP

    // Mode 7
    lda.b   #7
    sta.w   BGMODE

    // Mode 7 EXTBG mode uses BG 2
    lda.b   #TM.bg2
    sta.w   TM


    // Reset Mode 7 Matrix
    lda.b   #1
    // M7A = 1
    stz.w   M7A
    sta.w   M7A
    // M7B = 0
    stz.w   M7B
    stz.w   M7B
    // M7C = 0
    stz.w   M7C
    stz.w   M7C
    // M7D = 1
    stz.w   M7D
    sta.w   M7D

    // M7X = 0
    stz.w   M7X
    stz.w   M7X

    // M7Y = 0
    stz.w   M7Y
    stz.w   M7Y



    // Load palette
    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Palette)


    // Load tile data to VRAM
    ldx.w   #0
    stx.w   VMADD
    Dma.ForceBlank.ToVramH(Mode7Tile)


    // Enable display
    lda.b   #0x0f
    sta.w   INIDISP
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


    // Hammer the SETINI register, enabling Mode7 EXTBG while the previous value on the data bus is 0

    // Check if it is safe to write to the register before SETINI
    assert(SETINI - 1 == COLDATA)

    ldx.w   #(SETINI.extbg) << 8 | (0x00)

    MainLoop:
        stx.w   SETINI - 1

        bra     MainLoop
}



Mode7Tile:
    fill 8*8, 0x81
constant Mode7Tile.size = pc() - Mode7Tile


Palette:
    variable n = 0
    while n < 256 {
        if n == 0 {
            // Invalid - red
            dw  ToPalette(31, 0, 0)
        } else if n == 1 {
            // Valid - light green
            dw  ToPalette(15, 31, 15)
        } else {
            // Invalid - blue
            dw  ToPalette(0, 0, 31)
        }

        n = n + 1
    }
constant Palette.size = pc() - Palette


