"""Validate current-build decoded weapon data and report candidate patch bytes.

This is an offline planner. It never writes to the input file or game process.
The proposed G-50 field replacement has not been tested in-game. The game's
installed generated_entities.dl_bin has a separate, unverified encoding; this
tool accepts decoded data only and does not create an installable replacement.
"""

import argparse
import hashlib
from pathlib import Path
import struct


ORIGINAL_SHA256 = '7648d8dbe9d0fe91693ee8608a5ce09a425f8436d86f986772a09d224ae1d510'
FULL_SHA256 = '21377252b81fdbc670eba1e59a8ab64b170323df208f175e708992e4c1fb515e'
FULL_SIZE = 46612588
FULL_COMPONENT_OFFSET = 46404840
EXPECTED_CONTENT_HASH = 0xEBFD607F348CFC7F
CONTENT_HASH_SEED = 0xDEADBEEFABAD1DEA
TABLE_SIZE = 28 + 176224
MAP_OFFSET = 28 + 6608
RECORD_INDEX = 188
RECORD_OFFSET = 28 + 8672 + RECORD_INDEX * 616
PROJECTILE_ENTITY_OFFSET = RECORD_OFFSET + 40
MG_WEAPON_HASH = 0xA32621E3BDE13379
G50_HASH = 0x2D398D1EC35E0838


def murmur64a(data: bytes, seed: int) -> int:
    mask, mix = (1 << 64) - 1, 0xC6A4A7935BD1E995
    value = (seed ^ (len(data) * mix)) & mask
    end = len(data) // 8 * 8
    for (word,) in struct.iter_unpack('<Q', data[:end]):
        word = word * mix & mask
        word ^= word >> 47
        value = (value ^ (word * mix & mask)) * mix & mask
    if data[end:]:
        value = (value ^ int.from_bytes(data[end:], 'little')) * mix & mask
    value ^= value >> 47
    value = value * mix & mask
    return value ^ (value >> 47)


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


def plan_full(data: bytes) -> dict:
    if len(data) != FULL_SIZE or hashlib.sha256(data).hexdigest() != FULL_SHA256:
        raise ValueError('decoded generated_entities.dl_bin differs from verified snapshot')
    actual_content_hash = murmur64a(data, CONTENT_HASH_SEED)
    if actual_content_hash != EXPECTED_CONTENT_HASH:
        raise ValueError('game-side expected content hash differs')
    component = data[FULL_COMPONENT_OFFSET:FULL_COMPONENT_OFFSET + TABLE_SIZE]
    component_plan = plan(component)
    modified = bytearray(data)
    field_offset = FULL_COMPONENT_OFFSET + PROJECTILE_ENTITY_OFFSET
    modified[field_offset:field_offset + 8] = struct.pack('<Q', G50_HASH)
    return {
        **component_plan,
        'decoded_full_sha256': FULL_SHA256,
        'original_game_content_hash': f'{actual_content_hash:016x}',
        'candidate_game_content_hash': f'{murmur64a(modified, CONTENT_HASH_SEED):016x}',
        'field_offset_from_decoded_file': field_offset,
        'candidate_decoded_full_sha256': hashlib.sha256(modified).hexdigest(),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('table', type=Path, help='verified DL instance bytes')
    parser.add_argument('--decoded-full', action='store_true',
                        help='input is the complete decoded generated_entities.dl_bin snapshot')
    args = parser.parse_args()
    planner = plan_full if args.decoded_full else plan
    for key, value in planner(args.table.read_bytes()).items():
        print(f'{key}={value}')


if __name__ == '__main__':
    main()
