// break_handler.inc
// =================
//
// A Break Interrupt handler that prints the CPU registers on screen.
//
//
// Copyright (c) 2022-2023, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


// This file might be included in tests that do not use `_common/memory.inc`
if {defined __MEMORY__.romBlocks.code} {
    code()
}
namespace BreakHandler {
    assert((pc() >> 16) | 0x80 == 0x80)

    constant VRAM_BG1_MAP_WADDR = 0x0000
    constant VRAM_BG1_TILES_WADDR = 0x1000

    // Temporary variable used to calculate the address of registers in the stack
    constant zpStack = 00


    if {defined __MEMORY__.romBlocks.rodata0} {
        rodata(rodata0)
            insert Font_1bpp, "../gen/textbuffer/font-1bpp-tiles.tiles"
        code()
    } else {
        // no rodata0 bank
        // Store the font in bank 0
        insert Font_1bpp, "../gen/textbuffer/font-1bpp-tiles.tiles"
    }
    include "../resources/textbuffer/font-1bpp-map.inc"


    inline _string(evaluate x, evaluate y, string) {
        assert({x} != 0)

        dw  BreakHandler.VRAM_BG1_MAP_WADDR + {x} + 32 * {y}
        db  {string}, 0
    }
    CrashString:
        _string(6, 4, "CRASHED!")

    inline _line(evaluate x, evaluate y, string, evaluate stack_offset, evaluate size) {
        _string({x}, {y}, {string})
        db  {stack_offset}, {size}
    }
    BreakDataTable:
        _line(6,  7, "PC", 16, 3)
        _line(7,  9, "P",  13, 1)
        _line(7, 11, "e",   3, 1)
        _line(6, 13, "DB",  6, 1)
        _line(6, 15, "SP",  2, 2)
        _line(6, 17, "DP",  5, 2)
        _line(7, 19, "A",  12, 2)
        _line(7, 21, "X",  10, 2)
        _line(7, 23, "Y",   8, 2)
    EmptyByte:
        db  0


