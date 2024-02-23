// Object dropout test
//
// Copyright (c) 2024, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define MEMORY_MAP = LOROM
define ROM_SIZE = 1
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "OBJECT DROPOUT TEST"
define VERSION = 2

architecture wdc65816-strict

include "../common.inc"


createCodeBlock(code,       0x808000, 0x80ffaf)

createRamBlock(lowram,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)


constant VRAM_OBJ_TILES_WADDR = $6000

constant SCREEN_WIDTH = 256
constant SCREEN_HEIGHT = 224


include "../reset_handler.inc"
include "../break_handler.inc"
include "../dma_forceblank.inc"



// VBlank routine.
//
// REQUIRES: 8 bit A, 16 bit Index, DB = 0x80, DP = 0
macro VBlank() {
    assert8a()
    assert16i()
}

include "../vblank_interrupts.inc"



// Setup PPU registers and load data to the PPU.
//
// REQUIRES: force-blank, PPU registers reset
a8()
i16()
code()
function SetupPpu {
    stz.w   BGMODE

    lda.b   #OBSEL.size.s8_32 | (VRAM_OBJ_TILES_WADDR / OBSEL.base.walign) << OBSEL.base.shift
    sta.w   OBSEL

    ldx.w   #VRAM_OBJ_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Obj_Tiles)

    stz.w   CGADD
    stz.w   CGDATA
    stz.w   CGDATA

    lda.b   #128
    sta.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Obj_Palette)

    stz.w   OAMADDL
    stz.w   OAMADDH
    Dma.ForceBlank.ToOam(Resources.Obj_Oam)

    lda.b   #TM.obj
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



namespace Resources {
    insert Obj_Tiles,    "../../gen/obj-tests/hex8-4bpp-tiles.tiles"


Obj_Palette:
    macro _P(evaluate rgb) {
        evaluate r = (({rgb} >> 16) & 0xff) >> 3
        evaluate g = (({rgb} >>  8) & 0xff) >> 3
        evaluate b = (({rgb} >>  0) & 0xff) >> 3

        dw      0,  ToPalette({r}, {g}, {b}), ToPalette({r}, {g}, {b})
        fill    (16 - 3) * 2
    }
    _P($cc3333) // hsl(  0, 60, 50)
    _P($ccad33) // hsl( 45, 60, 50)
    _P($80cc33) // hsl( 90, 60, 50)
    _P($33cc59) // hsl(135, 60, 50)
    _P($33cccc) // hsl(180, 60, 50)
    _P($3359cc) // hsl(225, 60, 50)
    _P($8033cc) // hsl(270, 60, 50)
    _P($cc33a6) // hsl(315, 60, 50)

constant Obj_Palette.size = pc() - Obj_Palette



variable __nObjects = 0

macro _obj(evaluate x, evaluate y, evaluate tile) {
    db  {x}, {y}, {tile}, (({tile} & 7) << 2)
    __nObjects = __nObjects + 1
}

macro _obj_flipped(evaluate x, evaluate y, evaluate tile) {
    db  {x}, {y}, {tile}, (({tile} & 7) << 2) | OamFormat.attr.hFlip | OamFormat.attr.vFlip
    __nObjects = __nObjects + 1
}


Obj_Oam:
    // 32 sprites per scanline overflow test
    namespace TimeOverflowTest {
        constant N_SPRITES      = 32 + 4
        constant N_LEFT_RIGHT   = 8
        constant SPACING        = 10
        constant C_SPACING      = 2
        constant LEFT_X         = 12
        constant Y_POS          = 32 - 8 / 2

        constant CENTER_INDEX =  N_LEFT_RIGHT
        constant RIGHT_INDEX = N_SPRITES - N_LEFT_RIGHT
        constant N_CENTER = (N_SPRITES - N_LEFT_RIGHT * 2)

