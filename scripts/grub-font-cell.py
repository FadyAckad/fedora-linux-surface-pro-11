#!/usr/bin/python3
"""Fit a GRUB console font (PF2) to the character cell gfxterm draws it in.

gfxterm's cell is as wide as the widest printable ASCII glyph's advance and as high as the font's tallest glyph
(MAXH); it puts the baseline ASCE rows below the cell's top, and what a glyph draws outside its cell is lost.
grub2-mkfont takes ASCE and DESC from the highest and the lowest glyph of the whole face, so their sum exceeds MAXH
and the baseline lies too low: at size 40 (ASCE 42, DESC 15, MAXH 48) the underscore fell below the cell and every
descender lost its last two rows. Step 30 builds the font once to read these numbers and again with them.

Usage: grub-font-cell.py metrics|check FONT.pf2
  metrics  print the ascent and descent to build with (grub2-mkfont --asce, --desc): the descent is the lowest row
           of the glyphs GRUB draws, the ascent the rest of the cell
  check    print the cell as WIDTHxHEIGHT; exit 1 naming the glyphs with rows above or below it
The glyphs GRUB draws: printable ASCII and the arrows, lines, corners and triangles of its menu and editor
(include/grub/unicode.h). The menu shown while Secure Boot is on is drawn with them as well
(payload/sp11-secureboot-theme): a font that lacks one is refused.
"""
import struct
import sys

DRAWN = list(range(0x20, 0x7f)) + [
    0x2190, 0x2191, 0x2192, 0x2193, 0x2195, 0x2500, 0x2501, 0x2502, 0x2503, 0x250c, 0x250f, 0x2510, 0x2513, 0x2514,
    0x2517, 0x2518, 0x251b, 0x25b2, 0x25ba, 0x25bc, 0x25c4]

mode, path = sys.argv[1:]
font = open(path, 'rb').read()
if font[:12] != b'FILE\0\0\0\4PFF2':
    sys.exit(f'{path}: not a PF2 font')

# Sections: a 4-byte name, a 4-byte big-endian length, the body. CHIX holds 9 bytes per glyph (code point, flags,
# file offset); a glyph is width, height, x offset, y offset (of its bottom row, from the baseline), advance and
# the bitmap. DATA is the last section.
head, index, pos = {}, b'', 0
while font[pos:pos + 4] != b'DATA':
    name, size = font[pos:pos + 4], struct.unpack_from('>I', font, pos + 4)[0]
    if name == b'CHIX':
        index = font[pos + 8:pos + 8 + size]
    elif size == 2:
        head[name.decode()] = struct.unpack_from('>H', font, pos + 8)[0]
    pos += 8 + size
glyphs = {}
for i in range(0, len(index), 9):
    code, _, offset = struct.unpack_from('>IBI', index, i)
    glyphs[code] = struct.unpack_from('>HHhhh', font, offset)
missing = [c for c in DRAWN if c not in glyphs]
if missing:
    sys.exit(f'{path}: no glyph for ' + ' '.join(f'U+{c:04X}' for c in missing))
drawn = {c: glyphs[c] for c in DRAWN}

cell_w = max(glyphs[c][4] for c in range(0x20, 0x7f))
cell_h = head['MAXH']
if mode == 'metrics':
    descent = max(0, -min(g[3] for g in drawn.values()))
    print(cell_h - descent, descent)
elif mode == 'check':
    out = []
    for code, (_, h, _, y, _) in sorted(drawn.items()):
        top, bottom = head['ASCE'] - y - h, head['ASCE'] - y
        if top < 0 or bottom > cell_h:
            out.append(f'U+{code:04X} (rows {top}..{bottom - 1})')
    if out:
        sys.exit(f"{path}: rows 0..{cell_h - 1} are the cell (ASCE {head['ASCE']}, DESC {head['DESC']}), outside: "
                 + ', '.join(out))
    print(f'{cell_w}x{cell_h}')
else:
    sys.exit(__doc__)
