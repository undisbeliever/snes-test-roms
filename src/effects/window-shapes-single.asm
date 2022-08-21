// A small sample of shapes that can be created from a single window, built
// using hard-coded HDMA tables.
//
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT



define ROM_NAME = "SINGLE WINDOW SHAPES"
define VERSION = 0

define MEMORY_MAP = LOROM
define ROM_SIZE = 1

define ROM_SPEED = fast
define REGION = Japan


define VBLANK_READS_JOYPAD


architecture wdc65816-strict

include "../common.inc"



createCodeBlock(code,       0x808000, 0x80ffaf)

createRamBlock(lowram,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)


include "../reset_handler.inc"
include "../break_handler.inc"
include "../dma_forceblank.inc"


constant DISPLAY_WIDTH = 256
constant DISPLAY_HEIGHT = 224


// Number of display frames between HDMA tables
constant CHANGE_HDMA_TABLE_INTERVAL = 2 * 60


// Frame countdown timer until the next HDMA table is displayed
// (uint16)
allocate(countdownToNextHdmaTable,   lowram, 2)


// The HDMA table to display.
// (word index into `HdmaTablesTable`)
allocate(hdmaTableIndex, lowram, 2)



// VBlank routine
//
// REQUIRES: 8 bit A, 16 bit Index, DB = 0x80, DP = 0
macro VBlank() {
    assert8a()
    assert16i()

    // Setup and enable HDMA channel 7

    // HDMA to WH0 & WH1
    ldx.w   #DMAP.direction.toPpu | DMAP.transfer.two | (WH0 << 8)
    stx.w   DMAP7       // also sets BBAD7

    ldx.w   hdmaTableIndex

    ldy.w   HdmaTablesTable,x
    sty.w   A1T7
    lda.b   #HdmaTablesTable >> 16
    sta.w   A1B7

    lda.b   #HDMAEN.dma7
    sta.w   HDMAEN
}

include "../vblank_interrupts.inc"



au()
iu()
code()
function Main {
    lda.b   #INIDISP.force | 0x0f
    sta.w   INIDISP


    // Reset variables
    ldx.w   #0
    stx.w   hdmaTableIndex

    ldx.w   #CHANGE_HDMA_TABLE_INTERVAL - 1
    stx.w   countdownToNextHdmaTable


    // Set Backdrop colour to white
    stz.w   CGADD
    lda.b   #0xFF
    sta.w   CGDATA
    sta.w   CGDATA


    // Window settings

    // Disable windows for backgrounds and objects
    stz.w   TMW
    stz.w   TSW

    // Enable window 1 for color math
    lda.b   #(WSEL.win1.enable) << WOBJSEL.color.shift
    sta.w   WOBJSEL

    // Set window mask logic for color math
    lda.b   #WOBJLOG.logic.or << WOBJLOG.color.shift
    sta.w   WOBJLOG


    // Color math settings

    // Clip colors to black inside the color window
    // Disable color math outside the color window
    // Use fixed color for color math
    lda.b   #CGWSEL.clip.inside | CGWSEL.prevent.outside
    sta.w   CGWSEL

    // Color math addition
    // Enable color math on backdrop
    lda.b   #CGADSUB.color.add | CGADSUB.enable.backdrop
    sta.w   CGADSUB

    // Set fixed color to violet
    lda.b   #COLDATA.plane.blue  | 31
    sta.w   COLDATA
    lda.b   #COLDATA.plane.green | 0
    sta.w   COLDATA
    lda.b   #COLDATA.plane.red   | 15
    sta.w   COLDATA


    EnableVblankInterrupts()

    lda.b   #0x0f
    sta.w   INIDISP


    TimerLoop:
        ldy.w   countdownToNextHdmaTable
        dey
        bpl     ++
            // countdown timer is 0, display the next HDMA Table
            ldx.w   hdmaTableIndex
            inx
            inx
            cpx.w   #HdmaTablesTable.size
            bcc     +
                ldx.w   #0
            +
            stx.w   hdmaTableIndex

            ldy.w   #CHANGE_HDMA_TABLE_INTERVAL - 1
        +
        sty.w   countdownToNextHdmaTable

        jsr     WaitFrame

        ldx.w   joypadPressed
        beq     TimerLoop


    // A button has been pressed, switch to joypad controls
    ButtonLoop:
        lda.w   joypadPressed + 1
        and.b   #JOYH.left | JOYH.y
        beq     SkipPrevious
            // Display the previous HDMA table
            ldx.w   hdmaTableIndex
            dex
            dex
            bpl     +
                ldx.w   #HdmaTablesTable.size - 2
            +
            stx.w   hdmaTableIndex
        SkipPrevious:


        lda.w   joypadPressed + 1
        and.b   #JOYH.right | JOYH.b
        beq     SkipNext
            // Display the next HDMA table
            ldx.w   hdmaTableIndex
            inx
            inx
            cpx.w   #HdmaTablesTable.size
            bcc     +
                ldx.w   #0
            +
            stx.w   hdmaTableIndex
        SkipNext:

        jsr     WaitFrame

        bra     ButtonLoop

}



