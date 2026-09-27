"""Synthetic checks for the read-only native weapon-index decoder."""

import importlib.util
from pathlib import Path
import struct
import unittest


SOURCE = Path(__file__).resolve().parents[1] / 'tools' / 'read_spawn_ring.py'
SPEC = importlib.util.spec_from_file_location('read_spawn_ring', SOURCE)
ring = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ring)


class RuntimeLookupTest(unittest.TestCase):
    def setUp(self):
        self.base, self.manager, self.table = 0x10000000, 0x20000000, 0x30000000
        self.store, self.slots, self.records = 0x40000000, 0x50000000, 0x60000000
        self.instance_id, self.slot = 123, 7
        self.memory = {}
        self.put(self.manager + ring.RING_DATA_OFFSET + self.slot * ring.RECORD_SIZE,
                 struct.pack('<QIIII', ring.GUARD_DOG_WEAPON, self.instance_id,
                             0, 1, 1))
        self.put(self.manager + 0xF12E80, struct.pack('<Q', self.table))
        bucket = ring.GUARD_DOG_WEAPON % ring.RAW_WEAPON_MAP_SLOTS
        self.put(self.table + bucket * 16,
                 struct.pack('<QI', ring.GUARD_DOG_WEAPON,
                             ring.GUARD_DOG_RECORD_INDEX))
        self.put(self.table + 0x21E0 + ring.GUARD_DOG_RECORD_INDEX * 616,
                 bytes(616))
        self.put(self.base + ring.INVALID_INSTANCE_RVA, struct.pack('<I', 0))
        self.put(self.base + ring.RUNTIME_WEAPON_STORE_RVA,
                 struct.pack('<Q', self.store))
        metadata = bytearray(0x48)
        struct.pack_into('<QIII', metadata, 0, self.slots, 8, 0xFFFFFFFF, 3)
        struct.pack_into('<I', metadata, 0x38, 2)
        struct.pack_into('<Q', metadata, 0x40, self.records)
        self.put(self.store + 0x90, bytes(metadata))
        for index in range(8):
            self.put(self.slots + index * 8,
                     struct.pack('<II', 0xFFFFFFFF, 0xFFFFFFFF))

    def put(self, address, value):
        self.memory[address] = value

    def read(self, address, size):
        value = self.memory[address]
        if len(value) != size:
            raise AssertionError((address, size, len(value)))
        return value

    def lookup(self):
        return ring.guard_dog_runtime(self.read, self.base, self.manager,
                                      self.slot, self.instance_id)

    def test_runtime_hit_and_raw_fallback(self):
        start = self.instance_id * 3 & 7
        self.put(self.slots + start * 8, struct.pack('<II', self.instance_id, 1))
        runtime = bytearray(616)
        struct.pack_into('<Q', runtime, 0x28, 0x2D398D1EC35E0838)
        self.put(self.records + 616, bytes(runtime))
        hit = self.lookup()
        self.assertTrue(hit['override'])
        self.assertEqual(hit['projectile_entity'], '0x2d398d1ec35e0838')
        self.put(self.slots + start * 8,
                 struct.pack('<II', 0xFFFFFFFF, 0xFFFFFFFF))
        self.assertFalse(self.lookup()['override'])

    def test_rejects_concurrent_record_change(self):
        original = self.read
        address = self.manager + ring.RING_DATA_OFFSET + self.slot * ring.RECORD_SIZE
        calls = 0

        def changing_read(pointer, size):
            nonlocal calls
            if pointer == address:
                calls += 1
                if calls == 2:
                    value = bytearray(self.memory[address])
                    struct.pack_into('<I', value, 8, 124)
                    self.put(address, bytes(value))
            return original(pointer, size)

        with self.assertRaisesRegex(RuntimeError, 'changed during read'):
            ring.guard_dog_runtime(changing_read, self.base, self.manager,
                                   self.slot, self.instance_id)


if __name__ == '__main__':
    unittest.main()
