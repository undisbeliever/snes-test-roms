// textbuffer.inc
// ==============
//
// A simple split-buffer text buffer for printing monospace text and hexadecimal numbers.
//
// Copyright (c) 2022, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


namespace TextBuffer {


// The bank to store the font and the string literals.
if !{defined TextBuffer.STRING_BLOCK} {
    define STRING_BLOCK = rodata0
}


constant BUFFER_WIDTH = 32
constant BUFFER_HEIGHT = 32
constant N_BUFFER_CELLS = BUFFER_WIDTH * BUFFER_HEIGHT



if !{defined CUSTOM_TEXTBUFFER_MARGINS} {
    constant MARGIN_LEFT    = 2
    constant MARGIN_RIGHT   = 2

    constant MARGIN_TOP     = 1
    constant N_TEXT_ROWS    = 26
}

assert(MARGIN_LEFT >= 0)
assert(MARGIN_RIGHT >= 0)
assert(MARGIN_TOP >= 0)
assert(N_TEXT_ROWS >= 0)

constant N_TEXT_COLUMNS = BUFFER_WIDTH - MARGIN_LEFT - MARGIN_RIGHT

constant STARTING_CURSOR_INDEX = MARGIN_TOP * BUFFER_WIDTH + MARGIN_LEFT

assert(MARGIN_LEFT + N_TEXT_COLUMNS <= BUFFER_WIDTH)
assert(MARGIN_TOP  + N_TEXT_ROWS    <= BUFFER_HEIGHT)



// Set default attribute to high priority, palette 0
constant DEFAULT_ATTR = TilemapH.order



// If zero, `charBuffer` will be transferred to VRAM on the next VBlank.
//
// (byte flag)
allocate(charBufferClean, lowram, 1)


// If zero, `attrBuffer` will be transferred to VRAM on the next VBlank.
//
// (byte flag)
allocate(attrBufferClean, lowram, 1)


// Current cursor position
//
// (word index into `charBuffer`)
allocate(cursorIndex, lowram, 2)

// Cursor position at the end of the current line
//
// (word index into `charBuffer`)
allocate(endOfLineIndex, lowram, 2)




// Character buffer
//
// The low-byte of the Tilemap entries.
//
// (u8[N_BUFFER_CELLS])
allocate(charBuffer, wram7e, N_BUFFER_CELLS)
constant charBuffer.size = N_BUFFER_CELLS


// Character attribute buffer
//
// The high-byte of the Tilemap entries, handles palette and order.
//
// (u8[N_BUFFER_CELLS])
allocate(attrBuffer, wram7e, N_BUFFER_CELLS)
constant attrBuffer.size = N_BUFFER_CELLS




// Font and Character Mapping
// ==========================

// 1-bpp font tiles
rodata(rodata0)
    insert Font_1bpp, "../gen/textbuffer/font-1bpp-tiles.tiles"