// List of HDMA tables to registers WH0 and WH1
HdmaTablesTable:
    dw  LeftGreaterThanRight
    dw  RectangularWindow
    dw  TallRectangularWindow
    dw  Trapezium_0
    dw  Trapezium_1
    dw  Trapezium_2
    dw  TriangleR_0
    dw  TriangleR_1
    dw  TriangleR_2
    dw  TriangleR_3
    dw  TriangleR_4
    dw  Octagon
    dw  MultipleShapes
    dw  Circle
constant HdmaTablesTable.size = pc() - HdmaTablesTable


// Assert `HdmaTablesTable` can be accessed with DB = PB (in VBlank macro)
assert(HdmaTablesTable >> 16 == pc() >> 16)




// Demonstrates that there is no window if `left > right`.
LeftGreaterThanRight:
namespace LeftGreaterThanRight {
    variable scanline = 0

    // repeat mode, 127 scanlines
    db  0x80 | 127
        while scanline < 127 {
            // Subtracting 254 so there is a scanline where WH0 == WH1
            db  scanline, 254 - scanline
            scanline = scanline + 1
        }

    // repeat mode, 97 scanlines
    db  0x80 | (DISPLAY_HEIGHT - 127)
        while scanline < DISPLAY_HEIGHT {
            db  scanline, 254 - scanline
            scanline = scanline + 1
        }

    // End of HDMA table
    db  0
}




// Rectangular window
RectangularWindow:
namespace RectangularWindow {
    constant HEIGHT = 100
    constant WIDTH  = 100
    constant X = (DISPLAY_WIDTH - WIDTH) / 2
    constant Y = (DISPLAY_HEIGHT - HEIGHT) / 2

    assert(X + WIDTH <= 0xff)

    // Disable window for the first `Y` scanlines
    // (if Y >= 0x80, two HDMA entries are required)
    assert(Y < 0x80)
    db  Y
        // Disable window (WH0 > WH1)
        db  0xff, 0

    // Enable window for `HEIGHT` scanlines
    // (if HEIGHT >= 0x80, two HDMA entries are required)
    assert(HEIGHT < 0x80)
    db HEIGHT
        db  X, X + WIDTH

    // Disable window for 1 scanline
    db 1
        // Disable window (WH0 > WH1)
        db  0xff, 0

    // End HDMA Table
    db 0
}




// Tall Rectangular window (> 127 scanlines tall)
TallRectangularWindow:
namespace TallRectangularWindow {
    constant HEIGHT = 200
    constant WIDTH  =  80
    constant X = (DISPLAY_WIDTH - WIDTH) / 2
    constant Y = (DISPLAY_HEIGHT - HEIGHT) / 2

    assert(X + WIDTH <= 0xff)

    // Disable window for the first `Y` scanlines
    // (if Y >= 0x80, two HDMA entries are required)
    assert(Y < 0x80)
    db  Y
        // Disable window (WH0 > WH1)
        db  0xff, 0


    // Enable window for `HEIGHT` scanlines
    //
    // Since `HEIGHT > 0x7f`, two HDMA entries are required.
    assert(HEIGHT > 0x7f)
    assert(HEIGHT < 0x7f * 2)

    // 127 scanlines
    db  0x7f
        // Enable window (X to `X + WIDTH`)
        db  X, X + WIDTH

    // `HEIGHT - 127` scanlines
    db HEIGHT - 127
        // Enable window (X to `X + WIDTH`)
        db  X, X + WIDTH


    // Disable window for 1 scanline
    db 1
        // Disable window (WH0 > WH1)
        db  0xff, 0

    // End HDMA Table
    db 0
}




// Used for converting 8.8 fixed point to integers (and vice versa)
constant FIXED_POINT_SCALE = 0x100


