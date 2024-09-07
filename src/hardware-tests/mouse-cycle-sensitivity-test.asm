// Nintendo Mouse Cycle Sensitivity Test.
//
// Used to test:
//   * The initial mouse sensitivity value.
//     (Answer: It has an inconsistent starting value.)
//   * Does the power-on uninitialised mouse sensitivity value increment by one
//     after the first cycle-sensitivity command.
//     (Answer: Yes, it increases by 1 for my Nintendo mouse.)
//   * If I can increment the sensitivity more than once per latch
//     (Answer: yes)
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
define ROM_NAME = "MOUSE SENSITIVITY"
define VERSION = 1

architecture wdc65816-strict

include "../common.inc"


createCodeBlock(code,       0x808000, 0x80ffaf)
createCodeBlock(rodata0,    0x818000, 0x81ffff)

createRamBlock(zeropage,        0x00,     0xff)
createRamBlock(lowram,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)
createRamBlock(wram7e,      0x7e2000, 0xfeffff)


constant VRAM_BG1_MAP_WADDR   = 0x0000
constant VRAM_BG1_TILES_WADDR = 0x1000

constant VRAM_TEXTBUFFER_MAP_WADDR   = VRAM_BG1_MAP_WADDR
constant VRAM_TEXTBUFFER_TILES_WADDR = VRAM_BG1_TILES_WADDR



include "../reset_handler.inc"
include "../break_handler.inc"
include "../dma_forceblank.inc"
include "../textbuffer.inc"


// zero-page temporary word variables
allocate(zpTmp0, zeropage, 2)
allocate(zpTmp1, zeropage, 2)
allocate(zpTmp2, zeropage, 2)
allocate(zpTmp3, zeropage, 2)

// zero-page temporary far pointer
allocate(zpTmpPtr, zeropage, 3)


allocate(mouseData, zeropage, 1)

allocate(mouseConnected, zeropage, 2)

constant TEST_DATA_SIZE = 9
allocate(mouseTestData, zeropage, TEST_DATA_SIZE)


// VBlank routine
//
// REQUIRES: 8 bit A, 16 bit Index, DB = 0x80, DP = 0
macro VBlank() {
    assert8a()
    assert16i()

    TextBuffer.VBlank()
}

include "../vblank_interrupts.inc"


// Manually read the 2nd byte of the mouse data
//
// OUT: mouseData[port] = 2nd mouse data byte
//
// DB = registers
macro ReadMouse(evaluate port) {
    assert8a()
    assert16i()
    assert({port} == 0 || {port} == 1)

    stz.b   mouseData

    // latch joypad ports
    lda.b   #JOYSER0.latch
    sta.w   JOYSER0
    stz.w   JOYSER0


    variable _i = 0;
    while _i < 8 {
        lda.w   JOYSER0 + {port}

        _i = _i + 1
    }

    variable _i = 0;
    while _i < 8 {
        lda.w   JOYSER0 + {port}
        lsr
        rol.b   mouseData

        _i = _i + 1
    }
}



// Cycle the mouse sensitivity `nSpeedCycles`, then read the mouse sensitivity bits
//
// OUT: A = sensitivity
// DB = registers
macro CycleAndReadSensitivity(evaluate port, evaluate nSpeedCycles) {
    assert8a()
    assert16i()
    assert({port} == 0 || {port} == 1)


    // latch ports and cycle mouse speed
    lda.b   #JOYSER0.latch
    sta.w   JOYSER0

    assert({nSpeedCycles} <= 10)
    variable _i = {nSpeedCycles}
    while _i > 0 {
        lda.w   JOYSER0 + {port}
        _i = _i - 1
    }

    stz.w   JOYSER0


    // Skip unneeded bits
    variable _i = 0;
    while _i < 10 {
        lda.w   JOYSER0 + {port}
        nop                         // Required for good reads
        nop                         // Required for good reads

        _i = _i + 1
    }

    // Read sensitivity bits
    lda.w   JOYSER0 + {port}
    nop                         // Required for good reads
    lsr
    lda.w   JOYSER0 + {port}
    and.b   #1
    bcc     +
        ora.b   #2
    +
}