    include "../resources/textbuffer/font-1bpp-map.inc"



// Initialise the TextBuffer subsystem and transfer font/buffers to VRAM
//
// NOTE: This function will not transfer a palette to CGRAM.
//
// REQUIRES: In force-blank
//
// DB = registers
a8()
i16()
code()
function InitAndTransferToVram {
    jsr     ClearCharBufferAndResetCursor
    jsr     ClearAttrBuffer

    jmp     TransferFontAndBuffersToVram
}



// Clear the character buffer and reset the cursor position
//
// DB = Low-RAM
a8()
i16()
code()
function ClearCharBufferAndResetCursor {
    ldx.w   #STARTING_CURSOR_INDEX
    stx.w   cursorIndex

    ldx.w   #STARTING_CURSOR_INDEX + N_TEXT_COLUMNS
    stx.w   endOfLineIndex

    rep     #$30
a16()

    assert(charBuffer.size % 2 == 0)
    ldx.w   #charBuffer.size - 2
    lda.w   #0
    Loop:
        sta.l   charBuffer,x
        dex
        dex
        bpl     Loop

    sep     #$20
a8()

    // Transfer `charBuffer` to VRAM on the next VBlank
    stz.w   charBufferClean

    rts
}



// Clear the attribute buffer
//
// DB = Low-RAM
a8()
i16()
code()
function ClearAttrBuffer {

    rep     #$30
a16()

    assert(attrBuffer.size % 2 == 0)
    ldx.w   #attrBuffer.size - 2
    lda.w   #DEFAULT_ATTR | (DEFAULT_ATTR << 8)
    Loop:
        sta.l   attrBuffer,x
        dex
        dex
        bpl     Loop

    sep     #$20
a8()

    // Transfer `attrBuffer` to VRAM on the next VBlank
    stz.w   attrBufferClean

    rts
}



// Transfer the font and the buffers to VRAM
//
// REQUIRES: force-blank
//
// DB = registers
a8()
i16()
code()
function TransferFontAndBuffersToVram {

    // Use VMAIN to convert 1bpp font to 2bpp tile data
    ldx.w   #VRAM_TEXTBUFFER_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVramL(Font_1bpp)

    ldx.w   #VRAM_TEXTBUFFER_TILES_WADDR
    ldy.w   #Font_1bpp.size
    jsr     Dma.ForceBlank.ClearVramH


    // Transfer buffers to VRAM
    ldx.w   #VRAM_TEXTBUFFER_MAP_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVramL(charBuffer)

    ldx.w   #VRAM_TEXTBUFFER_MAP_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVramH(attrBuffer)


    // Mark buffers are unchanged
    lda.b   #1
    sta.w   charBufferClean
    sta.w   attrBufferClean

    rts
}



// TextBuffer VBlank routine.
//
// Transfers buffers to VRAM if they have changed.
//
// In: V-Blank
//
// DB = 0x80
macro VBlank() {
    assert8a()
    assert16i()

    // Transfer `charBuffer` to VRAM if `charBufferClean` is zero
    lda.w   TextBuffer.charBufferClean
    bne     SkipCharBuffer
        // Transfer `charBuffer` to the low-bytes of VRAM at word-address `VRAM_TEXTBUFFER_MAP_WADDR`.

        ldx.w   #VRAM_TEXTBUFFER_MAP_WADDR
        stx.w   VMADD

        assert(VMAIN.incrementMode.low | VMAIN.increment.by1 == 0)
        stz.w   VMAIN

        ldx.w   #DMAP.direction.toPpu | DMAP.transfer.one | (VMDATAL << 8)
        stx.w   DMAP0                       // also set BBAD0

        ldx.w   #TextBuffer.charBuffer
        stx.w   A1T0
        lda.b   #TextBuffer.charBuffer >> 16
        sta.w   A1B0

        ldx.w   #TextBuffer.charBuffer.size
        stx.w   DAS0

        lda.b   #MDMAEN.dma0
        sta.w   MDMAEN

        // A is non-zero
        sta.w   TextBuffer.charBufferClean
SkipCharBuffer:


    // Transfer `attrBuffer` to VRAM if `attrBufferClean` is zero
    lda.w   TextBuffer.attrBufferClean
    bne     SkipAttrBuffer
        // Transfer `attrBuffer` to the high-bytes of VRAM at word-address `VRAM_TEXTBUFFER_MAP_WADDR`.

        ldx.w   #VRAM_TEXTBUFFER_MAP_WADDR
        stx.w   VMADD

        lda.b   #VMAIN.incrementMode.high | VMAIN.increment.by1
        sta.w   VMAIN

        ldx.w   #DMAP.direction.toPpu | DMAP.transfer.one | (VMDATAH << 8)
        stx.w   DMAP0                       // also set BBAD0

        ldx.w   #TextBuffer.attrBuffer
        stx.w   A1T0
        lda.b   #TextBuffer.attrBuffer >> 16
        sta.w   A1B0

        ldx.w   #TextBuffer.attrBuffer.size
        stx.w   DAS0

        lda.b   #MDMAEN.dma0
        sta.w   MDMAEN

        // A is non-zero
        sta.w   TextBuffer.attrBufferClean
SkipAttrBuffer:
}



// Set the cursor to a fixed location
//
// DB = low-RAM
macro SetCursor(evaluate x, evaluate y) {
    assert16i()

    assert({x} >= 0 && {x} < TextBuffer.N_TEXT_COLUMNS)
    assert({y} >= 0 && {y} < TextBuffer.N_TEXT_ROWS)

    ldx.w   #({y} + TextBuffer.MARGIN_TOP) * TextBuffer.BUFFER_WIDTH + ({x} + TextBuffer.MARGIN_LEFT)
    stx.w   TextBuffer.cursorIndex

    ldx.w   #({y} + TextBuffer.MARGIN_TOP) * TextBuffer.BUFFER_WIDTH + (TextBuffer.MARGIN_LEFT + TextBuffer.N_TEXT_COLUMNS)
    stx.w   TextBuffer.endOfLineIndex
}



// Move the cursor to a given location
//
// INPUT: X = x-position (u8)
// INPUT: Y = y-position (u8)
//
// DB = low-RAM
a8()
iu()
code()
function SetCursor {
constant _tmpWord = zpTmp0

assertPowerOfTwo(BUFFER_WIDTH)
assertPowerOfTwo(BUFFER_HEIGHT)
constant CURSOR_INDEX_ROW_MASK = (BUFFER_HEIGHT - 1) * BUFFER_WIDTH

    php

    sep     #$10
i8()

    // clear high byte of A
    tdc

    txa
    cmp.b   #N_TEXT_COLUMNS
    bcc     +
        lda.b   #0
        clc
    +
    // carry clear
    adc.b   #MARGIN_LEFT

    sta.b   _tmpWord
    stz.b   _tmpWord + 1


    tya
    cmp.b   #N_TEXT_ROWS
    bcc     +
        lda.b   #0
        clc
    +
    // carry clear
    adc.b   #MARGIN_TOP

    rep     #$30
a16()
    // A.h clear (from `tdc` above)
    assert(BUFFER_WIDTH == 1 << 5)
    asl
    asl
    asl
    asl
    asl
    ora.b   _tmpWord

    sta.w   cursorIndex

    and.w   #CURSOR_INDEX_ROW_MASK
    ora.w   #MARGIN_LEFT + N_TEXT_COLUMNS
    sta.w   endOfLineIndex


    plp
    rts
}



// Advance the cursor to the next line and clear the new line.
//
// DB = low-RAM
a8()
i16()
code()
function NewLine {

assertPowerOfTwo(BUFFER_WIDTH)
assertPowerOfTwo(BUFFER_HEIGHT)
constant CURSOR_INDEX_ROW_MASK = (BUFFER_HEIGHT - 1) * BUFFER_WIDTH

constant LAST_ROW = MARGIN_TOP + N_TEXT_ROWS - 1
assert(LAST_ROW * BUFFER_WIDTH + MARGIN_LEFT + N_TEXT_COLUMNS <= N_BUFFER_CELLS)

// `NewLine` does not work correctly if there is no margin on the right.
assert(MARGIN_RIGHT >= 1)


    rep     #$20
a16()
    lda.w   cursorIndex
    and.w   #CURSOR_INDEX_ROW_MASK
    clc
    adc.w   #BUFFER_WIDTH + MARGIN_LEFT

    cmp.w   #(LAST_ROW + 1) * BUFFER_WIDTH
    bcc     +
        lda.w   #STARTING_CURSOR_INDEX
    +
    sta.w   cursorIndex
    tax

    // Clear the line and advance X to `endOfLineIndex`
    assert(N_TEXT_COLUMNS % 2 == 0)
    ldy.w   #N_TEXT_COLUMNS / 2
    lda.w   #Font.SPACE | (Font.SPACE << 8)
    Loop:
        sta.l   charBuffer,x
        inx
        inx
        dey
        bne     Loop

    // X = cursorIndex + N_TEXT_COLUMNS
    stx.w   endOfLineIndex

    sep     #$20
a8()
    rts
}



// Print a string from a label
//
// DB = low-RAM
macro PrintString(label) {
    assert8a()
    assert16i()

    ldx.w   #{label}
    lda.b   #({label}) >> 16
    jsr     TextBuffer.PrintString
}



// Print a string literal
//
// DB = low-RAM
inline PrintStringLiteral(s) {
    assert8a()
    assert16i()

    pushBlock()
        rodata({TextBuffer.STRING_BLOCK})
    String{#}:
        db  {s}, 0
    popBlock()

    ldx.w   #String{#}
    lda.b   #String{#} >> 16
    jsr     TextBuffer.PrintString
}



// Print a string
//
// INPUT: A:X - far address of string
//
// NOTE: Uses `zpTmpPtr`
//
// DB = low-RAM
a8()
i16()
code()
function PrintString {
    stx.b   zpTmpPtr
    sta.b   zpTmpPtr + 2


    lda     [zpTmpPtr]
    beq     EmptyString

    ldx.w   cursorIndex

    ldy.w   #0
    Loop:
        assert(Font.NEW_LINE + 1 == Font.FIRST_INVALID_CHARACTER)
        cmp.b   #Font.NEW_LINE
        beq     NewLineCharacter
        bcc     +
            lda.b   #' '
        +

        sta.l   charBuffer,x
        inx

        // Test if the cursor is at the end of the line
        cpx.w   endOfLineIndex
        bcc     +
        NewLineCharacter:
            // Confirm this works with very long strings::
            phy
                jsr     NewLine
                ldx.w   cursorIndex
            ply
        +

        iny
        lda     [zpTmpPtr],y
        bne     Loop


    stx.w   cursorIndex

    // Transfer `charBuffer` to VRAM on the next VBlank
    stz.w   charBufferClean

EmptyString:
    rts
}



// Print an 8-bit hexadecimal string, followed by a space or new line
//
// INPUT: A - 8 bit value
//
// DB = low-RAM
a8()
i16()
code()
function PrintHexSpace_8A {
constant _tmp = zpTmp0

    assert(Font.ZERO + 10 == Font.CAPITAL_A)

    ldx.w   cursorIndex
    inx
    cpx.w   endOfLineIndex
    bcc     +
        sta.b   _tmp
        jsr     NewLine
        ldx.w   cursorIndex
        inx
        lda.b   _tmp
    +
    inx

AfterX:
    tay

    lsr
    lsr
    lsr
    lsr
    clc
    adc.b   #Font.ZERO
    sta.l   charBuffer - 2,x


    tya
    and.b   #0x0f
    clc
    adc.b   #Font.ZERO
    sta.l   charBuffer - 1,x


    // Print a space or new line
    inx
    cpx.w   endOfLineIndex
    bcc     +
        jsr     NewLine
        bra     ++
    +
        stx.w   cursorIndex

        lda.b   #Font.SPACE
        sta.l   charBuffer - 1,x
    +

    // Transfer `charBuffer` to VRAM on the next VBlank
    stz.w   charBufferClean

    rts
}



// Print a 16-bit hexadecimal string, followed by a space or new line
//
// INPUT: Y - 16 bit value
//
// DB = low-RAM
a8()
i16()
code()
function PrintHexSpace_16Y {
    sty.b   zpTmp0

FallThrough:
}



// Print a 16-bit hexadecimal string, followed by a space or new line
//
// INPUT: Y - 16 bit value
//
// DB = low-RAM
function PrintHexSpace_16_zpTmp0 {
    assert(PrintHexSpace_16Y.FallThrough == pc())

    assert(Font.ZERO + 10 == Font.CAPITAL_A)

    ldx.w   cursorIndex
    inx
    inx
    inx
    cpx.w   endOfLineIndex
    bcc     +
        jsr     NewLine
        ldx.w   cursorIndex
        inx
        inx
        inx
    +
    inx


    lda.b   zpTmp0 + 1
    lsr
    lsr
    lsr
    lsr
    clc
    adc.b   #Font.ZERO
    sta.l   charBuffer - 4,x


    lda.b   zpTmp0 + 1
    and.b   #0x0f
    clc
    adc.b   #Font.ZERO
    sta.l   charBuffer - 3,x


    lda.b   zpTmp0
    jmp     PrintHexSpace_8A.AfterX
}

}