        constant RIGHT_X  = SCREEN_WIDTH - N_LEFT_RIGHT * SPACING - LEFT_X
        constant CENTER_X = (SCREEN_WIDTH - N_CENTER * C_SPACING) / 2

        variable _i = 0
        while _i < N_SPRITES {
            if _i < CENTER_INDEX {
                _obj(LEFT_X + _i * SPACING, Y_POS, _i)
            } else if _i < RIGHT_INDEX {
                _obj(CENTER_X + (_i - CENTER_INDEX) * C_SPACING, Y_POS, _i)
            } else {
                _obj(RIGHT_X + (_i - RIGHT_INDEX) * SPACING, Y_POS, _i)
            }

            _i = _i + 1
        }
    }

    // 34 tile-slivers per scanline overflow test
    namespace RangeOverflowTest {
        constant N_SPRITES = 12
        constant X_SPACING = 16
        constant Y_SPACING =  3

        constant X_START   = (SCREEN_WIDTH - X_SPACING * (N_SPRITES - 1) - 32) / 2
        constant Y_START   = (SCREEN_HEIGHT - Y_SPACING * N_SPRITES/2 - 32) / 3

        variable _i = 0
        while _i < N_SPRITES {
            if _i < N_SPRITES / 2 {
                variable _y = Y_START + _i * Y_SPACING
            } else {
                variable _y = Y_START + (N_SPRITES - _i) * Y_SPACING
            }

            _obj(X_START + _i * X_SPACING, _y, _i)

            _i = _i + 1
        }
    }

    // 34 tile-slivers per scanline overflow test
    namespace RangeOverflowTest_Flipped {
        constant N_SPRITES = 12
        constant X_SPACING = 16
        constant Y_SPACING =  3

        constant X_START   = (SCREEN_WIDTH - X_SPACING * (N_SPRITES - 1) - 32) / 2
        constant Y_START   = (SCREEN_HEIGHT - Y_SPACING * N_SPRITES/2 - 32) * 2 / 3

        variable _i = 0
        while _i < N_SPRITES {
            if _i < N_SPRITES / 2 {
                variable _y = Y_START + _i * Y_SPACING
            } else {
                variable _y = Y_START + (N_SPRITES - _i) * Y_SPACING
            }

            _obj_flipped(X_START + _i * X_SPACING, _y, _i)

            _i = _i + 1
        }
    }

    // If a sprite has an X position of 256, it counts towards the 32 sprites per scanline limit
    namespace X256BugTest {
        constant N_OFFSCREEN = 8
        constant N_ONSCREEN  = 32

        constant X_SPACING = 8

        constant Y_POS   = SCREEN_HEIGHT - 8 - TimeOverflowTest.Y_POS

        variable _i = 0
        while _i < N_OFFSCREEN {
            _obj(256, Y_POS, _i)
            _i = _i + 1
        }
        while _i < N_OFFSCREEN + N_ONSCREEN {
            _obj((_i - N_OFFSCREEN) * X_SPACING, Y_POS, _i)
            _i = _i + 1
        }
    }

    fill    (128 - __nObjects) * 4, -32

Obj_OamHiTable:
    namespace TimeOverflowTest {
        assert(N_SPRITES % 4 == 0)
        fill    N_SPRITES / 4, 0
    }
    namespace RangeOverflowTest {
        assert(N_SPRITES % 4 == 0)
        fill    N_SPRITES / 4, %10101010
    }
    namespace RangeOverflowTest_Flipped {
        assert(N_SPRITES % 4 == 0)
        fill    N_SPRITES / 4, %10101010
    }
    namespace X256BugTest {
        assert(N_OFFSCREEN % 4 == 0)
        fill    N_OFFSCREEN / 4, %11110101  // half large and half small

        assert(N_ONSCREEN % 4 == 0)
        fill    N_ONSCREEN / 4, 0
    }
    fill    (128 - __nObjects) / 4, 0

constant Obj_Oam.size = pc() - Obj_Oam
assert(Obj_Oam.size == 544)

}