    // Break Interrupt Service Routine
    //
    // This interrupt is also used for any unused interrupts.
    //
    // All registers unknown
    // emulation bit unknown
    function ISR {
        // This ISR may be invoked in emulation mode, switch to native mode
        clc
        xce

        // MUST NOT MODIFY CARRY

            rep     #%11111010
        // All flags except carry and interrupt-disable clear
        // a16
        // i16
            pha

            // Disable interrupts (make sure an NMI interrupt will not interfere with this break handler)
            // Also sets WRIO pins high (required for SLHV latching)
            // saves two cycles compared to using an 8 bit Accumulator)
            assert(NMITIMEN + 1 == WRIO)
            lda.w   #00 | ((WRIO.port1 | WRIO.port2)) << 8
            sta.l   NMITIMEN

            phx
            phy

            phb
            phd

            sep     #$24
        // a8
        // irq interrupts disable

            tsx

            // Save emulation flag to the stack
            // carry = old emulation flag
            lda.b   #0
            rol
            pha

        // CAN NOW MODIFY CARRY

        // invert emulation flag
        eor.b   #1
        lsr
        // carry set if in native mode

        // Write original stack pointer to the stack
        // (so it can be read by PrintRegisterLoop)
        rep     #$30
    // a16
        // carry set if in native mode
        tsc
        adc.w   #13
        pha

        lda.w   #0
        tcd
    // DP = 0

        // Decrement PC in stack to match the PC of the break instruction
        // (This is safe, this BreakHandler never returns)
        tsx
        dec.b   14,x
        dec.b   14,x


        sep     #$20
    // a8
        assert(pc() >> 16 == 0 || pc() >> 16 == 0x80)
        phk
        plb
    // DB = 0


        // Setup PPU
        jsr     ResetRegisters

        stz.w   BGMODE

        lda.b   #TM.bg1
        sta.w   TM

        assert(VRAM_BG1_MAP_WADDR == 0)
        stz.w   BG1SC

        lda.b   #(VRAM_BG1_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg1.shift
        sta.w   BG12NBA


        // Set the backdrop color to dark red
        stz.w   CGADD

        lda.b   #8
        sta.w   CGDATA
        stz.w   CGDATA

        // Set text color to white
        lda.b   #0xff
        sta.w   CGDATA
        sta.w   CGDATA


        // Clear tilemap

        ldx.w   #EmptyByte
        stx.w   A1T0
        stz.w   A1B0

        ldx.w   #DMAP.direction.toPpu | DMAP.fixed | DMAP.transfer.two | (VMDATA << 8)
        stx.w   DMAP0       // also sets BBAD0

        ldx.w   #32 * 32 * 2
        stx.w   DAS0

        lda.b   #VMAIN.incrementMode.high | VMAIN.increment.by1
        sta.w   VMAIN

        ldx.w   #VRAM_BG1_MAP_WADDR
        stx.w   VMADD

        lda.b   #MDMAEN.dma0
        sta.w   MDMAEN


        // Clear high byte of tile data

        ldx.w   #DMAP.direction.toPpu | DMAP.fixed | DMAP.transfer.one | (VMDATAH << 8)
        stx.w   DMAP0       // also sets BBAD0

        ldy.w   #Font_1bpp.size
        sty.w   DAS0

        ldx.w   #VRAM_BG1_TILES_WADDR
        stx.w   VMADD

        lda.b   #MDMAEN.dma0
        sta.w   MDMAEN


        // Copy font to VRAM

        // Y = Font_1bpp.size
        sty.w   DAS0

        ldx.w   #DMAP.direction.toPpu | DMAP.transfer.one | (VMDATAL << 8)
        stx.w   DMAP0       // also sets BBAD0

        ldx.w   #Font_1bpp
        lda.b   #Font_1bpp >> 16
        stx.w   A1T0
        sta.w   A1B0

        assert(VMAIN.incrementMode.low | VMAIN.increment.by1 == 0)
        stz.w   VMAIN

        ldx.w   #VRAM_BG1_TILES_WADDR
        stx.w   VMADD

        lda.b   #MDMAEN.dma0
        sta.w   MDMAEN


        // Print the strings
        tsx
        stx.b   zpStack

        ldx.w   #CrashString
        jsr     PrintString

        ldx.w   #BreakDataTable

        PrintRegisterLoop:
            jsr     PrintString

            // Print colon, space
            lda.b   #Font.COLON
            sta.w   VMDATAL
            stz.w   VMDATAL

            phx

                tdc
            // Ah = 0
                lda.b   1,x     // size (byte)
                tay

                lda.b   0,x     // stack offset (byte)
                rep     #$31
            // a16
            // carry clear
                adc.b   zpStack
                tax


                // X = register address
                // Y = register size

                sep     #$20
            // a8

                -
                    lda.b   0,x
                    lsr
                    lsr
                    lsr
                    lsr
                    assert(Font.ZERO == 1)
                    inc
                    sta.w   VMDATAL

                    lda.b   0,x
                    and.b   #0xf
                    assert(Font.ZERO == 1)
                    inc
                    sta.w   VMDATAL

                    dex

                    dey
                    bne     -

            plx
            inx
            inx

            lda.b   0,x
            bne     PrintRegisterLoop


        lda.b   #0xf
        sta.w   INIDISP

        // Interrupts are disabled.
        // This spinloop will loop forever and do absolutely nothing until the console has been reset.
        SpinLoop:
            wai
            bra     SpinLoop
    }


    // IN: X = string addr
    // OUT: X = addr at end of string
    //
    // a8
    // i16
    // DB = 0
    function PrintString {
        lda.b   0,x
        inx
        sta.w   VMADDL

        lda.b   0,x
        inx
        sta.w   VMADDH

        lda.b   0,x
        -
            sta.w   VMDATAL

            inx
            lda.b   0,x
            bne     -
        inx

        rts
    }
}

constant BreakHandler = BreakHandler.ISR


// Use `BreakHandler` for all unused interrupts

// (Used by emulation mode interrupts)
constant EmptyHandler = BreakHandler


if !{defined USES_IRQ_INTERRUPTS} {
    constant IrqHandler = BreakHandler
}

if !{defined USES_COP_INTERRUPTS} {
    constant CopHandler = BreakHandler
}