// A macro to generate a HDMA table for an acute triangle with an axis-aligned base.
//
// There are many different ways of drawing a triangle, this macro uses a fixed-point delta to
// calculate the left and right position for each scanline.
//
// ASSUMES: top_x/top_y are inside the screen
//
// PARAM: left: the starting left window position (integer)
// PARAM: right: the starting right window position (integer)
// PARAM: top_y: the Y-position of the top of the triangle (integer)
// PARAM: height: the height of the triangle (integer)
// PARAM: dx_left: the delta-X of left side of the triangle (8.8 fixed point integer)
// PARAM: dx_right: the delta-X of the right side of the triangle (8.8 fixed point integer)
macro Trapezium_HdmaTable(variable left, variable right, evaluate top_y, evaluate height, evaluate dx_left, evaluate dx_right) {
    assert(left <= right)
    assert({height} > 0)
    assert({top_y} + {height} <= DISPLAY_HEIGHT)

    // Disable window for the first `top_y` scanlines
    if {top_y} > 127 {
        // HDMA entry must be split in two if `top_y` > 127
        db  127
            db  0xff, 0
        db  {top_y} - 127
            db  0xff, 0
    } else if {top_y} > 0 {
        db  {top_y}
            db  0xff, 0
    }

    left = left * FIXED_POINT_SCALE + FIXED_POINT_SCALE / 2
    right = right * FIXED_POINT_SCALE + FIXED_POINT_SCALE / 2

    // Start a HDMA entry in repeat mode
    if {height} > 127 {
        db  0x80 | 127
    } else {
        db  0x80 | {height}
    }

    variable i = 0
    while i < {height} {
        if i == 127 {
            // After 127 scanlines the first HDMA table is completed.
            // Start a new HDMA entry for the remaining scanlines.
            db  0x80 | ({height} - 127)
        }

        db  left / FIXED_POINT_SCALE, right / FIXED_POINT_SCALE

        left = left - {dx_left}
        if left < 0 {
            left = 0
        }

        right = right + {dx_right}
        if right >= DISPLAY_WIDTH * FIXED_POINT_SCALE {
            right = (DISPLAY_WIDTH * FIXED_POINT_SCALE) - 1
        }

        i = i + 1
    }

    // Disable window for 1 scanline
    db  1
        db  0xff, 0

    // End HDMA table
    db  0
}


// A Trapezium can be used to draw an acute triangle with an horizontal base
Trapezium_0:
    Trapezium_HdmaTable(127, 128, 20, 184, 0x005c, 0x005c)


Trapezium_1:
    Trapezium_HdmaTable(54, 64, 130, 94, 0x00d8, 0x0070)

Trapezium_2:
    Trapezium_HdmaTable(100, 200, 20, 80, 0x00e0, 0x00e0)




// Generate a HDMA repeat mode block for two angled window positions.
//
// NOTE: This inline macro will only create a single HDMA table entry.
//       Height MUST be <= 127.
//
// NOTE: This inline macro will modify the `left` and `right` variables.
//
// PARAM: height: The number of scanlines to draw (integer <= 127)
// PARAM: dx_left/dx_right: The delta-x for each scanline (.8 signed fixed point)
inline __DrawAngledLines(evaluate height, evaluate dx_left, evaluate dx_right) {
    if {height} > 0 {
        // Start a HDMA entry in repeat mode
        assert({height} <= 127)
        db  0x80 | {height}

        variable i = 0
        while i < {height} {
            left = left + {dx_left}
            right = right + {dx_right}

            if right < 0 || left >= DISPLAY_WIDTH * FIXED_POINT_SCALE {
                // Window is off-screen
                db  255, 0
            } else {
                // Window is on-screen, clamp window positions to an 8 bit value
                variable l = left / FIXED_POINT_SCALE
                if l < 0 {
                    l = 0
                }

                variable r = right / FIXED_POINT_SCALE
                if r >= 255 {
                    r = 255
                }

                db  l, r
            }

            i = i + 1
        }
    }
}


