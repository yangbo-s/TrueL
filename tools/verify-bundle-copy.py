#!/usr/bin/env python3
"""Compare bundle bytes, executable modes and symlinks without following aliases."""
import hashlib
import os
from pathlib import Path
import stat
import sys


def manifest(root):
    root = Path(root)
    entries = {}
    for directory, folders, files in os.walk(root, followlinks=False):
        for name in folders + files:
            path = Path(directory) / name
            relative = str(path.relative_to(root))
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode):
                entries[relative] = ('link', os.readlink(path))
            elif stat.S_ISREG(mode):
                entries[relative] = ('file', mode & 0o111, hashlib.sha256(path.read_bytes()).hexdigest())
            elif stat.S_ISDIR(mode):
                entries[relative] = ('directory',)
            else:
                raise ValueError(f'Unexpected bundle entry: {relative}')
    return entries


if __name__ == '__main__':
    left, right = map(manifest, sys.argv[1:3])
    changed = sorted(key for key in left.keys() | right.keys() if left.get(key) != right.get(key))
    if changed:
        raise SystemExit('Bundle copy mismatch: ' + ', '.join(changed))
    print(f'PASS identical bundle contents: {len(left)} entries')
