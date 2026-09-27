"""Read recent native entity-creation records without modifying the game.

Run on the Windows computer hosting the supported Helldivers 2 build. This
diagnostic only opens the process for query/read access and prints JSON lines.
It does not call game functions, inject code, or alter game files or memory.
"""

import argparse
import ctypes as C
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


def game_pid():
    output = subprocess.check_output(
        ['powershell', '-NoProfile', '-Command',
         '(Get-Process helldivers2 -ErrorAction Stop).Id'],
        text=True, stderr=subprocess.DEVNULL).strip()
    ids = output.splitlines()
    if len(ids) != 1:
        raise RuntimeError(f'expected one game process, found {len(ids)}')
    return int(ids[0])


def process_reader():
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
    handle = kernel.OpenProcess(0x0410, 0, game_pid())
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


def records(buffer):
    for slot in range(RING_SLOTS):
        resource, instance_id, word_0c, word_10, flag_14 = struct.unpack_from(
            '<QIIII', buffer, slot * RECORD_SIZE)
        kind = SEEKERS.get(resource)
        if kind:
            yield (slot, kind, instance_id, word_0c, word_10, flag_14)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds', type=float, default=0,
                        help='poll duration after the first successful read')
    parser.add_argument('--interval', type=float, default=0.25,
                        help='poll interval in seconds')
    args = parser.parse_args()
    if not 0 <= args.seconds <= 300 or not 0.1 <= args.interval <= 5:
        parser.error('duration or interval out of range')
    for read, base in process_reader():
        previous = {}
        changes = 0
        start = time.monotonic()
        ready = False
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
                for slot, kind, instance_id, word_0c, word_10, flag_14 in records(ring):
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
