#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# vim: set fenc=utf-8 ai ts=4 sw=4 sts=4 et:


# A simple python script that calculates and writes the SNES header checksum
# (and checksum complement) into the header of a homebrew SNES ROM.
#
# This script is intended to be used on homebrew SNES executables that were
# created with my `snes_header.inc` include file.
#
# WARNING: This script will modify the input file.
#
#
# SPDX-FileCopyrightText: © 2022 Marcus Rowe <undisbeliever@gmail.com>
# SPDX-License-Identifier: Zlib
#
# Copyright © 2022 Marcus Rowe <undisbeliever@gmail.com>
#
# This software is provided 'as-is', without any express or implied warranty.
# In no event will the authors be held liable for any damages arising from the
# use of this software.
#
# Permission is granted to anyone to use this software for any purpose, including
# commercial applications, and to alter it and redistribute it freely, subject to
# the following restrictions:
#
#    1. The origin of this software must not be misrepresented; you must not
#       claim that you wrote the original software. If you use this software in
#       a product, an acknowledgment in the product documentation would be
#       appreciated but is not required.
#
#    2. Altered source versions must be plainly marked as such, and must not be
#       misrepresented as being the original software.
#
#    3. This notice may not be removed or altered from any source distribution.


import os.path
import sys
import argparse


MIN_ROM_SIZE = 64 * 1024
MAX_ROM_SIZE = 4 * 1024 * 1024



def check_header_exists(rom_data, header_offset, expected_map_mode):
    """
    Checks that `rom_data` contains an unaltered header that is created by `snes_header.inc`.

    Returns true if header matches expected values
    """

    # snes_header.inc creates a header with a blank maker code, blank game code and no expansion chips.
    EXPECTED_START = (6 * b'\x20') + bytes(7)

    EXPECTED_CHECKSUM = b'\xaa\xaa\x55\x55'


    if rom_data[header_offset : header_offset + 13] != EXPECTED_START:
        return False

    if rom_data[header_offset + 0x25] & 0xef != expected_map_mode:
        return False

    if rom_data[header_offset + 0x2a] != 0x33:
        return False

    # Do not write to files that have changed the checksum bytes (from what is defined in `snes_header`.inc`).
    if rom_data[header_offset + 0x2c : header_offset + 0x30] != EXPECTED_CHECKSUM:
        return False


    return True



def calculate_checksum(rom_data, bank_size, header_offset, expected_map_mode):
    """
    Calculate checksum.

    Throws an exception if input is invalid.

    Returns *bytes of length 4* containing checksum and checksum complement.
    """

    rom_size = len(rom_data)

    # Confirm there is no copier header
    if rom_size % bank_size != 0:
        raise RuntimeError(f"sfc file is an invalid size (expected a multiple of { bank_size // 1024 } KiB).")


    if rom_size < MIN_ROM_SIZE:
        raise RuntimeError(f"sfc file is too small (min { MIN_ROM_SIZE // 1024 } KiB).")

    if rom_size > 4 * MAX_ROM_SIZE:
        raise RuntimeError(f"sfc file is too large (max { MAX_ROM_SIZE // 1024 } KiB).")


    # Confirm there is an SFC header in this file
    if not check_header_exists(rom_data, header_offset, expected_map_mode):
        raise RuntimeError('Could not find header.  Header must match `snes_header.inc` (and the checksum bytes MUST be unmodified).  Is the --hirom/--lorom argument correct?')


    # Check if a cartridge can be created with 2 power-of-two ROM chips
    if rom_size.bit_count() > 2:
        raise RuntimeError('sfc file is an invalid size (cannot fit on 2 ROM chips)')


    if rom_size.bit_count() == 1:
        checksum = sum(rom_data)
    else:
        # If the sfc file is not a power of two, it is split in two.
        # The first part contains the largest power-of-two bytes.
        # The second part is repeated until the ROM size is a power-of-two.

        largest_power_of_two = 1 << (rom_size.bit_length() - 1)

        if largest_power_of_two <= bank_size:
            # The "Remove old checksum" code below will only work correctly if the checksum is in the first part.
            raise RuntimeError("sfc file is too small.")

        first_part_checksum = sum(rom_data[0:largest_power_of_two])


        remaining = rom_size - largest_power_of_two
        assert(remaining > 0)
        assert(remaining.bit_count() == 1)
        assert(largest_power_of_two % remaining == 0)

        remaining_checksum = sum(rom_data[largest_power_of_two:])
        remaining_count = largest_power_of_two // remaining


        checksum = first_part_checksum + remaining_checksum * remaining_count


    # Remove old checksum and old complement from checksum
    checksum -= rom_data[header_offset + 0x2c]
    checksum -= rom_data[header_offset + 0x2d]
    checksum -= rom_data[header_offset + 0x2e]
    checksum -= rom_data[header_offset + 0x2f]
    # Add expected `checksum + complement` value to checksum
    checksum += 0xff
    checksum += 0xff


    # Write checksum and complement
    checksum = checksum & 0xffff
    complement = checksum ^ 0xffff

    return (complement.to_bytes(2, byteorder='little', signed=False)
            + checksum.to_bytes(2, byteorder='little', signed=False))



def write_sfc_checksum(sfc_filename, bank_size, header_offset, expected_map_mode):
    """
    Calculates and writes the checksum for `sfc_filename`.
    Throws an exception on error.
    """

    ext = os.path.splitext(sfc_filename)[1]
    if ext != '.sfc':
        raise RuntimeError('Expected a file with a .sfc extension')


    with open(sfc_filename, 'r+b') as fp:
        rom_data = fp.read(MAX_ROM_SIZE)

        # Test if fp is not at the end of the file
        if fp.read(1):
            raise RuntimeError(f"sfc file is too large (max { MAX_ROM_SIZE // 1024 } KiB).")

        checksum_bytes = calculate_checksum(rom_data, bank_size, header_offset, expected_map_mode)

        # Write checksum
        fp.seek(header_offset + 0x2c)
        fp.write(checksum_bytes)



def parse_arguments():
    parser = argparse.ArgumentParser(
                allow_abbrev=False,
                description='Calculates and writes the SNES header checksum into the header of a homebrew SNES ROM.',
                epilog='Distributed under the zlib License,  see the script source code for more details.')

    mgroup = parser.add_mutually_exclusive_group(required=True)
    mgroup.add_argument('--lorom', action="store_true",
                        help='sfc file uses LOROM mapping')
    mgroup.add_argument('--hirom', action="store_true",
                        help='sfc file uses HIROM mapping')

    parser.add_argument('sfc_filename', action='store',
                        help='sfc file (MODIFIED IN PLACE)')


    # Print full help message if there is no arguments
    if len(sys.argv) > 1:
        return parser.parse_args()
    else:
        parser.parse_args(['--help'])
        sys.exit("Expected arguments")



def main():
    args = parse_arguments()

    if args.lorom:
        write_sfc_checksum(args.sfc_filename, 32 * 1024, 0x007fb0, 0x20)
    elif args.hirom:
        write_sfc_checksum(args.sfc_filename, 64 * 1024, 0x00ffb0, 0x21)
    else:
        raise RuntimeError("Unknown mapping type")



if __name__ == '__main__':
    main()


