#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# vim: set fenc=utf-8 ai ts=4 sw=4 sts=4 et:


import itertools
from collections import namedtuple


TileMapEntry = namedtuple('TileMapEntry', ('tile_id', 'palette_id', 'hflip', 'vflip'))



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



def convert_rgb_color(c):
    r, g, b = c

    b = (b >> 3) & 31;
    g = (g >> 3) & 31;
    r = (r >> 3) & 31;

    return (b << 10) | (g << 5) | r;



def is_small_tile_not_transparent(image, transparent_color, xpos, ypos):
    """ Returns True if the tile contains a non-transparent pixel """

    if xpos + 8 > image.width or ypos + 8 > image.height:
        raise ValueError(f"position out of bounds: { xpos }, { ypos }")

    return any(convert_rgb_color(image.getpixel((x, y))) != transparent_color
                 for y in range(ypos, ypos + 8) for x in range(xpos, xpos + 8))



def extract_tileset_tiles(image):
    """ Extracts 8x8px tiles from the image. """

    if image.mode != 'RGB':
        image = image.convert('RGB')

    if image.width % 8 != 0:
        raise ValueError('Image height MUST BE multiple of 8')

    if image.height % 8 != 0:
        raise ValueError('Image height MUST BE multiple of 8')


    for ty in range(0, image.height, 8):
        for tx in range(0, image.width, 8):

            tile_data = list()

            for y in range(ty, ty + 8):
                for x in range(tx, tx + 8):
                    tile_data.append(convert_rgb_color(image.getpixel((x, y))))

            yield tile_data



def extract_small_tile(image, xpos, ypos):
    if xpos + 8 > image.width or ypos + 8 > image.height:
        raise ValueError(f"position out of bounds: { xpos }, { ypos }")

    return [ convert_rgb_color(image.getpixel((x, y)))
             for y in range(ypos, ypos + 8) for x in range(xpos, xpos + 8) ]



def extract_large_tile(image, xpos, ypos):
    if xpos + 16 > image.width or ypos + 16 > image.height:
        raise ValueError(f"position out of bounds: { xpos }, { ypos }")

    return [ convert_rgb_color(image.getpixel((x, y)))
             for y in range(ypos, ypos + 16) for x in range(xpos, xpos + 16) ]



