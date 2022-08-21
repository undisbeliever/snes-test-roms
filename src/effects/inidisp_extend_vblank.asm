// Extend VBlank demo
//
// This demo uses extended-VBlank to transfer 8736 bytes of data to the PPU
// on every display frame.
//
// IRQ interrupts and the INIDISP register are used to decrease the number
// of visible scanlines, moving them into the VBlank routine and increasing
// the amount of data that can be transferred during the VBlank routine.
//
// The mid-screen activation OBJ glitch is hidden by disabling backgrounds
// and sprites for the first visible scanline.  This technique works best
// if the background colour is black.
//
// The IRQ interrupts have been carefully timed to ensure critical register
// writes occur within Horizontal-Blank.
//
// This demo does not use HDMA.  Combining HDMA with extended VBlank
// requires careful consideration and is beyond the scope of this demo.
//
//
// Copyright (c) 2021, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT



define MEMORY_MAP = LOROM
define ROM_SIZE = 4
define ROM_SPEED = fast
define REGION = Japan
define ROM_NAME = "INIDISP EXTEND VBLANK"
define VERSION = 1

define USES_IRQ_INTERRUPTS


architecture wdc65816-strict

include "../common.inc"

createCodeBlock(code,       0x808000, 0x80ffaf)
createCodeBlock(rom1,       0x818000, 0x81ffff)
createCodeBlock(rom2,       0x828000, 0x82ffff)
createCodeBlock(rom3,       0x838000, 0x83ffff)
createCodeBlock(rom4,       0x848000, 0x84ffff)
createCodeBlock(rom5,       0x858000, 0x85ffff)
createCodeBlock(rom6,       0x868000, 0x86ffff)
createCodeBlock(rom7,       0x878000, 0x87ffff)
createCodeBlock(rom8,       0x888000, 0x88ffff)
createCodeBlock(rom9,       0x898000, 0x89ffff)
createCodeBlock(rom10,      0x8a8000, 0x8affff)
createCodeBlock(rom11,      0x8b8000, 0x8bffff)
createCodeBlock(rom12,      0x8c8000, 0x8cffff)
createCodeBlock(rom13,      0x8d8000, 0x8dffff)
createCodeBlock(rom14,      0x8e8000, 0x8effff)
createCodeBlock(rom15,      0x8f8000, 0x8fffff)

createRamBlock(lowram,      0x7e0100, 0x7e1f7f)
createRamBlock(stack,       0x7e1f80, 0x7e1fff)


include "../reset_handler.inc"
include "../break_handler.inc"
include "../dma_forceblank.inc"


//
// ============================================================================
//


// Number of scanlines to remove from the top and bottom.
//
// There will be `224 - 2 * N_SCANLINES_TO_REMOVE` visible scanlines.
//
// VBlank will be extended by `2 * N_SCANLINES_TO_REMOVE - 1` scanlines.
//
constant N_SCANLINES_TO_REMOVE   = 10;


// The scanline to trigger the `IRQ_EnableDisplay` IRQ ISR.
constant ENABLE_DISPLAY_SCANLINE = N_SCANLINES_TO_REMOVE - 1

// The scanline to trigger the `IRQ_VBlank` IRQ ISR.
constant VBLANK_SCANLINE         = 224 - N_SCANLINES_TO_REMOVE


// H-Counter position of the IRQ interrupts.
//
// Mesen-SX's Event Viewer was used to confirm the IRQ ISR's critical
// writes occurred within Horizontal-Blank.
//
// NOTE: This value MUST be re-calibrated whenever `IRQ_EnableDisplay`,
//       `IRQ_EnableMainScreen`, or the `INIDISP` write within `IRQ_VBlank`
//       is changed.
//
constant IRQ_X_POS = 240



// IRQ ISR
//
// Located in RAM so the address of the interrupt handler can be changed.
//
// Will contain `jml 0x80????`, where `????` is the address of the next IRQ
// handler to execute.
allocate(IrqHandler, lowram, 4)


// Address of the next IRQ ISR.
// (long addr)
constant irqHandlerAddr = IrqHandler + 1


// Update VBlank flag.
//
// Set by `WaitFrame`, cleared by `IRQ_VBlank`.
//
// (byte flag)
allocate(vBlankFlag, lowram, 1)