macro Test(evaluate port) {
    assert({port} == 0 || {port} == 1)

    ReadMouse({port})

    lda.b   mouseData
    and.b   #JOYL.type.mask
    cmp.b   #JOYL.type.mouse
    beq     +
        // not a mouse
        stz.b   mouseConnected + {port}
        jmp     Return{#}
    +

    // Mouse connected
    // Check if mouse was not connected on the previous read
    lda.b   mouseConnected + {port}
    beq     +
        jmp     Return{#}
    +

    // Mouse connected

    lda.b   #1
    sta.b   mouseConnected + {port}


Mouse_Connected_{port}:
    CycleAndReadSensitivity({port}, 1)
    sta.b   mouseTestData + 0

    CycleAndReadSensitivity({port}, 1)
    sta.b   mouseTestData + 1

    CycleAndReadSensitivity({port}, 1)
    sta.b   mouseTestData + 2

    CycleAndReadSensitivity({port}, 1)
    sta.b   mouseTestData + 3


    CycleAndReadSensitivity({port}, 2)
    sta.b   mouseTestData + 4

    CycleAndReadSensitivity({port}, 2)
    sta.b   mouseTestData + 5

    CycleAndReadSensitivity({port}, 2)
    sta.b   mouseTestData + 6

    CycleAndReadSensitivity({port}, 3)
    sta.b   mouseTestData + 7

    CycleAndReadSensitivity({port}, 8)
    sta.b   mouseTestData + 8

    assert(TEST_DATA_SIZE == 9)


    // Print test data

    TextBuffer.PrintStringLiteral("P")

    lda.b   #{port} + 1
    jsr     TextBuffer.PrintOneHexDigitSpace_8A

    TextBuffer.PrintStringLiteral(" ")

    // Print original sensitivity bits
    lda.b   mouseData
    lsr
    lsr
    lsr
    lsr
    and.b   #3
    jsr     TextBuffer.PrintOneHexDigitSpace_8A

    TextBuffer.PrintStringLiteral(" ")

    ldx.w   #0
    -
        phx

        cpx.w   #4
        bne     +
            phx
            TextBuffer.PrintStringLiteral(" ")
            plx
        +

        lda.b   mouseTestData,x
        jsr     TextBuffer.PrintOneHexDigitSpace_8A

        plx
        inx
        cpx.w   #TEST_DATA_SIZE
        bcc     -


    ldx.w   TextBuffer.cursorIndex
    cpx.w   #(TextBuffer.MARGIN_TOP + TextBuffer.N_TEXT_ROWS - 1) * TextBuffer.BUFFER_WIDTH - 1
    bcc     +
        TextBuffer.SetCursor(0, TEST_DATA_YPOS - 1)
    +
    jsr     TextBuffer.NewLine

Return{#}:
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

    lda.b   #BGMODE.mode0
    sta.w   BGMODE

    lda.b   #TM.bg1
    sta.w   TM

    lda.b   #(VRAM_BG1_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG1SC

    lda.b   #(VRAM_BG1_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg1.shift
    sta.w   BG12NBA

    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Palette)

    jsr     TextBuffer.InitAndTransferToVram


    TextBuffer.SetCursor(0, 1)
    TextBuffer.PrintStringLiteral("Nintendo Mouse\nCycle Sensitivity Test v{VERSION}")

    TextBuffer.SetCursor(0, 4)
    TextBuffer.PrintStringLiteral("Plug + unplug mouse\n\n")

    constant TEST_DATA_YPOS = 7

    EnableVblankInterrupts_NoAutoJoypad()

    jsr     WaitFrame

    lda.b   #0x0f
    sta.w   INIDISP

    MainLoop:
        jsr     WaitFrame

        Test(0)
        Test(1)

        jmp     MainLoop
}


namespace Resources {

Palette:
    dw  ToPalette(0, 0, 0)
    dw  ToPalette(31, 31, 31)
constant Palette.size = pc() - Palette
}

finalizeMemory()

