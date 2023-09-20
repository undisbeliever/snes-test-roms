// This test runs the quick-model-1-dma-crash without an IRQ delay.
//
//
// Copyright (c) 2023, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


evaluate _dtl = DMA_TRANSFER_LENGTH

define   ROM_NAME = "QUICK DMA CRASH {_dtl}"
constant VERSION = 3

include "_quick-model-1-dma-crash-test.inc"


// DB = 0
// SP = 0x01??
// d = 0
// i = 1
// e = 1
// a8
// i8
seek(0x8000)
function ResetHandler {
    QuickDmaTest(DMA_TRANSFER_LENGTH)
}



seek(0xE000)
HdmaTable:
namespace HdmaTable {
    // HDMA table to CGRAM (2 registers write twice)

    variable _sl = 0

    while _sl < DISPLAY_HEIGHT {
        db  0x80 | 0x7f     // HDMA repeat mode

        variable _i = 0
        while _i < 0x7f {
            evaluate c = (_sl + 8) % 64
            if {c} > 31 {
                evaluate c = 63 - {c}
            }
            _sl = _sl + 1

            dw  0           // CGADD
            dw  {c} << 5    // CGDATA

            _i = _i + 1
        }
    }

    db 0
}


