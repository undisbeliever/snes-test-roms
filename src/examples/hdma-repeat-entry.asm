// Test ROM showing how to implement a repeat HDMA entry.
//
// This test ROM was used to generate a screenshot for the SNESdev wiki.
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT



define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "HDMA REPEAT ENTRY"
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
    lda.b   #DMAP.direction.toPpu | DMAP.transfer.writeTwice
    sta.w   DMAP7

    lda.b   #BG1HOFS
    sta.w   BBAD7

    // HDMA table address
    ldx.w   #HdmaTable
    stx.w   A1T7
    lda.b   #HdmaTable >> 16
    sta.w   A1B7

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



// HDMA Table for the `BG1HOFS` register (one register, write twice transfer pattern).
HdmaTable:
    db  0x80 | 127      // 127 scanlines, repeat entry (maximum number of repeat scanlines per entry)
        // 127 words (254 bytes) of BG1HOFS data for the next 127 scanlines
        dw  144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270

    db  0x80 | 97       // 97 scanlines, repeat entry (+127 = 224 scanlines total)
        // 97 words (194 bytes) of BG1HOFS data for the next 97 scanlines
        dw  271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 300, 301, 302, 303, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313, 314, 315, 316, 317, 318, 319, 320, 321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347, 348, 349, 350, 351, 352, 353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367

    db  0               // End HDMA table

constant HdmaTable.size = pc() - HdmaTable

assert(HdmaTable.size == 224 * 2 + 3)



// Resources
// =========

namespace Resources {
    insert Bg1_Palette,  "../../gen/hdma-hoffset-examples/vertical-bar-2bpp.palette"
    insert Bg1_Tiles,   "../../gen/hdma-hoffset-examples/vertical-bar-2bpp.2bpp"
    insert Bg1_Tilemap, "../../gen/hdma-hoffset-examples/vertical-bar-2bpp.tilemap"
}