def extract_tilemap_tiles(image):
    """ Extracts 8x8px tiles from the image, in the same order as a SNES tilemap. """

    if image.mode != 'RGB':
        image = image.convert('RGB')

    if image.width % 256 != 0:
        raise ValueError('Image width MUST BE a multiple of 256')

    if image.height % 256 != 0:
        raise ValueError('Image height MUST BE a multiple of 256')

    if image.width > 512 or image.height > 512:
        raise ValueError('Maximum image size is 512x512 pixels')


    t_width = image.width // 8
    t_height = image.height // 8

    img_data = image.getdata()

    for screen_y in range(t_height // 32):
        for screen_x in range(t_width // 32):
            for ty in range(32):
                ty = screen_y * 256 + ty * 8
                for tx in range(32):
                    tx = screen_x * 256 + tx * 8

                    tile_data = list()

                    for y in range(ty, ty + 8):
                        for x in range(tx, tx + 8):
                            tile_data.append(convert_rgb_color(image.getpixel((x, y))))

                    yield tile_data



def create_palettes_map(image, bpp, pad_palette_data=None):
    # Returns palettes_map

    if image.mode != 'RGB':
        image = image.convert('RGB')


    colors_per_palette = 1 << bpp
    max_colors = min(colors_per_palette * 8, 256)

    if image.width != 16:
        raise ValueError('Palette Image MUST BE 16 px in width')

    if image.width * image.height > max_colors:
        raise ValueError(f"Palette Image has too many colours (max { max_colors })")

    image_data = image.getdata()


    palettes_map = list()

    for p in range(len(image_data) // colors_per_palette):
        pal_map = dict()

        for x in range(colors_per_palette):
            c = convert_rgb_color(image_data[p * colors_per_palette + x])
            if c not in pal_map:
                pal_map[c] = x

        palettes_map.append(pal_map)

    return palettes_map



def convert_palette_image(image):
    palette_data = bytearray()

    for c in image.getdata():
        u16 = convert_rgb_color(c)

        palette_data.append(u16 & 0xff)
        palette_data.append(u16 >> 8)

    return palette_data



def get_palette_id(tile, palette_map):
    # Returns a tuple of (palette_id, palette_map)
    for palette_id, pal_map in enumerate(palette_map):
        if all([c in pal_map for c in tile]):
            return palette_id, pal_map

    return None, None



_H_FLIP_ORDER_SMALL = [ (y * 8 + x) for y, x in itertools.product(range(8), reversed(range(8))) ]
_V_FLIP_ORDER_SMALL = [ (y * 8 + x) for y, x in itertools.product(reversed(range(8)), range(8)) ]

def hflip_tile(tile):
    return bytes([ tile[i] for i in _H_FLIP_ORDER_SMALL ])

def vflip_tile(tile):
    return bytes([ tile[i] for i in _V_FLIP_ORDER_SMALL ])


_H_FLIP_ORDER_LARGE = [ (y * 16 + x) for y, x in itertools.product(range(16), reversed(range(16))) ]
_V_FLIP_ORDER_LARGE = [ (y * 16 + x) for y, x in itertools.product(reversed(range(16)), range(16)) ]

def hflip_large_tile(tile):
    return bytes([ tile[i] for i in _H_FLIP_ORDER_LARGE ])

def vflip_large_tile(tile):
    return bytes([ tile[i] for i in _V_FLIP_ORDER_LARGE ])


def split_large_tile(tile):
    return (
        [ tile[y * 16 + x] for y in range(0, 8 ) for x in range(0, 8 ) ],
        [ tile[y * 16 + x] for y in range(0, 8 ) for x in range(8, 16) ],
        [ tile[y * 16 + x] for y in range(8, 16) for x in range(0, 8 ) ],
        [ tile[y * 16 + x] for y in range(8, 16) for x in range(8, 16) ],
    )



def convert_tilemap_and_tileset(tiles, palettes_map):
    # Returns a tuple(tilemap, tileset)

    invalid_tiles = list()

    tilemap = list()
    tileset = list()

    tileset_map = dict()

    for tile_index, tile in enumerate(tiles):
        palette_id, pal_map = get_palette_id(tile, palettes_map)

        if pal_map:
            # Must be bytes() here as a dict() key must be immutable
            tile_data = bytes([pal_map[c] for c in tile])

            tile_match = tileset_map.get(tile_data, None)
            if tile_match is None:
                tile_id = len(tileset)
                tile_match = tile_id, False, False

                tileset.append(tile_data)

                h_tile_data = hflip_tile(tile_data)
                v_tile_data = vflip_tile(tile_data)
                hv_tile_data = vflip_tile(h_tile_data)

                tileset_map[tile_data] = tile_match
                tileset_map.setdefault(h_tile_data, (tile_id, True, False))
                tileset_map.setdefault(v_tile_data, (tile_id, False, True))
                tileset_map.setdefault(hv_tile_data, (tile_id, True, True))

            tilemap.append(TileMapEntry(tile_id=tile_match[0], palette_id=palette_id, hflip=tile_match[1], vflip=tile_match[2]))
        else:
            invalid_tiles.append(tile_index)

    if invalid_tiles:
        raise ValueError(f"Cannot find palette for tiles {invalid_tiles}")

    return tilemap, tileset



def create_tilemap_data(tilemap, default_order):
    data = bytearray()

    assert(len(tilemap) % 32 * 32 == 0)

    for t in tilemap:
        data.append(t.tile_id & 0xff)
        data.append(((t.tile_id & 0x3ff) >> 8) | ((t.palette_id & 7) << 2)
                    | (bool(default_order) << 5) | (bool(t.hflip) << 6) | (bool(t.vflip) << 7))

    return data



def create_tilemap_data_low(tilemap):
    data = bytearray()

    assert(len(tilemap) % 32 * 32 == 0)

    for t in tilemap:
        data.append(t.tile_id & 0xff)

    return data



def create_tilemap_data_high(tilemap, default_order):
    data = bytearray()

    assert(len(tilemap) % 32 * 32 == 0)

    for t in tilemap:
        data.append(((t.tile_id & 0x3ff) >> 8) | ((t.palette_id & 7) << 2)
                    | (bool(default_order) << 5) | (bool(t.hflip) << 6) | (bool(t.vflip) << 7))

    return data



def image_to_snes(image, palette_image, bpp):
    # Return (tilemap, tile_data, palette_data)

    tilemap, tileset = convert_tilemap_and_tileset(
                            extract_tilemap_tiles(image),
                            create_palettes_map(palette_image, bpp))

    tile_data = convert_snes_tileset(tileset, bpp)

    palette_data = convert_palette_image(palette_image)

    return tilemap, tile_data, palette_data




