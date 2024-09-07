#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# vim: set fenc=utf-8 ai ts=4 sw=4 sts=4 et:
#
#
# SPDX-FileCopyrightText: © 2020 Marcus Rowe <undisbeliever@gmail.com>
# SPDX-License-Identifier: Zlib
#
# Copyright © 2020 Marcus Rowe <undisbeliever@gmail.com>
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


import PIL.Image
import argparse


from _snes import image_to_snes, create_tilemap_data


FORMATS_BPP = {
    '2bpp'  : 2,
    '4bpp'  : 4,
    '8bpp'  : 8,
}



def parse_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument('-f', '--format', required=True,
                        choices=FORMATS_BPP.keys(),
                        help='tile format')
    parser.add_argument('-t', '--tileset-output', required=True,
                        help='tileset output file')
    parser.add_argument('-m', '--tilemap-output', required=True,
                        help='tilemap output file')
    parser.add_argument('-p', '--palette-output', required=True,
                        help='palette output file')
    parser.add_argument('--high-priority', required=False, action='store_true',
                        help='increase tilemap priority')
    parser.add_argument('image_filename', action='store',
                        help='Indexed png image')
    parser.add_argument('palette_image', action='store',
                        help='Palette png image')

    args = parser.parse_args()

    return args;



def main():
    args = parse_arguments()

    bpp = FORMATS_BPP[args.format]

    image = PIL.Image.open(args.image_filename)
    palette_image = PIL.Image.open(args.palette_image)

    tilemap, tileset_data, palette_data = image_to_snes(image, palette_image, bpp)

    tilemap_data = create_tilemap_data(tilemap, args.high_priority)

    with open(args.tileset_output, 'wb') as fp:
        fp.write(tileset_data)

    with open(args.tilemap_output, 'wb') as fp:
        fp.write(tilemap_data)

    with open(args.palette_output, 'wb') as fp:
        fp.write(palette_data)



if __name__ == '__main__':
    main()