// A macro to generate a HDMA table for a triangle pointing to the right.
//
// There are many different ways of drawing a triangle, this macro uses a fixed-point delta to
// calculate the left and right position for each scanline.
//
// ASSUMES: y-positions are inside the screen
//
macro TrianglePointingRight_HdmaTable(evaluate top_x, evaluate top_y, evaluate center_x, evaluate center_y, evaluate bottom_x, evaluate bottom_y) {
    evaluate h1 = {center_y} - {top_y}
    evaluate h2 = {bottom_y} - {center_y}

    assert({top_y} >= 0 && {top_y} <= 127 * 2)
    assert({h1} >= 0 && {h1} <= 127 * 2)
    assert({h2} >= 0 && {h2} <= 127 * 2)
    assert({bottom_y} < DISPLAY_HEIGHT)
    assert({center_x} >= {top_x})
    assert({center_x} >= {bottom_x})

    evaluate dx_left   = (({bottom_x} -    {top_x}) * FIXED_POINT_SCALE) / ({h1} + {h2})
    evaluate dx_right1 = (({center_x} -    {top_x}) * FIXED_POINT_SCALE) / {h1}
    evaluate dx_right2 = (({bottom_x} - {center_x}) * FIXED_POINT_SCALE) / {h2}


    // Disable window for the first `top_y` scanlines
    if {top_y} > 127 {
        // HDMA entry must be split in two if `top_y` > 127
        db  127
            db  0xff, 0
        db  {top_y} - 127
            db  0xff, 0
    } else if {top_y} > 0 {
        db  {top_y}
            db  0xff, 0
    }


    variable left  = {top_x} * FIXED_POINT_SCALE
    variable right = left

    if {h1} > 127 {
        __DrawAngledLines(127,        {dx_left}, {dx_right1})
        __DrawAngledLines({h1} - 127, {dx_left}, {dx_right1})
    } else {
        __DrawAngledLines({h1},       {dx_left}, {dx_right1})
    }

    if {h2} > 127 {
        __DrawAngledLines(127,        {dx_left}, {dx_right2})
        __DrawAngledLines({h2} - 127, {dx_left}, {dx_right2})
    } else {
        __DrawAngledLines({h2},       {dx_left}, {dx_right2})
    }


    // Disable window for 1 scanline
    db  1
        db  0xff, 0

    // End HDMA table
    db  0
}

TriangleR_0:
    TrianglePointingRight_HdmaTable(20, 20,   236, 112,   20, 204)

TriangleR_1:
    assert(200 - 10 > 0x80)
    TrianglePointingRight_HdmaTable(10, 10,   246, 200,   128, 214)


// Aspect corrected equilateral triangle
TriangleR_2:
    TrianglePointingRight_HdmaTable(79, 55,    197, 92,   110, 189)


// Triangle with the top horizontally off-screen
TriangleR_3:
    TrianglePointingRight_HdmaTable(-80, 20,   150, 150,   80, 200)


// Triangle with the top horizontally off-screen
TriangleR_4:
    TrianglePointingRight_HdmaTable(120, 20,   320, 100,   300, 200)




Octagon:
namespace Octagon {
    constant SIDE_LENTH    = 70
    constant DIAGONAL_AXIS = 49     // sqrt(70**2 / 2)
    constant Y_OFFSET      = (DISPLAY_HEIGHT - DIAGONAL_AXIS * 2 - SIDE_LENTH) / 2

    constant TOP_LEFT  = (DISPLAY_WIDTH - SIDE_LENTH) / 2
    constant TOP_RIGHT = TOP_LEFT + SIDE_LENTH - 1

    constant MIDDLE_LEFT = TOP_LEFT - DIAGONAL_AXIS
    constant MIDDLE_RIGHT = MIDDLE_LEFT + DIAGONAL_AXIS * 2 + SIDE_LENTH - 1


    // Disable window for `Y_OFFSET` scanlines
    assert(Y_OFFSET < 0x80)
    db  Y_OFFSET
        // Disable window (WH0 > WH1)
        db  0xff, 0


    // Draw angled lines.
    //
    // Repeat mode, `DIAGONAL_AXIS` scanlines
    assert(DIAGONAL_AXIS < 0x80)
    db  0x80 | DIAGONAL_AXIS
        variable i = 0
        while i < DIAGONAL_AXIS {
            db  TOP_LEFT - i, TOP_RIGHT + i
            i = i + 1
        }


    // Fixed window for `SIDE_LENTH` scanlines
    assert(SIDE_LENTH < 0x80)
    db  SIDE_LENTH
        db  MIDDLE_LEFT, MIDDLE_RIGHT


