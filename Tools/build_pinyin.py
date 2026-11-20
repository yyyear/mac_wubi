#!/usr/bin/env python3
"""Regenerate the built-in full-pinyin TSV offline, or compare it with --check."""
import argparse
import gzip
import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / 'pinyin' / 'pinyin_simp.dict.yaml.gz'
EXTRA = ROOT / 'pinyin' / 'extra.tsv'
OUTPUT = ROOT.parent / 'Sources/WubiCore/Resources/pinyin.tsv'
SHA256 = 'e341598343a0f0f2035bb1aafc34a7f3bb7887deeecb3f60796262aaa2983e6b'


def generate():
    raw = gzip.decompress(SOURCE.read_bytes())
    if hashlib.sha256(raw).hexdigest() != SHA256:
        raise ValueError('upstream dictionary hash mismatch')
    _, sep, body = raw.decode('utf-8').partition('\n...\n')
    if not sep:
        raise ValueError('missing end of Rime header')
    pairs = {}
    for lines in (body, EXTRA.read_text(encoding='utf-8')):
        for line in lines.splitlines():
            if not line or line.startswith('#'):
                continue
            word, reading, weight = line.split('\t')
            syllables = reading.replace('ü', 'v').split()
            weight = int(weight)
            if (not re.fullmatch(r'[〇\u3400-\u9fff]+', word) or weight < 0
                    or not syllables or not all(re.fullmatch('[a-z]+', s) for s in syllables)):
                raise ValueError(f'invalid input: {line}')
            # Preserve the source spelling and accept the keyboard v spelling.
            codes = {''.join(syllables), ''.join({'lue': 'lve', 'nue': 'nve'}.get(s, s) for s in syllables)}
            for code in codes:
                key = (code, word)
                pairs[key] = max(weight, pairs.get(key, 0))

    # Dense ranks preserve distinct frequencies without clipping common words.
    ranks = {n: i for i, n in enumerate(sorted(set(pairs.values())), 1)}
    if len(ranks) > 65535:
        raise ValueError('too many distinct frequencies for UInt16')
    ordered = sorted(pairs, key=lambda k: (k[0], -pairs[k], k[1]))
    return ''.join(f'{code}\t{word}\t{ranks[pairs[code, word]]}\n' for code, word in ordered).encode('utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='do not write; fail on a byte difference')
    args = parser.parse_args()
    data = generate()
    if args.check:
        if data != OUTPUT.read_bytes():
            raise SystemExit('pinyin.tsv differs from generated data')
    else:
        OUTPUT.write_bytes(data)
    print(f'{len(data.splitlines())} records, {len(data)} bytes, sha256 {hashlib.sha256(data).hexdigest()}')
