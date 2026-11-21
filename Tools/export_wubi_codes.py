#!/usr/bin/env python3
"""Export text<TAB>full code rows from the shipped WUB1 dictionary.

Usage: python3 Tools/export_wubi_codes.py Sources/WubiCore/Resources/wubi86.bin
Writes wubi86-reverse.tsv next to the input; rerun when replacing the dictionary.
"""
import struct
import sys
from pathlib import Path


def export(source):
    data = source.read_bytes()
    magic, version, entries, keys, blob_size = struct.unpack_from("<4sIIII", data)
    records = 20 + keys * 12
    blob = records + entries * 8
    if (magic, version, len(data)) != (b"WUB1", 1, blob + blob_size):
        raise ValueError("not a WUB1 dictionary")
    codes = {}
    for slot in range(keys):
        packed, = struct.unpack_from("<I", data, 20 + slot * 4)
        digits = []
        for _ in range(4):
            packed, digit = divmod(packed, 27)
            if digit:
                digits.append(digit + 96)
        code = bytes(reversed(digits))
        # z is reserved for special groups (e.g. zzpp for radicals), not a root.
        if b"z" in code:
            continue
        offset, count = struct.unpack_from("<II", data, 20 + keys * 4 + slot * 8)
        for record in range(offset, offset + count):
            pos, _, length, flags = struct.unpack_from("<IHBB", data, records + record * 8)
            if flags & 2:  # explicitly marked shorthand
                continue
            text = data[blob + pos:blob + pos + length]
            # Longest attested spelling; ties retain the first code (key order).
            # Some characters have genuine three-key full spellings, e.g. 了 bnh.
            if len(code) > len(codes.get(text, b"")):
                codes[text] = code
    with source.with_name(source.stem + "-reverse.tsv").open("wb") as handle:
        for text, code in sorted(codes.items()):
            handle.write(text + b"\t" + code + b"\n")


if __name__ == "__main__":
    export(Path(sys.argv[1]))
