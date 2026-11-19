#!/usr/bin/env python3
"""Compile a Rime wubi86 dictionary (dict.yaml) into the compact binary
format consumed by WubiCore at runtime.

Format (little endian):
    magic     4s   b"WUB1"
    version   u32
    entries   u32   number of candidate records
    keys      u32   number of distinct codes
    blobSize  u32   utf-8 string blob size
    reserved  u32
    keys      keys * u32      packed code, ascending
    index     keys * (u32 offset, u32 count)   slice into records
    records   entries * 8B    (u32 strOffset, u16 weight, u8 len, u8 flags)
    blob      blobSize bytes  concatenated utf-8 strings

Codes are packed base-27, four digits, 'a'..'z' -> 1..26, missing -> 0.
That keeps lexicographic order == numeric order, so prefix ranges are
contiguous and can be located with a binary search.

Usage: build_dict.py <wubi86.dict.yaml> <out.bin>
"""
import math
import os
import re
import struct
import sys
from collections import defaultdict

LETTERS = "abcdefghijklmnopqrstuvwxyz"
DIGIT = {ch: i + 1 for i, ch in enumerate(LETTERS)}


def pack(code: str) -> int:
    value = 0
    for i in range(4):
        d = DIGIT.get(code[i], 0) if i < len(code) else 0
        value = value * 27 + d
    return value


def unpack(value: int) -> str:
    digits = []
    for _ in range(4):
        value, d = divmod(value, 27)
        digits.append(d)
    digits.reverse()
    return "".join(LETTERS[d - 1] if d else "" for d in digits)


def parse_yaml_body(path: str):
    """Yield (text, code, weight, is_simple) skipping metadata and comments."""
    started = False
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            line = raw.rstrip("\n")
            if not started:
                if line.strip() == "...":
                    started = True
                continue
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 2:
                continue
            text = parts[0].strip()
            code = parts[1].strip()
            if not text or not re.fullmatch(r"[a-z]{1,4}", code):
                continue
            weight = 0
            if len(parts) >= 3 and parts[2].strip():
                try:
                    weight = float(parts[2])
                except ValueError:
                    weight = 0
            is_simple = len(parts) >= 4
            yield text, code, weight, is_simple


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    src, dst = sys.argv[1], sys.argv[2]

    buckets = defaultdict(list)
    seen = set()
    for text, code, weight, is_simple in parse_yaml_body(src):
        key = (text, code)
        if key in seen:
            continue
        seen.add(key)
        buckets[pack(code)].append((text, weight, is_simple))

    # Normalise weights on a log scale so ranking survives compression to u16.
    weights = [w for items in buckets.values() for _, w, _ in items if w > 0]
    lo = math.log1p(min(weights)) if weights else 0.0
    hi = math.log1p(max(weights)) if weights else 1.0
    span = max(hi - lo, 1e-9)

    keys = sorted(buckets)
    records = bytearray()
    blob = bytearray()
    index = bytearray()

    for key in keys:
        items = buckets[key]
        # Pre-sort by weight desc; simple-code entries first on ties so that
        # 一级/二级简码 stay on top of full codes with the same frequency.
        items.sort(key=lambda it: (-it[1], -int(it[2])))
        offset = len(records) // 8
        for text, weight, is_simple in items:
            data = text.encode("utf-8")
            if weight > 0:
                norm = (math.log1p(weight) - lo) / span
                w16 = max(1, min(65535, int(round(norm * 65535))))
            else:
                w16 = 1
            flags = (1 if len(text) > 1 else 0) | (2 if is_simple else 0)
            records += struct.pack("<IHBB", len(blob), w16, len(data), flags)
            blob += data
        index += struct.pack("<II", offset, len(items))

    # 20 byte header: magic, version, entry count, key count, blob size.
    header = struct.pack(
        "<4sIIII",
        b"WUB1",
        1,
        len(records) // 8,
        len(keys),
        len(blob),
    )
    with open(dst, "wb") as out:
        out.write(header)
        out.write(struct.pack("<%dI" % len(keys), *keys))
        out.write(index)
        out.write(records)
        out.write(blob)

    size = os.path.getsize(dst)
    print(
        f"codes={len(keys):,}  entries={len(records)//8:,}  "
        f"blob={len(blob):,}B  file={size/1024/1024:.2f}MB  -> {dst}"
    )
    # A couple of sanity samples for CI logs.
    for probe in ("wqiy", "trnt", "jghu", "rqyy", "g", "wq"):
        print(f"  {probe:<5} -> {[t for t, _, _ in buckets.get(pack(probe), [])][:4]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