// The brightness of the display for the current frame.
//
// (uint8 INIDISP shadow variable)
allocate(brightness, lowram, 1)


// Shadow variable of the TM register.
//
// (uint8 TM shadow variable)
allocate(tmShadow, lowram, 1)



// This demo does not use NMI Interrupts.
constant NmiHandler = BreakHandler



// Initialize and enable the extend VBlank IRQs.
//
// Assumes `brightness` and `tmShadow` are already set.
//
// Assumes IRQ and NMI interrupts are disabled.
//
// REQUIRES: 8 bit A, 16 bit Index, DB access registers
// REQUIRES: Force-Blank
//
a8()
i16()
code()
function SetupAndEnableIrqHandler {
    // Write `jml IRQ_VBlank` to IrqHandler
    lda.b   #0x5c
    sta.w   IrqHandler

    ldx.w   #IRQ_VBlank
    stx.w   IrqHandler + 1

    lda.b   #IRQ_VBlank >> 16
    sta.w   IrqHandler + 3


    // Setup IRQ time
    ldx.w   #IRQ_X_POS
    stx.w   HTIME

    ldx.w   #VBLANK_SCANLINE
    stx.w   VTIME


    // Enable IRQ Interrupts
    lda.b   #NMITIMEN.vCounter | NMITIMEN.hCounter | NMITIMEN.autoJoy
    sta.w   NMITIMEN

    // Enable IRQ interrupts
    cli

    // Clear IRQ flag
    lda.w   TIMEUP

    rts
}



// First IRQ ISR of the display frame.
//
// Triggered on X=`IRQ_X_POS`, Y=`ENABLE_DISPLAY_SCANLINE`.
//
// Turns off Force-Blank and ends the extended VBlank.
//
au()
iu()
// DB unknown
code()
function IRQ_EnableDisplay {

    // No need to set/clear x or decimal flags.  They are not used by this ISR.
    sep     #$20
a8()
    pha

    // Data Bank and Direct Page registers are unknown.
    // Use long addressing on all data writes.


    // Enable display.
    //
    // A bank-byte of `0x0f` is used to pre-load the data-bus with bit-7
    // clear (and full brightness) before the INIDISP write to mitigate the
    // INIDISP open-bus early read glitch (corrupt sprite tiles).
    //
    // This mitigation is not required as the OBJ tiles on the next
    // scanline are already glitched (as the screen is enabled mid-frame).
    //
    // Long addressing is required as the Data Bank is unknown.
    lda.l   brightness
    sta.l   0x0f0000 | INIDISP


    // Schedule the next IRQ on the next scanline

    lda.b   #IRQ_EnableMainScreen
    sta.l   irqHandlerAddr
    lda.b   #IRQ_EnableMainScreen >> 8
    sta.l   irqHandlerAddr + 1

    lda.b   #NMITIMEN.hCounter | NMITIMEN.autoJoy
    sta.l   NMITIMEN


    // Clear IRQ flag
    lda.l   TIMEUP


    pla
    rti
}



// Second IRQ ISR of the display frame.
//
// Triggered on X=`IRQ_X_POS`, Y=`ENABLE_DISPLAY_SCANLINE + 1`.
//
// Turns on background layers and sprites.
//
au()
iu()
// DB unknown
code()
function IRQ_EnableMainScreen {

    // No need to set/clear x or decimal flags.  They are not used by this ISR.
    sep     #$20
a8()
    pha

    // Data Bank and Direct Page registers are unknown.
    // Use long addressing on all reads and writes.

    // Enable Backgrounds and sprites
    lda.l   tmShadow
    sta.l   TM


    // Schedule next IRQ
    // (8 bit write to VTIME is safe, VTIMEH is always 0)

    lda.b   #IRQ_VBlank
    sta.l   irqHandlerAddr
    lda.b   #IRQ_VBlank >> 8
    sta.l   irqHandlerAddr + 1

    lda.b   #VBLANK_SCANLINE
    sta.l   VTIMEL

    lda.b   #NMITIMEN.vCounter | NMITIMEN.hCounter | NMITIMEN.autoJoy
    sta.l   NMITIMEN


    // Clear IRQ flag
    lda.l   TIMEUP


    pla
    rti
}



