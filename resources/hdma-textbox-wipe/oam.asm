

macro soldierFacingRight(evaluate xPos, evaluate yPos) {
    variable ty = 0
    while ty < 3 {
        variable tx = 0
        while tx < 2 {
            db {xPos} + tx * 8
            db {yPos} + ty * 8
            db tx + ty * 2
            db 0x20

            tx = tx + 1
        }
        ty = ty + 1
    }
}


macro soldierFacingLeft(evaluate xPos, evaluate yPos) {
    variable ty = 0
    while ty < 3 {
        variable tx = 0
        while tx < 2 {
            db {xPos} + 8 - tx * 8
            db {yPos} + ty * 8
            db tx + ty * 2
            db 0x60

            tx = tx + 1
        }
        ty = ty + 1
    }
}


soldierFacingRight(84, 84)
soldierFacingRight(90, 64)
soldierFacingRight(96, 44)

soldierFacingLeft(156, 84)
soldierFacingLeft(150, 64)
soldierFacingLeft(144, 44)



constant TO_FILL = 512 - pc()
if TO_FILL <= 0 {
    error "Too many sprites"
}

// Move all unused sprites offscreen
fill 512 - pc(), 256-8


// Hi table
fill 32, 0


