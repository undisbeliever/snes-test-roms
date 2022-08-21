// A precalculated horizontally-symmetrical single-window HDMA demo.
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define ROM_NAME = "SYMMETRICAL WINDOW"
define VERSION = 0

define MEMORY_MAP = LOROM
define ROM_SIZE = 1

define ROM_SPEED = fast
define REGION = Japan



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



constant DISPLAY_WIDTH = 256
constant DISPLAY_HEIGHT = 224


constant HDMA_ENTRY_MAX_SCANLINES = 127



// zero-page temporary word variables
allocate(zpTmp0, zeropage, 2)
allocate(zpTmp1, zeropage, 2)
allocate(zpTmp2, zeropage, 2)
allocate(zpTmp3, zeropage, 2)




// HDMA Double Buffering
// =====================

constant HDMA_BUFFER_SIZE = 2048

constant HDMA_CHANNEL = 7


// Notifies the `HdmaBuffer_VBlank` macro that a new HDMA buffer is available.
//
// If non-zero, a HDMA from `currentHdmaBuffer` to `hdmaBufferTarget` will be activated
// on the next VBlank.
//
// (byte flag)
allocate(hdmaBufferVBlankFlag, lowram, 1)


// Address of current HDMA buffer.
// MUST point to `hdmaBuffer0` or `hdmaBuffer1`
// MUST only be modified by `HdmaBuffer_NextBuffer`
// (word address)
allocate(currentHdmaBuffer, lowram, 2)


// Shadow of `DMAP` and `BBAD` HDMA registers for the HDMA buffer
// (word)
allocate(hdmaBufferTarget, lowram, 2)


// HDMA double buffers
// (2x HDMA_BUFFER_SIZE byte array)
allocate(hdmaBuffer0, wram7e, HDMA_BUFFER_SIZE)
allocate(hdmaBuffer1, wram7e, HDMA_BUFFER_SIZE)



// Initialize the HDMA double buffer to a given PPU register.
//
// REQUIRES: 8 bit A, 16 bit Index, DP = 0
// DB access registers
macro HdmaBuffer_Init(evaluate dmap, evaluate bbad) {
    assert8a()
    assert16i()

    ldx.w   #({dmap} & 0xff) | ({bbad} << 8)
    stx.w   hdmaBufferTarget

    ldx.w   #hdmaBuffer0
    stx.w   currentHdmaBuffer

    stz.w   hdmaBufferVBlankFlag
}



// Retrieve the next HDMA buffer.
//
// NOTE: This buffer MUST BE committed and the VBlank routine MUST be processed before the next
//       `HdmaBuffer_NextBuffer` call.
//
// RETURN: x = currentHdmaBuffer = the new HDMA buffer
//
// DB access low-RAM
au()
i16()
code()
function HdmaBuffer_NextBuffer {
    // Do not transfer the new buffer until it has been committed
    stz.w   hdmaBufferVBlankFlag


    ldx.w   currentHdmaBuffer
    cpx.w   #hdmaBuffer0
    bne     Else
        ldx.w   #hdmaBuffer1
        bra     EndIf
Else:
        ldx.w   #hdmaBuffer0
EndIf:
    stx.w   currentHdmaBuffer

    rts
}



// Commit the current HDMA buffer.
// The HDMA registers will be updated on the next VBlank.
//
// REQUIRES: 8 bit A, 16 bit Index
// DB access low-RAM
macro HdmaBuffer_Commmit() {
    assert8a()

    lda.b   #1
    sta.w   hdmaBufferVBlankFlag
}