// Third IRQ ISR of the display frame.
//
// Triggered on X=`IRQ_X_POS`, Y=`VBLANK_SCANLINE`.
//
//  * Turns on Force-Blank, disabling the screen, starting the extended VBlank.
//  * Turns off background layers and sprites.
//  * Executes the `VBlank` routine if `vBlankFlag` is set.
//
// This routine MUST COMPLETE before the EnableDisplay IRQ is scheduled to start.
// Failure to do so can cause blank lines and/or fullscreen flashing (major
// photosensitivity issue).
//
au()
iu()
// DB unknown
code()
function IRQ_VBlank {

    // Clear m, x, decimal flags
    rep     #$38
a16()
i16()
    pha

    sep     #$20
a8()
    // Disable display.
    //
    // INIDISP is written as early as possible to ensure write is preformed
    // within H-Blank.
    //
    // A bank-byte of `0x80` is used to pre-load the data-bus with bit-7 set
    // before the INIDISP write to mitigate the INIDISP open-bus early read
    // glitch.
    //
    // Long addressing is required as the Data Bank is unknown.
    lda.l   brightness
    ora.b   #INIDISP.force
    sta.l   0x800000 | INIDISP


    phx
    phy
    phb

    assert(pc() >> 16 == 0x80)
    phk
    plb
// DB = 0x80


    // Schedule next IRQ Handler
    // (8 bit write to VTIME is safe, VTIMEH is always 0)
    //
    // Scheduled early to ensure the next IRQ is triggered on time.

    lda.b   #IRQ_EnableDisplay
    sta.w   irqHandlerAddr
    lda.b   #IRQ_EnableDisplay >> 8
    sta.w   irqHandlerAddr + 1

    lda.b   #ENABLE_DISPLAY_SCANLINE
    sta.w   VTIMEL

    // Clear IRQ flag
    lda.w   TIMEUP


    // Disable all backgrounds and sprites
    stz.w   TM


    // Execute Vertical Blank routine (if vBlankFlag is set)
    lda.w   vBlankFlag
    beq     +
        jsr     VerticalBlank

        stz.w   vBlankFlag
    +


    // Confirm VBlank did not overrun.
    // Break if VBlank overran.
    sep     #$30
i8()
    // Read vertical scanline location
    lda.w   SLHV
    ldx.w   OPVCT
    lda.w   OPVCT
    // X = OPVCT low byte
    // A = OPVCT high byte

    and.b   #1
    bne     NoOverrun
        cpx.b   #ENABLE_DISPLAY_SCANLINE
        bcc     NoOverrun

        cpx.b   #VBLANK_SCANLINE
        bcs     NoOverrun

            // VBlank overran
            jmp     BreakHandler
NoOverrun:


    // Restore registers from stack
    rep     #$30
a16()
i16()
    plb
    ply
    plx
    pla

    rti
}



// Wait until the end of `IRQ_VBlank`.
//
// REQUIRES: 8 bit A, DB access low-RAM
a8()
iu()
code()
function WaitFrame {

    // Execute `VBlank` routine on the next `IRQ_VBlank` interrupt
    lda.b   #1
    sta.w   vBlankFlag


    // Loop until the vBlankFlag clear
    Loop:
        wai
        lda.w   vBlankFlag
        bne     Loop

    rts
}



//
// ============================================================================
//


// Demo Variables
// --------------


// VRAM Table
constant VRAM_BG1_MAP_WADDR   = 0x0000
constant VRAM_BG1_TILES_WADDR = 0x1000
constant VRAM_OBJ_TILES_WADDR = 0x6000


// The address of the OBJ tiles to load during VBlank
// (long addr)
allocate(objTilesAddr, lowram, 3)


// Frame counter.  Incremented once per frame.
// (uint8)
allocate(frameCounter, lowram, 1)


// OAM Buffer
// (two tables: 512 byte low table and 32 byte high table)
allocate(oamBuffer, lowram, 544)
constant oamBuffer.size = 544

constant hiOamBuffer = oamBuffer + 512



