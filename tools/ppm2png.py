#!/usr/bin/env python3
"""Convert the LVGL preview PPM (P6, 8-bit RGB) to PNG without extra deps."""
import struct
import sys
import zlib


def chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def main(src, dst):
    raw = open(src, "rb").read()
    parts = raw.split(b"\n", 3)
    assert parts[0] == b"P6", "only binary PPM (P6) is supported"
    w, h = map(int, parts[1].split())
    assert parts[2].strip() == b"255"
    pixels = parts[3]
    stride = w * 3
    scanlines = b"".join(b"\x00" + pixels[y * stride:(y + 1) * stride] for y in range(h))
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(scanlines, 9))
           + chunk(b"IEND", b""))
    open(dst, "wb").write(png)
    print("wrote %s (%dx%d)" % (dst, w, h))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
