// A precalculated non-symmetrical single-window HDMA demo.
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


define ROM_NAME = "PRECALCULATED WINDOW"
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
// DB access Low-RAM
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
// DB access Low-RAM
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



// TranslateSingleWindow
// =====================


namespace TranslateSingleWindow {


// WINDOW TABLE DATA FORMAT:
//      count       u8          Number of scanlines
//                              (must not be 0)
//                              (must be <= 2 * HDMA_ENTRY_MAX_SCANLINES)
//                              (should be <= DISPLAY_HEIGHT)
//
//      repeated `count` times:
//          left    u8          window left position
//          right   u8          window right position

// Window Table data.
// Accessed with `long,x` addressing mode
constant _TableOffset   = WINDOW_TABLE_DATA_BANK << 16
constant _Table__count  = _TableOffset
constant _Table__data   = _TableOffset + 1


constant MAX_HORIZONTAL_TRANSLATION = 0xff



// Temporary word variables
constant _yOffset                  = zpTmp0
constant _xOffset                  = zpTmp1
constant _secondHdmaEntryScanlines = zpTmp2
constant _remainingScanlines       = zpTmp3



// Confirm these functions will not overflow the HDMA buffer
// (+8 for `YOffsetPositive`)
// (`1 + 2 * HDMA_ENTRY_MAX_SCANLINES` for a single HDMA repeat-mode entry)
// (+4 for `__EndHdmaTable`)
// (+16 to be extra safe)
assert(8 + 2 * (1 + 2 * HDMA_ENTRY_MAX_SCANLINES) + 4 + 16 < HDMA_BUFFER_SIZE)




// Retrieve the next HDMA buffer and process the Y-Axis offset.
//
// INPUT: X         = ROM Table word address
// INPUT: _yOffset  = Y offset (sint16)
//
// RETURN: Carry: set if window is vertically onscreen
//
// RETURN: WMADD = HDMA buffer position
// RETURN: X = table address after the above-screen offscreen scanlines (if any)
// RETURN: A = number of scanlines in the first HDMA entry
// RETURN: _secondHdmaEntryScanlines = number of scanlines in the second HDMA entry (if any)
//
// The caller MUST branch to `__EndHdmaTable` if this function returns false.
//
// NOTE: Uses `WMDATA`
//
// DP = 0
// DB access registers
a8()
i16()
code()
function __GetNextBufferAndProcessYOffset {

    phx

    // Set `WMDATA` address to the next HDMA buffer
    jsr     HdmaBuffer_NextBuffer
    assert(hdmaBuffer0 >> 16 == 0x7e)
    stx.w   WMADD
    stz.w   VMADD + 2

    plx

    ldy.b   _yOffset
    beq     YOffsetZero
    bpl     YOffsetPositive
        // _yOffset is negative

        rep     #$31
    a16()
        // Decrement number of scanlines to draw.
        //
        // _remainingScanlines = (u8)Table_count + (s16)_yOffset
        // (yOffset is negative, equivalent to `A = Table_count - abs(_yOffset)`)
        lda.l   _Table__count,x
        and.w   #0xff
        // carry clear
        adc.b   _yOffset
        sta.b   _remainingScanlines

        // Test if the window is vertically offscreen
        bmi     ReturnFalse_A16
        beq     ReturnFalse_A16


        // Increment table position.
        //
        // X = _tableAddr - 2 * _yOffset 
        txa
        sec
        sbc.b   _yOffset
        sec
        sbc.b   _yOffset
        tax


        sep     #$20
    a8()
        lda.b   _remainingScanlines
        bra     EndIf


    YOffsetPositive:
        // yOffset is > 0

        // Test if the window is vertically offscreen
        cpy.w   #DISPLAY_HEIGHT
        bcs     ReturnFalse_A8

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
        //
        // A = DISPLAY_HEIGHT - Y
        lda.b   #DISPLAY_HEIGHT
        sec
        sbc.b   _yOffset

        // Branch if all scanlines are on vertically screen
        cmp.l   _Table__count,x
        bcs     YOffsetZero
        bra     EndIf


    YOffsetZero:
        // _yOffset is zero or all scanlines are vertically onscreen
        lda.l   _Table__count,x
        beq     ReturnFalse_A8

    EndIf:



    // A = number of scanlines to draw
    //
    // Calculate return A and _secondHdmaEntryScanlines values

    stz.b   _secondHdmaEntryScanlines

    cmp.b   #HDMA_ENTRY_MAX_SCANLINES
    bcc     +
        // carry set
        sbc.b   #HDMA_ENTRY_MAX_SCANLINES
        sta.b   _secondHdmaEntryScanlines

        lda.b   #HDMA_ENTRY_MAX_SCANLINES
    +

    // return true
    sec
    rts



au()
ReturnFalse_A16:
    sep     #$20
a8()
ReturnFalse_A8:
    clc
    rts
}



// Draw a precalculated HDMA window with a left x-offset.
//
// INPUT: X       - address of window table data (in WINDOW_TABLE_DATA_BANK)
// INPUT: A       - x-axis left offset (u8)
// INPUT: yOffset - y-axis offset (s16, zeropage temporary)
//
// NOTE: Uses `WMDATA`
//
// DP = 0
// DB access registers
a8()
i16()
code()
function DrawWindowLeftOffset {
constant yOffset = _yOffset

    // Negate A.
    //
    // Using a negative A allows me to store `_xOffset` in the `Y` register.
    // Only the lobyte of -A is required.  The code below assumes hibyte is always 0xff.
    eor.b   #0xff
    inc
InvertedA:
    sta.b   _xOffset

    jsr     __GetNextBufferAndProcessYOffset
    bcc     __EndHdmaTable

    ldy.w   _xOffset

    EntryLoop:
        // A = number of scanlines in the HDMA entry
        // X = pre-calculated HDMA table address
        // Y = _xOffset (only the lobyte is used, hibyte is unknown)

        sta.b   _remainingScanlines

        // repeat mode, `A` scanlines
        ora.b   #0x80
        sta.w   WMDATA

        Loop:
            //  right = _xOffset + _Table__data[x+1]
            //  if right < 0:
            //      write 0xff to buffer
            //      write 0    to buffer
            //  else:
            //      left = _xOffset + _Table__data[x]
            //      if left < 0:
            //          left = 0
            //      write `left`  to buffer
            //      write `right` to buffer
            tya
            clc
            adc.l   _Table__data + 1,x          // right
            bcs     WindowOnscreen
                // Window is offscreen.
                // Disable HDMA window (left = 0xff, right = 0)
                lda.b   #0xff
                sta.w   WMDATA
                stz.w   WMDATA

                bra     EndIf


            WindowOnscreen:
                xba                             // store right position in the high byte of A
                                                // slightly faster than using a zero-page variable
                tya
                clc
                adc.l   _Table__data + 0,x      // left
                bcs     +
                    lda.b   #0
                +

                sta.w   WMDATA
                xba
                sta.w   WMDATA
            EndIf:

            inx
            inx

            dec.b   _remainingScanlines
            bne     Loop


        // Check if a second HDMA entry is required
        lda.b   _secondHdmaEntryScanlines
        beq     __EndHdmaTable

        stz.b   _secondHdmaEntryScanlines
        bra     EntryLoop

Fallthrough:
}



// Finish the HDMA window table and commit the HDMA buffer.
//
// INPUT: WMADD = HDMA buffer position
//
// NOTE: Uses `WMDATA`
//
// DB access registers
a8()
i16()
code()
function __EndHdmaTable {
    assert(pc() == DrawWindowLeftOffset.Fallthrough)

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
}



// Draw a precalculated HDMA window with a right x-offset.
//
// INPUT: X       - address of window table data (in WINDOW_TABLE_DATA_BANK)
// INPUT: A       - x-axis left offset (u8)
// INPUT: yOffset - y-axis offset (s16, zeropage temporary)
//
// NOTE: Uses `WMDATA`
//
// DP = 0
// DB access registers
a8()
i16()
code()
function DrawWindowRightOffset {
constant yOffset = _yOffset


    sta.b   _xOffset

    jsr     __GetNextBufferAndProcessYOffset
    bcc     __EndHdmaTable

    ldy.w   _xOffset

    EntryLoop:
        // A = number of scanlines in the HDMA entry
        // X = pre-calculated HDMA table address
        // Y = _xOffset (only the lobyte is used, hibyte is unknown)

        sta.b   _remainingScanlines

        // repeat mode, `A` scanlines
        ora.b   #0x80
        sta.w   WMDATA

        Loop:
            //  left = _xOffset + _Table__data[x]
            //  if left > 255:
            //      write 0xff to buffer
            //      write 0    to buffer
            //  else:
            //      write `left`  to buffer
            //
            //      right = _xOffset + _Table__data[x+1]
            //      if right > 255:
            //          right = 255
            //      write `right` to buffer
            tya
            clc
            adc.l   _Table__data + 0,x          // left
            bcc     WindowOnscreen
                // Window is offscreen.
                // Disable HDMA window (left = 0xff, right = 0)
                lda.b   #0xff
                sta.w   WMDATA
                stz.w   WMDATA

                bra     EndIf


            WindowOnscreen:
                sta.w   WMDATA

                tya
                clc
                adc.l   _Table__data + 1,x      // right
                bcc     +
                    lda.b   #0xff
                +
                sta.w   WMDATA
            EndIf:

            inx
            inx

            dec.b   _remainingScanlines
            bne     Loop


        // Check if a second HDMA entry is required
        lda.b   _secondHdmaEntryScanlines
        beq     __EndHdmaTable

        stz.b   _secondHdmaEntryScanlines
        bra     EntryLoop

    bra     __EndHdmaTable
}



// Draw a precalculated HDMA window at a given offset.
//
// The window will not be drawn is `xOffset < -MAX_HORIZONTAL_TRANSLATION`
// or `xOffset > MAX_HORIZONTAL_TRANSLATION`.
//
// INPUT: X       - address of window table data (in WINDOW_TABLE_DATA_BANK)
// INPUT: xOffset - x-axis offset (s16, zeropage temporary)
// INPUT: yOffset - y-axis offset (s16, zeropage temporary)
//
// NOTE: Uses `WMDATA`
//
// DB access registers
a8()
i16()
code()
function DrawWindow {
constant xOffset = _xOffset
constant yOffset = _yOffset

    ldy.b   _xOffset
    bmi     XOffsetNegative
        // Y (_xOffset) is positive
        cpy.w   #MAX_HORIZONTAL_TRANSLATION + 1
        bcs     WindowOffscreen
        tya
        bra     DrawWindowRightOffset


    XOffsetNegative:
        // Y (_xOffset) is negative
        cpy.w   #-MAX_HORIZONTAL_TRANSLATION
        bcc     WindowOffscreen
        tya
        jmp     DrawWindowLeftOffset.InvertedA


WindowOffscreen:
    // Set `WMDATA` address to the next HDMA buffer
    jsr     HdmaBuffer_NextBuffer
    assert(hdmaBuffer0 >> 16 == 0x7e)
    stx.w   WMADD
    stz.w   VMADD + 2

    bra     __EndHdmaTable
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


constant _SHAPE_WIDTH       = 49
constant _SHAPE_HEIGHT      = 140
constant _PADDING           = 2


constant MIN_X_POS          = -128 - _SHAPE_WIDTH
constant MAX_X_POS          = +128 + _SHAPE_WIDTH
constant MIN_Y_POS          = -_SHAPE_HEIGHT - _PADDING
constant MAX_Y_POS          = DISPLAY_HEIGHT + _PADDING

constant START_X_POS        = 0
constant START_Y_POS        = 0

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


        stx.b   TranslateSingleWindow.DrawWindow.xOffset
        sty.b   TranslateSingleWindow.DrawWindow.yOffset
        ldx.w   #ExclamationMark
        jsr     TranslateSingleWindow.DrawWindow


        bra     SpinLoop
}




// Rom Data
// ========

constant WINDOW_TABLE_DATA_BANK = pc() >> 16


ExclamationMark:
    // first byte: number of scanlines
    db  140