// Initialize the demo's variables
//
// REQUIRES: 8 bit A, 16 bit Index, DB access registers
a8()
i16()
code()
function Init {

    // Initialize oamBuffer

    // Copy InitialOamBuffer to oamBuffer
    ldx.w   #0
    -
        lda.l   Resources.InitialOamBuffer,x
        sta.w   oamBuffer,x

        inx
        cpx.w   #Resources.InitialOamBuffer.size
        bcc     -

    // Move all unused sprites off-screen
    lda.b   #256 - 16
    -
        sta.w   oamBuffer,x
        inx
        cpx.w   #128 * 4
        bcc     -

    // Clear oamBuffer high table
    -
        stz.w   oamBuffer,x
        inx
        cpx.w   #oamBuffer.size
        bcc     -


    // Initialize `objTilesAddr`
    ldx.w   #Resources.ObjTiles.Block_1
    stx.w   objTilesAddr
    lda.b   #Resources.ObjTiles.Block_1 >> 16
    sta.w   objTilesAddr + 2


    rts
}



// Setup the PPU.
//
// REQUIRES: 8 bit A, 16 bit Index, DB access registers
// REQUIRES: Force-Blank
a8()
i16()
code()
function SetupPpu {

    // Disable HDMA
    stz.b   HDMAEN


    // Setup PPU registers

    // Mode 0
    stz.w   BGMODE

    lda.b   #(VRAM_BG1_MAP_WADDR / BGXSC.base.walign) << BGXSC.base.shift | BGXSC.map.s32x32
    sta.w   BG1SC

    lda.b   #(VRAM_BG1_TILES_WADDR / BG12NBA.walign) << BG12NBA.bg1.shift
    sta.w   BG12NBA

    lda.b   #OBSEL.size.s16_32 | (VRAM_OBJ_TILES_WADDR / OBSEL.base.walign) << OBSEL.base.shift
    sta.w   OBSEL

    lda.b   #TM.bg1 | TM.obj
    sta.w   tmShadow


    // Move BG1 so it appears centered
    lda.b   #8
    sta.w   BG1HOFS
    stz.w   BG1HOFS

    lda.b   #7
    sta.w   BG1VOFS
    stz.w   BG1VOFS


    // Transfer Palettes to CGRAM
    stz.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Bg1_Palette)

    lda.b   #128
    sta.w   CGADD
    Dma.ForceBlank.ToCgram(Resources.Obj_Palette)


    // Transfer BG1 data to VRAM
    ldx.w   #VRAM_BG1_MAP_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg1_Tilemap)

    ldx.w   #VRAM_BG1_TILES_WADDR
    stx.w   VMADD
    Dma.ForceBlank.ToVram(Resources.Bg1_Tiles)


    // Start demo at 1 brightness
    lda.b   #1
    sta.w   brightness


    rts
}



// Process the demo.
//
// Called once per frame.
//
// REQUIRES: 8 bit A, 16 bit Index, DB access registers
a8()
i16()
code()
function Process {
    inc.w   frameCounter


    // Move all the sprites up one pixel
    ldx.w   #0
    -
        dec.w   oamBuffer + 1,x
        inx
        inx
        inx
        inx
        cpx.w   #Resources.InitialOamBuffer.size
        bcc     -


    // Change sprite tiles every second frame
    lda.w   frameCounter
    and.b   #1
    bne     SkipChangeTiles
        // Increment `objTilesAddr` (with wrapping)
        rep     #$30
    a16()
        lda.w   objTilesAddr
        clc
        adc.w   #Resources.ObjTiles.FRAME_SIZE
        sta.w   objTilesAddr

        sep     #$20
    a8()
        bcc     ++
            // 16 bit address overflowed, reset address
            ldx.w   #Resources.ObjTiles.FirstAddr
            stx.w   objTilesAddr

            // Increment `objTilesAddr` bank (with wrapping)
            lda.w   objTilesAddr + 2
            inc
            cmp.b   #Resources.ObjTiles.LastBank
            bcc     +
                lda.b   #Resources.ObjTiles.FirstBank
            +
            sta.w   objTilesAddr + 2
        +
SkipChangeTiles:


    // On every 16th frame: Increment brightness (if not at full brightness)
    lda.w   frameCounter
    and.b   #15
    bne     +
        lda.w   brightness
        cmp.b   #INIDISP.brightness.mask
        beq     +
            inc
            sta.w   brightness
    +

    rts
}



