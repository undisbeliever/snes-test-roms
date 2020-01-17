#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# vim: set fenc=utf-8 ai ts=4 sw=4 sts=4 et:


import PIL.Image
import argparse
import struct


def convert_palette(palette, max_colors):
    if not palette:
        raise ValueError('Image must have a palette')

    data_type, pdata = palette.getdata()

    if data_type != 'RGB':
        raise ValueError('Image palette is invalid')

    n_colors = len(pdata) / 3
    if n_colors > max_colors:
        raise ValueError('Image palette has too many colors')

    snes_pal_data = bytearray()

    for c in struct.iter_unpack('BBB', pdata):
        r, g, b = c

        b = (b >> 3) & 31;
        g = (g >> 3) & 31;
        r = (r >> 3) & 31;

        u16 = (b << 10) | (g << 5) | r;

        snes_pal_data.append(u16 & 0xff);
        snes_pal_data.append(u16 >> 8);

    assert len(snes_pal_data) == n_colors * 2;

    return snes_pal_data



def extract_tiles(image):
    if image.width % 8 != 0 or image.height % 8 != 0:
        raise ValueError('Image width MUST BE a multiple of 8')

    if image.height % 8 != 0:
        raise ValueError('Image height MUST BE a multiple of 8')

    t_width = image.width // 8
    t_height = image.height // 8

    img_data = image.getdata()

    for ty in range(t_height):
        ty *= 8
        for tx in range(t_width):
            tx *= 8

            tile_data = bytearray()

            for y in range(ty, ty + 8):
                for x in range(tx, tx + 8):
                    tile_data.append(image.getpixel((x, y)))

            yield tile_data


def convert_mode7_tileset(tiles):
    out = bytes().join(tiles)

    if len(out) > 256 * 64:
        raise ValueError('Too many tiles in image')

    return out


def convert_snes_tileset(tiles, bpp):
    out = bytearray()

    for tile in tiles:
        for b in range(0, bpp, 2):
            for y in range(0, 8):
                for bi in range(b, min(b+2, bpp)):
                    byte = 0
                    mask = 1 << bi
                    for x in range(0, 8):
                        byte <<= 1
                        if tile[x + y * 8] & mask:
                            byte |= 1
                    out.append(byte)
    return out

FORMATS = {
    'm7'    : convert_mode7_tileset,
    'mode7' : convert_mode7_tileset,
    '1bpp'  : lambda tiles : convert_snes_tileset(tiles, 1),
    '2bpp'  : lambda tiles : convert_snes_tileset(tiles, 2),
    '3bpp'  : lambda tiles : convert_snes_tileset(tiles, 3),
    '4bpp'  : lambda tiles : convert_snes_tileset(tiles, 4),
    '8bpp'  : lambda tiles : convert_snes_tileset(tiles, 8),
}


def parse_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument('-f', '--format', required=True,
                        choices=FORMATS.keys(),
                        help='tile format')
    parser.add_argument('-t', '--tileset-output', required=True,
                        help='tileset output file')
    parser.add_argument('-p', '--palette-output', required=True,
                        help='palette output file')
    parser.add_argument('-c', '--max-colors', required=False,
                        type=int, default=256,
                        help='maximum number of colors')
    parser.add_argument('image_filename', action='store',
                        help='Indexed png image')

    args = parser.parse_args()

    return args;


def main():
    args = parse_arguments()

    tile_converter = FORMATS[args.format]

    image = PIL.Image.open(args.image_filename)

    palette = convert_palette(image.palette, args.max_colors)
    tileset = tile_converter(extract_tiles(image))

    with open(args.tileset_output, 'wb') as fp:
        fp.write(tileset)

    with open(args.palette_output, 'wb') as fp:
        fp.write(palette)


if __name__ == '__main__':
    main()

