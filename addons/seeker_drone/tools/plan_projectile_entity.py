"""Validate a current-build weapon component table and report candidate patch bytes.

This is an offline planner. It never writes to the input file or game process.
The proposed G-50 field replacement has not been tested in-game.
"""

import argparse
import hashlib
from pathlib import Path
import struct


ORIGINAL_SHA256 = '7648d8dbe9d0fe91693ee8608a5ce09a425f8436d86f986772a09d224ae1d510'
TABLE_SIZE = 28 + 176224
MAP_OFFSET = 28 + 6608
RECORD_INDEX = 188
RECORD_OFFSET = 28 + 8672 + RECORD_INDEX * 616
PROJECTILE_ENTITY_OFFSET = RECORD_OFFSET + 40
MG_WEAPON_HASH = 0xA32621E3BDE13379
G50_HASH = 0x2D398D1EC35E0838


def plan(data: bytes) -> dict:
    if len(data) != TABLE_SIZE:
        raise ValueError(f'expected {TABLE_SIZE} bytes, got {len(data)}')
    digest = hashlib.sha256(data).hexdigest()
    if digest != ORIGINAL_SHA256:
        raise ValueError('component table differs from verified current build')
    if data[:8] != bytes.fromhex('681b17454c444c44'):
        raise ValueError('unexpected DL instance header')
    resource, index = struct.unpack_from('<QI', data, MAP_OFFSET)
    if resource != MG_WEAPON_HASH or index != RECORD_INDEX:
        raise ValueError('machine-gun Guard Dog index entry differs')
    if data[PROJECTILE_ENTITY_OFFSET:PROJECTILE_ENTITY_OFFSET + 8] != bytes(8):
        raise ValueError('ProjectileEntity is not zero')
    modified = bytearray(data)
    replacement = struct.pack('<Q', G50_HASH)
    modified[PROJECTILE_ENTITY_OFFSET:PROJECTILE_ENTITY_OFFSET + 8] = replacement
    return {
        'original_sha256': digest,
        'candidate_sha256': hashlib.sha256(modified).hexdigest(),
        'field_offset_from_dl_instance': PROJECTILE_ENTITY_OFFSET,
        'before_hex': bytes(8).hex(),
        'candidate_after_hex': replacement.hex(),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('table', type=Path, help='verified DL instance bytes')
    args = parser.parse_args()
    for key, value in plan(args.table.read_bytes()).items():
        print(f'{key}={value}')


if __name__ == '__main__':
    main()