    // remaining bytes: left and right value
    db  0x85, 0x8c, 0x83, 0x8e, 0x81, 0x90, 0x80, 0x92, 0x7f, 0x93, 0x7e, 0x94, 0x7d, 0x94, 0x7c, 0x95
    db  0x7c, 0x95, 0x7b, 0x96, 0x7b, 0x96, 0x7b, 0x97, 0x7a, 0x97, 0x7a, 0x97, 0x7a, 0x97, 0x7a, 0x97
    db  0x7a, 0x97, 0x7a, 0x97, 0x7a, 0x97, 0x7a, 0x96, 0x7a, 0x96, 0x7a, 0x96, 0x7a, 0x95, 0x7a, 0x95
    db  0x7a, 0x95, 0x7a, 0x94, 0x7a, 0x94, 0x7a, 0x94, 0x7a, 0x93, 0x7a, 0x93, 0x7a, 0x93, 0x7a, 0x92
    db  0x7a, 0x92, 0x7a, 0x92, 0x7a, 0x91, 0x7a, 0x91, 0x7a, 0x91, 0x7a, 0x90, 0x7a, 0x90, 0x79, 0x90
    db  0x79, 0x8f, 0x79, 0x8f, 0x79, 0x8f, 0x79, 0x8e, 0x79, 0x8e, 0x79, 0x8e, 0x79, 0x8d, 0x79, 0x8d
    db  0x79, 0x8d, 0x79, 0x8c, 0x79, 0x8c, 0x79, 0x8c, 0x79, 0x8b, 0x79, 0x8b, 0x79, 0x8b, 0x79, 0x8b
    db  0x79, 0x8a, 0x79, 0x8a, 0x79, 0x8a, 0x79, 0x89, 0x79, 0x89, 0x79, 0x89, 0x79, 0x88, 0x79, 0x88
    db  0x79, 0x88, 0x79, 0x87, 0x79, 0x87, 0x79, 0x87, 0x79, 0x86, 0x79, 0x86, 0x79, 0x86, 0x79, 0x85
    db  0x79, 0x85, 0x78, 0x85, 0x78, 0x84, 0x78, 0x84, 0x78, 0x84, 0x78, 0x83, 0x78, 0x83, 0x78, 0x83
    db  0x78, 0x82, 0x78, 0x82, 0x78, 0x82, 0x78, 0x81, 0x78, 0x81, 0x78, 0x81, 0x78, 0x80, 0x78, 0x80
    db  0x78, 0x80, 0x78, 0x7f, 0x78, 0x7f, 0x78, 0x7f, 0x78, 0x7e, 0x79, 0x7e, 0xff, 0x00, 0xff, 0x00
    db  0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00
    db  0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0x72, 0x79, 0x6f, 0x7b
    db  0x6e, 0x7d, 0x6c, 0x7e, 0x6b, 0x7f, 0x6a, 0x80, 0x6a, 0x81, 0x69, 0x82, 0x69, 0x82, 0x68, 0x83
    db  0x68, 0x83, 0x67, 0x83, 0x67, 0x83, 0x67, 0x84, 0x67, 0x84, 0x67, 0x84, 0x67, 0x84, 0x67, 0x84
    db  0x67, 0x83, 0x68, 0x83, 0x68, 0x83, 0x69, 0x82, 0x69, 0x82, 0x6a, 0x81, 0x6a, 0x80, 0x6b, 0x7f
    db  0x6c, 0x7e, 0x6e, 0x7d, 0x70, 0x7b, 0x72, 0x79


finalizeMemory()

