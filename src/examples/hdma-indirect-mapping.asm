// Test ROM showing how to use HDMA indirect mode to map a contiguous array to a HDMA table.
//
// This test ROM was used to generate a screenshot for the SNESdev wiki.
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "HDMA INDIRECT MAPPING"
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



// Setup the HDMA registers.
//
// Uses DMA channel 7.
//
// REQUIRES: 8 bit A, 16 bit Index, DB = 0x80, DP = 0
// REQUIRES: HDMA disabled
a8()
i16()
code()
function SetupHdma {
    // HDMA to `BG1HOFS`
    lda.b   #DMAP.direction.toPpu | DMAP.addressing.indirect | DMAP.transfer.writeTwice
    sta.w   DMAP7

    lda.b   #BG1HOFS
    sta.w   BBAD7

    // HDMA table address
    ldx.w   #IndirectHdmaTable
    stx.w   A1T7
    lda.b   #IndirectHdmaTable >> 16
    sta.w   A1B7

    // HDMA indirect bank
    lda.b   #ContiguousArray >> 16
    sta.w   DASB7

    rts
}



// VBlank routine.
//
// REQUIRES: 8 bit A, 16 bit Index, DB = 0x80, DP = 0
macro VBlank() {
    // Enable HDMA.
    // HDMA should be enabled during VBlank.
    // There is no need to write to `HDMAEN` on every VBlank, it can be written to on a single VBlank.
    lda.b   #HDMAEN.dma7
    sta.w   HDMAEN
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

    jsr     WaitFrame

    lda.b   #0x0f
    sta.w   INIDISP


    MainLoop:
        jsr     WaitFrame
        jmp     MainLoop
}



// Contiguous array of `BG1HOFS` values for all 244 scanlines
ContiguousArray:
    dw  367, 366, 365, 364, 363, 362, 361, 360, 359, 358, 357, 356, 355, 354, 353, 352, 351, 350, 349, 348, 347, 346, 345, 344, 343, 342, 341, 340, 339, 338, 337, 336, 335, 334, 333, 332, 331, 330, 329, 328, 327, 326, 325, 324, 323, 322, 321, 320, 319, 318, 317, 316, 315, 314, 313, 312, 311, 310, 309, 308, 307, 306, 305, 304, 303, 302, 301, 300, 299, 298, 297, 296, 295, 294, 293, 292, 291, 290, 289, 288, 287, 286, 285, 284, 283, 282, 281, 280, 279, 278, 277, 276, 275, 274, 273, 272, 271, 270, 269, 268, 267, 266, 265, 264, 263, 262, 261, 260, 259, 258, 257, 256, 255, 254, 253, 252, 251, 250, 249, 248, 247, 246, 245, 244, 243, 242, 241, 240, 239, 238, 237, 236, 235, 234, 233, 232, 231, 230, 229, 228, 227, 226, 225, 224, 223, 222, 221, 220, 219, 218, 217, 216, 215, 214, 213, 212, 211, 210, 209, 208, 207, 206, 205, 204, 203, 202, 201, 200, 199, 198, 197, 196, 195, 194, 193, 192, 191, 190, 189, 188, 187, 186, 185, 184, 183, 182, 181, 180, 179, 178, 177, 176, 175, 174, 173, 172, 171, 170, 169, 168, 167, 166, 165, 164, 163, 162, 161, 160, 159, 158, 157, 156, 155, 154, 153, 152, 151, 150, 149, 148, 147, 146, 145, 144

constant ContiguousArray.size = pc() - ContiguousArray

assert(ContiguousArray.size == 224 * 2)



// Indirect HDMA Table for the `BG1HOFS` register (one register, write twice transfer pattern).
IndirectHdmaTable:
    // Cannot fit all 224 scanlines in a single HDMA entry.
    // Splitting the table into two equally sized entries.
    db  0x80 | 112      // 112 scanlines, repeat entry
        // Word address pointing to the first half of ContiguousArray
        dw  ContiguousArray

    db  0x80 | 112      // 112 scanlines, repeat entry (+112 = 224 scanlines total)
        // Word address pointing to the second half of ContiguousArray
        dw  ContiguousArray + 112 * 2

    db  0               // End HDMA table



// Resources
// =========

namespace Resources {
    insert Bg1_Palette,  "../../gen/hdma-hoffset-examples/vertical-bar-2bpp.palette"
    insert Bg1_Tiles,   "../../gen/hdma-hoffset-examples/vertical-bar-2bpp.2bpp"
    insert Bg1_Tilemap, "../../gen/hdma-hoffset-examples/vertical-bar-2bpp.tilemap"
}




