#!/usr/bin/env python3
"""Packs PNG files into a Windows .ico (PNG-compressed entries). Stdlib only.
Usage: make-ico.py out.ico a.png b.png ..."""
import struct, sys

def main(out, pngs):
    entries = []
    for path in pngs:
        data = open(path, "rb").read()
        # width/height from IHDR (bytes 16..24)
        w, h = struct.unpack(">II", data[16:24])
        entries.append((w, h, data))
    header = struct.pack("<HHH", 0, 1, len(entries))
    offset = len(header) + 16 * len(entries)
    dir_entries, blobs = b"", b""
    for w, h, data in entries:
        dir_entries += struct.pack("<BBBBHHII", w if w < 256 else 0, h if h < 256 else 0,
                                   0, 0, 1, 32, len(data), offset)
        blobs += data
        offset += len(data)
    with open(out, "wb") as f:
        f.write(header + dir_entries + blobs)
    print(f"wrote {out} ({len(entries)} sizes)")

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