// VBlank routine.
//
// Called once per frame by `IRQ_VBlank`.
//
// REQUIRES: 8 bit A, 16 bit Index, DB access registers
// REQUIRES: Force-Blank
a8()
i16()
code()
function VerticalBlank {

    // Transfer oamBuffer to OAM using DMA channel 0
    stz.w   OAMADDL
    stz.w   OAMADDH

    lda.b   #DMAP.direction.toPpu | DMAP.transfer.one
    sta.w   DMAP0

    lda.b   #OAMDATA
    sta.w   BBAD0

    ldx.w   #oamBuffer
    stx.w   A1T0
    lda.b   #oamBuffer >> 16
    sta.w   A1B0

    ldx.w   #oamBuffer.size
    stx.w   DAS0

    lda.b   #MDMAEN.dma0
    sta.w   MDMAEN


    // Transfer tiles at address `objTilesAddr` to VRAM using DMA channel 0
    ldx.w   #VRAM_OBJ_TILES_WADDR
    stx.w   VMADD

    lda.b   #VMAIN.incrementMode.high | VMAIN.increment.by1
    sta.w   VMAIN

    lda.b   #DMAP.direction.toPpu | DMAP.transfer.two
    sta.w   DMAP0

    lda.b   #VMDATA
    sta.w   BBAD0

    ldx.w   objTilesAddr
    stx.w   A1T0
    lda.w   objTilesAddr + 2
    sta.w   A1B0

    ldx.w   #Resources.ObjTiles.FRAME_SIZE
    stx.w   DAS0

    lda.b   #MDMAEN.dma0
    sta.w   MDMAEN


    rts
}



au()
iu()
code()
function Main {
    sep     #$20
    rep     #$10
a8()
i16()

    phk
    plb
// DB = 0x80


    // Force-Blank
    lda.b   #INIDISP.force
    sta.l   0x800000 | INIDISP

    jsr     Init
    jsr     SetupPpu

    jsr     SetupAndEnableIrqHandler


    // Setting DB to `0x7e` to demonstrate why the IRQ handlers must either
    // change the DB register or use long-addressing on every read/write.
    lda.b   #0x7e
    pha
    plb
// DB = 0x7e

    MainLoop:
        jsr     WaitFrame

        jsr     Process

        bra     MainLoop
}



namespace Resources {

    // Object Tiles are too large to fit inside a single bank.
    namespace ObjTiles {
        // The comment at the top of this file MUST BE updated if `FRAME_SIZE` changes.
        constant FRAME_SIZE = 128 * 128 / 2

        constant N_FRAMES = 60

        constant FRAMES_PER_BANK = 32 * 1024 / FRAME_SIZE
        constant N_BANKS = (N_FRAMES + (FRAMES_PER_BANK - 1)) / FRAMES_PER_BANK
        constant BYTES_PER_BANK = FRAME_SIZE * FRAMES_PER_BANK

        variable i = 0
        while i < N_BANKS {
            evaluate _bank = i + 1
            rodata(rom{_bank})
                assert(pc() & 0xffff == 0x8000)

                insert Block_{_bank}, "../../gen/inidisp_extend_vblank/spinning-logo-4bpp-tiles.tiles", i * BYTES_PER_BANK, BYTES_PER_BANK

            i = i + 1
        }

        constant FirstAddr = Block_1 & 0xffff

        constant FirstBank = Block_1 >> 16
        constant LastBank  = pc() >> 16
    }

    rodata(code)
    insert Obj_Palette, "../../gen/inidisp_extend_vblank/spinning-logo-4bpp-tiles.pal"

    insert InitialOamBuffer, "../../gen/inidisp_extend_vblank/spinning-logo-oam.bin"
    assert(Resources.InitialOamBuffer.size < 544)


    rodata(code)
    insert Bg1_Palette, "../../gen/inidisp_extend_vblank/bg1-2bpp-tiles.pal"
    insert Bg1_Tiles, "../../gen/inidisp_extend_vblank/bg1-2bpp-tiles.tiles"
    insert Bg1_Tilemap, "../../gen/inidisp_extend_vblank/bg1-tilemap.bin"
}


finalizeMemory()

