#!/usr/bin/env python3
"""
test_gif.py — Verify GIF structure, dimensions, and palette for a CimBar output.

Usage:
    python tests/test_gif.py path/to/output.gif [expected_size]
    expected_size defaults to 256.

Requires: pip install pillow   (optional but enables frame/palette checks)
"""
import sys
import struct


def test_gif(path, expected_size=256):
    with open(path, 'rb') as f:
        data = f.read()

    # ── GIF89a magic ──────────────────────────────────────────────────────────
    assert data[:6] == b'GIF89a', f'Bad magic: {data[:6]!r}'
    print('  magic GIF89a ✓')

    # ── Logical Screen Descriptor ─────────────────────────────────────────────
    width  = struct.unpack_from('<H', data, 6)[0]
    height = struct.unpack_from('<H', data, 8)[0]
    assert width  == expected_size, f'Width  {width}  != {expected_size}'
    assert height == expected_size, f'Height {height} != {expected_size}'
    print(f'  dimensions {width}×{height} ✓')

    flags = data[10]
    assert flags & 0x80, 'Global color table flag not set'
    print('  global color table flag ✓')

    # ── Pillow-based checks ───────────────────────────────────────────────────
    try:
        from PIL import Image

        img = Image.open(path)

        # Count frames
        frames = 0
        try:
            while True:
                frames += 1
                img.seek(img.tell() + 1)
        except EOFError:
            pass
        assert frames > 0, 'No frames found'
        print(f'  frames: {frames} ✓')

        # Palette must have ≥ 8 entries (one per CimBar color)
        img.seek(0)
        pal = img.getpalette()
        assert pal is not None, 'No palette'
        n_entries = len(pal) // 3
        assert n_entries >= 8, f'Palette too small: {n_entries} entries'
        print(f'  palette: {n_entries} entries ✓')

        # Verify palette slots 0-7 match the 8 CimBar base colors
        EXPECTED = [
            (  0, 200, 200),
            (220,  40,  40),
            ( 30, 100, 220),
            (255, 130,  20),
            (200,  40, 200),
            ( 40, 200,  60),
            (230, 220,  40),
            (100,  20, 200),
        ]
        for i, (er, eg, eb) in enumerate(EXPECTED):
            r, g, b = pal[i*3], pal[i*3+1], pal[i*3+2]
            assert (r, g, b) == (er, eg, eb), (
                f'Palette slot {i}: got ({r},{g},{b}), expected ({er},{eg},{eb})'
            )
        print('  CimBar base palette entries ✓')

    except ImportError:
        print('  (Pillow not installed — skipping frame/palette checks)')

    return True


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: test_gif.py <gif_path> [expected_size]')
        sys.exit(1)

    path = sys.argv[1]
    size = int(sys.argv[2]) if len(sys.argv) > 2 else 256

    try:
        test_gif(path, size)
        print('PASS: GIF structure valid')
        sys.exit(0)
    except AssertionError as e:
        print(f'FAIL: {e}')
        sys.exit(1)
    except FileNotFoundError:
        print(f'FAIL: File not found: {path}')
        sys.exit(1)
