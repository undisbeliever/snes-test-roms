// common/assert.inc
// =================
//
// Macros that break assembly if a test fails.
//
//
// This file is part of the UnTech Game Engine.
// Copyright (c) 2016 - 2019, Marcus Rowe <undisbeliever@gmail.com>.
// Distributed under The MIT License: https://opensource.org/licenses/MIT


// Asserts than an expression is true
// Breaks assembly if expression if false
macro assert(test) {
    if !({test}) {
        error "{test}"
    }
}

// Asserts than an expression is a power of two
// Breaks assembly if expression if false
macro assertPowerOfTwo(evaluate test) {
    if ({test} & ({test} - 1)) != 0 {
        error "{test} is not a power of 2"
    }
}

// Asserts that a variable is inside zero page
// Breaks assembly if variable is not zero page
macro assertZeroPage(var) {
    evaluate addr = {var}
    if {addr} >= 0x100 && ({addr} < 0x7e0000 || {addr} >= 0x7e0100) {
        error "{var} is not inside zero page"
    }
}

// Asserts that a variable is inside low-RAM
// Breaks assembly if variable is not in low-RAM
macro assertLowRam(var) {
    evaluate addr = {var}
    if {addr} >= 0x2000 && ({addr} < 0x7e0000 || {addr} >= 0x7e2000) {
        error "{var} is not inside low-RAM"
    }
}

// vim: ft=bass-65816 ts=4 sw=4 et:

