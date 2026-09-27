"""Read recent native entity-creation records without modifying the game.

Run on the Windows computer hosting the supported Helldivers 2 build. This
diagnostic only opens the process for query/read access and prints JSON lines.
It does not call game functions, inject code, or alter game files or memory.
"""

import argparse
import ctypes as C
import hashlib
import json
import struct
import subprocess
import time


EXPECTED_TIMESTAMP = 0x6AB3B43F
EXPECTED_IMAGE_SIZE = 0x04744000
MANAGER_POINTER_RVA = 0x346BF98
RING_NEXT_OFFSET = 0xF32F14
RING_DATA_OFFSET = 0xF32F18
RING_SLOTS = 0x800
RECORD_SIZE = 24
SEEKERS = {
    0x2D398D1EC35E0838: 'g50',
    0x8E325C933E55BF62: 'g60',
}
GUARD_DOG_WEAPON = 0xA32621E3BDE13379
RUNTIME_WEAPON_STORE_RVA = 0x33266D8
INVALID_INSTANCE_RVA = 0x3483C24
WEAPON_RECORD_SIZE = 616
GUARD_DOG_RECORD_INDEX = 188
RAW_WEAPON_MAP_SLOTS = 542


def game_pid():
    output = subprocess.check_output(
        ['powershell', '-NoProfile', '-Command',
         '(Get-Process helldivers2 -ErrorAction Stop).Id'],
        text=True, stderr=subprocess.DEVNULL).strip()
    ids = output.splitlines()
    if len(ids) != 1:
        raise RuntimeError(f'expected one game process, found {len(ids)}')
    return int(ids[0])


def process_reader(pid=None):
    kernel = C.WinDLL('kernel32', use_last_error=True)
    psapi = C.WinDLL('psapi', use_last_error=True)
    kernel.OpenProcess.argtypes = (C.c_uint32, C.c_int, C.c_uint32)
    kernel.OpenProcess.restype = C.c_void_p
    kernel.CloseHandle.argtypes = (C.c_void_p,)
    kernel.ReadProcessMemory.argtypes = (
        C.c_void_p, C.c_void_p, C.c_void_p, C.c_size_t,
        C.POINTER(C.c_size_t))
    psapi.EnumProcessModulesEx.argtypes = (
        C.c_void_p, C.POINTER(C.c_void_p), C.c_uint32,
        C.POINTER(C.c_uint32), C.c_uint32)
    psapi.GetModuleBaseNameW.argtypes = (
        C.c_void_p, C.c_void_p, C.c_wchar_p, C.c_uint32)
    handle = kernel.OpenProcess(0x0410, 0, pid or game_pid())
    if not handle:
        raise RuntimeError(f'OpenProcess failed: {C.get_last_error()}')

    def read(address, size):
        buffer, count = C.create_string_buffer(size), C.c_size_t()
        ok = kernel.ReadProcessMemory(handle, C.c_void_p(address), buffer,
                                      size, C.byref(count))
        if not ok or count.value != size:
            raise RuntimeError(f'ReadProcessMemory failed: {C.get_last_error()}')
        return buffer.raw

    try:
        modules = (C.c_void_p * 1024)()
        used = C.c_uint32()
        if not psapi.EnumProcessModulesEx(handle, modules, C.sizeof(modules),
                                          C.byref(used), 3):
            raise RuntimeError('EnumProcessModulesEx failed')
        base = None
        for module in modules[:used.value // C.sizeof(C.c_void_p)]:
            name = C.create_unicode_buffer(260)
            if (psapi.GetModuleBaseNameW(handle, module, name, 260)
                    and name.value.lower() == 'game.dll'):
                base = module
                break
        if base is None:
            raise RuntimeError('game.dll is not loaded')
        header = read(base, 0x1000)
        pe = struct.unpack_from('<I', header, 0x3C)[0]
        if (header[:2] != b'MZ' or header[pe:pe+4] != b'PE\0\0'
                or struct.unpack_from('<I', header, pe+8)[0] != EXPECTED_TIMESTAMP
                or struct.unpack_from('<I', header, pe+24+56)[0] != EXPECTED_IMAGE_SIZE):
            raise RuntimeError('unsupported game.dll build')
        yield read, base
    finally:
        kernel.CloseHandle(handle)


def records(buffer, include_guard_dog=False):
    for slot in range(RING_SLOTS):
        resource, instance_id, word_0c, word_10, flag_14 = struct.unpack_from(
            '<QIIII', buffer, slot * RECORD_SIZE)
        kind = SEEKERS.get(resource)
        if include_guard_dog and resource == GUARD_DOG_WEAPON:
            kind = 'guard_dog_weapon'
        if kind:
            yield (slot, kind, instance_id, word_0c, word_10, flag_14)


def guard_dog_runtime(read, base, entity_manager, slot, instance_id):
    """Inspect the versioned 0x515100 override lookup without calling it."""
    entity_address = entity_manager + RING_DATA_OFFSET + slot * RECORD_SIZE
    entity_before = read(entity_address, RECORD_SIZE)
    if struct.unpack_from('<QI', entity_before) != (GUARD_DOG_WEAPON, instance_id):
        raise RuntimeError('Guard Dog weapon record changed before lookup')
    table = struct.unpack('<Q', read(entity_manager + 0xF12E80, 8))[0]
    if not table:
        raise RuntimeError('projectile weapon table unavailable')
    for probe in range(RAW_WEAPON_MAP_SLOTS):
        bucket = (GUARD_DOG_WEAPON % RAW_WEAPON_MAP_SLOTS + probe) % RAW_WEAPON_MAP_SLOTS
        raw_key, raw_index = struct.unpack('<QI', read(table + bucket * 16, 12))
        if raw_key == GUARD_DOG_WEAPON:
            if raw_index != GUARD_DOG_RECORD_INDEX:
                raise RuntimeError('Guard Dog weapon raw index changed')
            break
        if raw_key == 0:
            raise RuntimeError('Guard Dog weapon absent from raw index')
    else:
        raise RuntimeError('Guard Dog weapon raw index full without match')
    raw_record_address = table + 0x21E0 + raw_index * WEAPON_RECORD_SIZE
    raw_record = read(raw_record_address, WEAPON_RECORD_SIZE)
    raw_projectile = struct.unpack_from('<Q', raw_record, 0x28)[0]
    invalid_id = struct.unpack('<I', read(base + INVALID_INSTANCE_RVA, 4))[0]
    report = {'event': 'guard_dog_runtime', 'instance_id': instance_id,
              'raw_projectile_entity': f'{raw_projectile:#018x}',
              'raw_table_address': f'{table:#018x}',
              'raw_record_address': f'{raw_record_address:#018x}',
              'raw_field_address': f'{raw_record_address + 0x28:#018x}',
              'override': False}
    store = struct.unpack('<Q', read(base + RUNTIME_WEAPON_STORE_RVA, 8))[0]
    validation = []
    if instance_id != invalid_id and store:
        metadata = read(store + 0x90, 0x48)
        slots = struct.unpack_from('<Q', metadata, 0)[0]
        count, sentinel, multiplier = struct.unpack_from('<III', metadata, 8)
        used = struct.unpack_from('<I', metadata, 0x38)[0]
        record_base = struct.unpack_from('<Q', metadata, 0x40)[0]
        if not count or count > 65536 or count & (count - 1):
            raise RuntimeError('runtime weapon index size invalid')
        if not slots:
            raise RuntimeError('runtime weapon index pointer missing')
        start = (instance_id * multiplier & 0xFFFFFFFF) & (count - 1)
        for probe in range(count):
            lookup_slot = (start + probe) & (count - 1)
            index_address = slots + lookup_slot * 8
            entry = read(index_address, 8)
            validation.append((index_address, entry))
            key, index = struct.unpack('<II', entry)
            if key == instance_id:
                if index == 0xFFFFFFFF:
                    break
                if index >= used or used > 65536:
                    raise RuntimeError('runtime weapon record index invalid')
                if not record_base:
                    raise RuntimeError('runtime weapon records pointer missing')
                record_address = record_base + index * WEAPON_RECORD_SIZE
                record = read(record_address, WEAPON_RECORD_SIZE)
                report.update({'override': True, 'record_index': index,
                               'projectile_entity':
                               f'{struct.unpack_from("<Q", record, 0x28)[0]:#018x}',
                               'record_sha256': hashlib.sha256(record).hexdigest()})
                validation.append((record_address, record))
                break
            if key == sentinel:
                break
        if read(store + 0x90, 0x48) != metadata:
            raise RuntimeError('runtime weapon store changed during lookup')
    if (read(entity_address, RECORD_SIZE) != entity_before
            or read(entity_manager + 0xF12E80, 8) != struct.pack('<Q', table)
            or read(table + bucket * 16, 12) != struct.pack('<QI', raw_key, raw_index)
            or read(raw_record_address, WEAPON_RECORD_SIZE) != raw_record
            or read(base + RUNTIME_WEAPON_STORE_RVA, 8) != struct.pack('<Q', store)
            or any(read(address, len(value)) != value
                   for address, value in validation)):
        raise RuntimeError('Guard Dog weapon lookup changed during read')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds', type=float, default=0,
                        help='poll duration after the first successful read')
    parser.add_argument('--interval', type=float, default=0.25,
                        help='poll interval in seconds')
    parser.add_argument('--guard-dog-runtime', action='store_true',
                        help='also inspect active Guard Dog weapon overrides')
    parser.add_argument('--pid', type=int,
                        help='specific game process ID when more than one exists')
    args = parser.parse_args()
    if not 0 <= args.seconds <= 300 or not 0.1 <= args.interval <= 5:
        parser.error('duration or interval out of range')
    if args.pid is not None and args.pid <= 0:
        parser.error('PID must be positive')
    for read, base in process_reader(args.pid):
        previous = {}
        changes = 0
        start = time.monotonic()
        ready = False
        inspected_weapons = set()
        while True:
            manager = struct.unpack('<Q', read(base + MANAGER_POINTER_RVA, 8))[0]
            if manager:
                next_slot = struct.unpack('<I', read(manager + RING_NEXT_OFFSET, 4))[0]
                if next_slot >= RING_SLOTS:
                    raise RuntimeError('entity ring index out of range')
                ring = read(manager + RING_DATA_OFFSET, RING_SLOTS * RECORD_SIZE)
                initial = not ready
                if initial:
                    print(json.dumps({'event': 'ready', 'next_slot': next_slot}),
                          flush=True)
                    ready = True
                current = {}
                for slot, kind, instance_id, word_0c, word_10, flag_14 in records(
                        ring, args.guard_dog_runtime):
                    signature = (kind, instance_id, word_10, flag_14)
                    current[slot] = signature
                    if previous.get(slot) != signature:
                        changes += 1
                        print(json.dumps({
                            'event': 'record_change',
                            'elapsed': round(time.monotonic() - start, 2),
                            'kind': kind, 'slot': slot,
                            'instance_id': instance_id,
                            'word_0c': word_0c, 'word_10': word_10,
                            'flag_14': flag_14,
                            'initial': initial,
                        }), flush=True)
                    if (kind == 'guard_dog_weapon' and instance_id
                            and instance_id not in inspected_weapons):
                        try:
                            report = guard_dog_runtime(
                                read, base, manager, slot, instance_id)
                        except RuntimeError as error:
                            print(json.dumps({'event': 'lookup_retry',
                                              'instance_id': instance_id,
                                              'reason': str(error)}), flush=True)
                        else:
                            inspected_weapons.add(instance_id)
                            print(json.dumps(report), flush=True)
                for slot in previous.keys() - current.keys():
                    changes += 1
                    print(json.dumps({'event': 'slot_lost', 'slot': slot,
                                      'elapsed': round(time.monotonic() - start, 2)}),
                          flush=True)
                previous = current
            if time.monotonic() - start >= args.seconds:
                break
            time.sleep(args.interval)
        print(json.dumps({'event': 'complete', 'ready': ready,
                          'record_changes': changes}), flush=True)


if __name__ == '__main__':
    main()