    // Draw angled lines.
    //
    // Repeat mode, `DIAGONAL_AXIS` scanlines
    assert(DIAGONAL_AXIS < 0x80)
    db  0x80 | DIAGONAL_AXIS
        variable i = 0
        while i < DIAGONAL_AXIS {
            db  MIDDLE_LEFT + i + 1, MIDDLE_RIGHT - i - 1
            i = i + 1
        }


    // Disable window for 1 scanline
    db 1
        // Disable window (WH0 > WH1)
        db  0xff, 0

    // End HDMA Table
    db 0
}




// A single window can display multiple shapes, so long as they do not overlap
MultipleShapes:
namespace MultipleShapes {
    // Shape 1 - rectangle
    db  22
        db  100, 156

    // 10 scanlines with no window
    db  10
        db  0xff, 0

    // Shape 2 - diamond
    // (HDMA repeat mode)
    db  0x80 | (30 * 2 - 1)
        variable i = 0
        while i < 30 {
            db  60 - i, 60 + i
            i = i + 1
        }
        i = i - 1
        while i > 0 {
            i = i - 1
            db  60 - i, 60 + i
        }


    // 10 scanlines with no window
    db  10
        db  0xff, 0


    // Shape 3 - another rectangle
    db  22
        db  100, 156


    // 10 scanlines with no window
    db  10
        db  0xff, 0


    // Shape 4 - diamond
    // (HDMA repeat mode)
    db  0x80 | (30 * 2 - 1)
        variable i = 0
        while i < 30 {
            db  196 - i, 196 + i
            i = i + 1
        }
        i = i - 1
        while i > 0 {
            i = i - 1
            db  196 - i, 196 + i
        }


    // 10 scanlines with no window
    db  10
        db  0xff, 0


    // Shape 4 - one final rectangle
    db  22
        db  100, 156


    // Disable window for 1 scanline
    db  1
        db  0xff, 0

    // End HDMA table
    db  0
}




// A HDMA circular window
Circle:
    // Disable window for 62 scanlines
    db  62
        db  0xff, 0

    // repeat mode, 50 scanlines
    db 0x80 | 50
        // Calculated using python
        //
        //    y = r - i - 1
        //    offset = math.sqrt(r ** 2 - y ** 2) * x_scale
        //    left = round(cx - offset)
        //    right = round(cx + offset)

        db  119, 137
        db  116, 140
        db  113, 143
        db  111, 145
        db  109, 147
        db  107, 149
        db  106, 150
        db  104, 152
        db  103, 153
        db  102, 154
        db  101, 155
        db  100, 156
        db   99, 157
        db   98, 158
        db   97, 159
        db   96, 160
        db   95, 161
        db   94, 162
        db   94, 162
        db   93, 163
        db   92, 164
        db   92, 164
        db   91, 165
        db   91, 165
        db   90, 166
        db   90, 166
        db   89, 167
        db   89, 167
        db   88, 168
        db   88, 168
        db   88, 168
        db   87, 169
        db   87, 169
        db   87, 169
        db   86, 170
        db   86, 170
        db   86, 170
        db   86, 170
        db   85, 171
        db   85, 171
        db   85, 171
        db   85, 171
        db   85, 171
        db   85, 171
        db   84, 172
        db   84, 172
        db   84, 172
        db   84, 172
        db   84, 172
        db   84, 172

    // repeat mode, 50 scanlines
    db 0x80 | 50
        // The following is the reverse of the previous block
        db   84, 172
        db   84, 172
        db   84, 172
        db   84, 172
        db   84, 172
        db   84, 172
        db   85, 171
        db   85, 171
        db   85, 171
        db   85, 171
        db   85, 171
        db   85, 171
        db   86, 170
        db   86, 170
        db   86, 170
        db   86, 170
        db   87, 169
        db   87, 169
        db   87, 169
        db   88, 168
        db   88, 168
        db   88, 168
        db   89, 167
        db   89, 167
        db   90, 166
        db   90, 166
        db   91, 165
        db   91, 165
        db   92, 164
        db   92, 164
        db   93, 163
        db   94, 162
        db   94, 162
        db   95, 161
        db   96, 160
        db   97, 159
        db   98, 158
        db   99, 157
        db  100, 156
        db  101, 155
        db  102, 154
        db  103, 153
        db  104, 152
        db  106, 150
        db  107, 149
        db  109, 147
        db  111, 145
        db  113, 143
        db  116, 140
        db  119, 137

    // Disable window for 1 scanline
    db  1
        db  0xff, 0

    // End HDMA table
    db  0


finalizeMemory()