// HDMA double buffer VBlank routine.
// Updates HDMA registers if `hdmaBufferVBlankFlag` is non-zero.
//
// REQUIRES: 8 bit A, 16 bit Index, DB = 0x80, DP = 0
// REQUIRES: in VBlank
//
// DB access registers
macro HdmaBuffer_VBlank() {
    lda.w   hdmaBufferVBlankFlag
    beq     EndIf{#}
        ldx.w   hdmaBufferTarget
        stx.w   DMAP0 + (HDMA_CHANNEL * 0x10)   // Also sets BBAD

        ldx.w   currentHdmaBuffer
        stx.w   A1T0 + (HDMA_CHANNEL * 0x10)

        lda.b   #hdmaBuffer0 >> 16
        sta.w   A1B7

        lda.b   #1 << HDMA_CHANNEL
        sta.w   HDMAEN

        stz.w   hdmaBufferVBlankFlag
EndIf{#}:
}



// DrawSymmetricalWindow
// =====================


// Draw a horizontally symmetrical window to the HDMA buffer
//
// NOTE: This function does not support windowless scanlines inside the window table data.
//
// NOTE: Uses `WMDATA`
//
// INPUT: centreX - centre X position (s16, zeropage temporary)
// INPUT: topY    - top Y position (s16, zeropage temporary)
// INPUT: X       - address of window table data (in WINDOW_TABLE_DATA_BANK)
//
//
// WINDOW TABLE DATA FORMAT:
//      count   u8          Number of scanlines
//                          (must not be 0)
//                          (should be <= DISPLAY_HEIGHT)
//
//      data    u8[count]   Window half-width for each scanline
//                          (window window is `2 * half_width + 1`)
//
// DP = 0
// DB access registers
a8()
i16()
function DrawSymmetricalWindow {
constant centreX            = zpTmp0
constant topY               = zpTmp1

// Number of scanlines to draw
// (u16, accessed with both 8 and 16 bit A)
constant _remainingScanlines        = zpTmp2    // must be u16

// Number of scanlines in the second HDMA repeat-mode entry (if any)
// (u8)
constant _secondHdmaEntryScanlines  = zpTmp3


// Window Table data.
// Accessed with `long,x` addressing mode
constant _TableOffset   = WINDOW_TABLE_DATA_BANK << 16
constant _Table__count  = _TableOffset
constant _Table__data   = _TableOffset + 1


    // Confirm this function will not overflow the HDMA buffer
    // (+8 for `TopYPositive`)
    // (`1 + 2 * HDMA_ENTRY_MAX_SCANLINES` for a single HDMA repeat-mode entry)
    // (+4 for `EndHdmaTable`)
    // (+16 to be extra safe)
    assert(8 + 2 * (1 + 2 * HDMA_ENTRY_MAX_SCANLINES) + 4 + 16 < HDMA_BUFFER_SIZE)


    phx

    // Set `WMDATA` address to the next HDMA buffer
    jsr     HdmaBuffer_NextBuffer
    assert(hdmaBuffer0 >> 16 == 0x7e)
    stx.w   WMADD
    stz.w   VMADD + 2

    plx


    ldy.b   topY
    beq     DrawBuffer
    bpl     TopYPositive
        // topY is negative

        rep     #$31
    a16()

        // Decrement number of scanlines to draw.
        //
        // _remainingScanlines = (u8)Table_count + (s16)topY
        // (topY is negative, equivalent to `A = Table_count - abs(topY)`)
        lda.l   _Table__count,x
        and.w   #0xff
        // carry clear
        adc.b   topY
        sta.b   _remainingScanlines

        // Branch if the window is vertically offscreen
        bmi     JumpToEndHdmaTable
        beq     JumpToEndHdmaTable


        // Increment table position.
        //
        // X = X - topY
        // (topY is negative, equivalent to `X = X + abs(topY)`)
        txa
        sec
        sbc.b   topY
        tax

        sep     #$20
    a8()
        lda.b   _remainingScanlines
        bra     DrawBuffer__A


    au()
    JumpToEndHdmaTable:
        sep     #$20
    a8()
        jmp     EndHdmaTable


    TopYPositive:
        // topY is > 0

        // Test if the window is vertically offscreen
        cpy.w   #DISPLAY_HEIGHT
        bcs     EndHdmaTable

        // Disable the window for `Y` scanlines using one or two HDMA non-repeat-mode entries.

        assert(DISPLAY_HEIGHT < 2 * HDMA_ENTRY_MAX_SCANLINES)
        assert(2 * HDMA_ENTRY_MAX_SCANLINES < 0xff)
        tya
        cmp.b   #HDMA_ENTRY_MAX_SCANLINES + 1
        bcc     +
            // Y > HDMA_ENTRY_MAX_SCANLINES

            // write `Y - HDMA_ENTRY_MAX_SCANLINES` to buffer (number of scanlines, non-repeat mode)
            // write `0xff` to buffer                         (left window position)
            // write `0`    to buffer                         (right window position)
            sec
            sbc.b   #HDMA_ENTRY_MAX_SCANLINES

            sta.w   WMDATA
            lda.b   #0xff
            sta.w   WMDATA
            stz.w   WMDATA

            lda.b   #HDMA_ENTRY_MAX_SCANLINES
        +

        // write `A` to buffer      (number of scanlines, non-repeat mode)
        // write `0xff` to buffer   (left window position)
        // write `0`    to buffer   (right window position)
        sta.w   WMDATA
        lda.b   #0xff
        sta.w   WMDATA
        stz.w   WMDATA


        // Calculate the number of scanlines to draw

        // A = DISPLAY_HEIGHT - Y
        // 
        lda.b   #DISPLAY_HEIGHT
        sec
        sbc.b   topY

        cmp.l   _Table__count,x
        bcc     DrawBuffer__A



DrawBuffer:
    lda.l   _Table__count,x
    beq     EndHdmaTable

DrawBuffer__A:
    // X = table address
    // A = number of scanlines to draw
    stz.b   _secondHdmaEntryScanlines

    cmp.b   #HDMA_ENTRY_MAX_SCANLINES
    bcc     +
        // carry set
        sbc.b   #HDMA_ENTRY_MAX_SCANLINES
        sta.b   _secondHdmaEntryScanlines

        lda.b   #HDMA_ENTRY_MAX_SCANLINES
    +

    ldy.b   centreX
    bmi     CentreXIsOffscreenLeft
    cpy.w   #DISPLAY_WIDTH
    bcs     CentreXIsOffscreenRight


    EntryLoop:
        // A = number of scanlines in the HDMA entry
        sta.b   _remainingScanlines

        // repeat mode, `A` scanlines
        ora.b   #0x80
        sta.w   WMDATA


        // Y = centreX
        // X = pre-calculated HDMA table address
        Loop:
            // left = centreX - _Table__data[x]
            // if left < 0:
            //      left = 0
            // write `left` to buffer
            tya
            sec
            sbc.l   _Table__data,x
            bcs     +
                lda.b   #0
            +
            sta.w   WMDATA

            // right = centreX + _Table__data[x]
            // if right > 255:
            //      right = 255
            // write `right` to buffer
            tya
            clc
            adc.l   _Table__data,x
            bcc     +
                lda.b   #0xff
            +
            sta.w   WMDATA

            inx

            dec.b   _remainingScanlines
            bne     Loop


        // Check if a second HDMA entry is required
        lda.b   _secondHdmaEntryScanlines
        beq     EndLoop

        stz.b   _secondHdmaEntryScanlines
        bra     EntryLoop
    EndLoop:


a8()
EndHdmaTable:
    // Disable HDMA window for 1 scanline (left = 0xff, right = 0)
    lda.b   #1
    sta.w   WMDATA
    lda.b   #0xff
    sta.w   WMDATA
    stz.w   WMDATA

    // End HDMA table byte
    stz.w   WMDATA


    HdmaBuffer_Commmit()


    rts



a8()
i16()
CentreXIsOffscreenLeft:
namespace CentreXIsOffscreenLeft {
    // Y = centreX
    // Y (centreX) is negative
    // A = number of scanlines to draw in the first HDMA entry
    // _secondHdmaEntryScanlines is set


    // Test if the window will never be horizontally onscreen.
    // If there is no early-exit, all the math can be calculated with an 8 bit Accumulator.
    assert(DISPLAY_WIDTH <= 0x100)
    cpy.w   #-DISPLAY_WIDTH
    bcc     EndHdmaTable


    EntryLoop:
        // A = number of scanlines in the HDMA entry
        sta.b   _remainingScanlines

        // repeat mode, `A` scanlines
        ora.b   #0x80
        sta.w   WMDATA


        // Y = centreX
        // X = pre-calculated HDMA table address
        Loop:
            // right = centreX + _Table__data[x]
            // if right > 0:
            //      write `0` to buffer
            //      write `right` to buffer
            // else:
            //      write `0xff` to buffer
            //      write `0` to buffer

            // Assumes high byte of Y is always 0xff
            tya
            clc
            adc.l   _Table__data,x
            bcc     +
                stz.w   WMDATA
                sta.w   WMDATA
                bra     ++
            +
                lda.b   #0xff
                sta.w   WMDATA
                stz.w   WMDATA
            +

            inx

            dec.b   _remainingScanlines
            bne     Loop


        // Check if a second HDMA entry is required
        lda.b   _secondHdmaEntryScanlines
        beq     EndHdmaTable

        stz.b   _secondHdmaEntryScanlines
        bra     EntryLoop
}



CentreXIsOffscreenRight:
namespace CentreXIsOffscreenRight {
    // Y = centreX
    // Y (centreX) is positive and >= DISPLAY_WIDTH
    // A = number of scanlines to draw in the first HDMA entry
    // _secondHdmaEntryScanlines is set


    // Test if the window will never be horizontally onscreen.
    // If there is no early-exit, all the math can be calculated with an 8 bit Accumulator.
    assert(DISPLAY_WIDTH == 0x100)
    cpy.w   #0x1ff
    bcs     EndHdmaTable


    EntryLoop:
        // A = number of scanlines in the HDMA entry
        sta.b   _remainingScanlines

        // repeat mode, `A` scanlines
        ora.b   #0x80
        sta.w   WMDATA


        // Y = centreX
        // X = pre-calculated HDMA table address
        Loop:
            // left = centreX - _Table__data[x]
            // if left < 0x100:
            //      write `left` to buffer
            //      write `255` to buffer
            // else:
            //      write `255` to buffer
            //      write `0` to buffer

            // Assumes high byte of centreX is always 0x01
            tya
            sec
            sbc.l   _Table__data,x
            bcs     +
                sta.w   WMDATA

                lda.b   #0xff
                sta.w   WMDATA
                bra     ++
            +
                lda.b   #0xff
                sta.w   WMDATA
                stz.w   WMDATA
            +

            inx

            dec.b   _remainingScanlines
            bne     Loop


        // Check if a second HDMA entry is required
        lda.b   _secondHdmaEntryScanlines
        beq     EndHdmaTable

        stz.b   _secondHdmaEntryScanlines
        bra     EntryLoop
}

}




// Main
// ====

// Window position
// (2x sint16)
allocate(xPos, lowram, 2)
allocate(yPos, lowram, 2)

// Window velocity
// (2x sint16)
allocate(xVelocity, lowram, 2)
allocate(yVelocity, lowram, 2)


constant _SHAPE_HALF_WIDTH  = 55
constant _SHAPE_HEIGHT      = 140
constant _PADDING           = 2


constant MIN_X_POS          = -_SHAPE_HALF_WIDTH - _PADDING
constant MAX_X_POS          = DISPLAY_WIDTH + _SHAPE_HALF_WIDTH + _PADDING
constant MIN_Y_POS          = -_SHAPE_HEIGHT - _PADDING
constant MAX_Y_POS          = DISPLAY_HEIGHT + _PADDING

constant START_X_POS        = 0
constant START_Y_POS        = -_SHAPE_HEIGHT / 2

constant START_X_VELOCITY   = 1
constant START_Y_VELOCITY   = 1



// VBlank routine
//
// REQUIRES: 8 bit A, 16 bit Index, DB = 0x80, DP = 0
macro VBlank() {
    assert8a()
    assert16i()

    HdmaBuffer_VBlank()
}

include "../vblank_interrupts.inc"



au()
iu()
code()
function Main {
    sep     #$20
    rep     #$10
a8()
i16()


    lda.b   #INIDISP.force | 0x0f
    sta.w   INIDISP


    // Set Backdrop colour to white
    stz.w   CGADD
    lda.b   #0xff
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

    // Clip colors to black outside the color window
    // Disable color math everywhere
    lda.b   #CGWSEL.clip.outside | CGWSEL.prevent.always
    sta.w   CGWSEL

    // No color math
    stz.w   CGADSUB


    // Setup HDMA double buffering (HDMA to WH0 & WH1)
    HdmaBuffer_Init(DMAP.direction.toPpu | DMAP.transfer.two, WH0)


    EnableVblankInterrupts()

    jsr     WaitFrame

    lda.b   #0x0f
    sta.w   INIDISP



    // Reset variables
    ldx.w   #START_X_POS
    stx.w   xPos

    ldy.w   #START_Y_POS
    sty.w   yPos

    ldx.w   #START_X_VELOCITY
    stx.w   xVelocity

    ldy.w   #START_Y_VELOCITY
    sty.w   yVelocity


    SpinLoop:
        jsr     WaitFrame


        rep     #$30
    a16()

        lda.w   xPos
        clc
        adc.w   xVelocity
        tax

        bpl     +
            cpx.w   #MIN_X_POS + 1
            bcs     ++
                ldx.w   #MIN_X_POS
                bra     InvertXVelocity
        +
            cpx.w   #MAX_X_POS
            bcc     +
                ldx.w   #MAX_X_POS
        InvertXVelocity:
                lda.w   #0
                sec
                sbc.w   xVelocity
                sta.w   xVelocity
        +
        stx.w   xPos


        lda.w   yPos
        clc
        adc.w   yVelocity
        tay

        bpl     +
            cpy.w   #MIN_Y_POS + 1
            bcs     ++
                ldy.w   #MIN_Y_POS
                bra     InvertYVelocity
        +
            cpy.w   #MAX_Y_POS
            bcc     +
                ldy.w   #MAX_Y_POS
        InvertYVelocity:
                lda.w   #0
                sec
                sbc.w   yVelocity
                sta.w   yVelocity
        +
        sty.w   yPos

        sep     #$20
    a8()


        stx.b   DrawSymmetricalWindow.centreX
        sty.b   DrawSymmetricalWindow.topY
        ldx.w   #Pawn
        jsr     DrawSymmetricalWindow


        bra     SpinLoop
}




// Rom Data
// ========

constant WINDOW_TABLE_DATA_BANK = pc() >> 16


Pawn:
    // first byte: number of scanlines
    db  140

    // remaining bytes: scanline half-width
    db    5,   8,  10,  11,  13,  14,  15,  16,  16,  17,  18,  18,  19,  19,  19,  20
    db   20,  20,  20,  20,  20,  20,  20,  19,  19,  19,  18,  18,  17,  16,  16,  15
    db   14,  13,  11,  10,   9,   9,  21,  25,  27,  28,  28,  27,  25,  21,  14,  14
    db   14,  14,  14,  14,  13,  13,  13,  13,  13,  13,  13,  12,  12,  12,  12,  12
    db   12,  12,  12,  12,  12,  12,  12,  12,  12,  12,  12,  13,  13,  13,  13,  13
    db   13,  13,  13,  14,  14,  14,  14,  14,  15,  15,  15,  15,  16,  16,  16,  16
    db   17,  17,  18,  18,  18,  19,  19,  19,  20,  20,  21,  21,  22,  22,  23,  24
    db   25,  26,  27,  29,  31,  34,  37,  40,  43,  45,  47,  49,  50,  51,  52,  53
    db   53,  54,  54,  55,  55,  55,  55,  55,  55,  55,  55,  54


finalizeMemory()

