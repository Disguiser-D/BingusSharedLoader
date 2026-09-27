"""Build the guarded one-shot G-50 entity experiment."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_addon import build_addon  # noqa: E402

NAME = 'mods/tzy/seeker_drone_entity_probe'
GUID = 'ac4c0643-3f52-4f61-a723-6cde03ec4417'
SOURCE = Path(__file__).with_name('entity_probe.lua')
OUTPUT = ROOT / 'build/seeker_drone/Seeker-Drone-Entity-Probe.zip'


if __name__ == '__main__':
    print(build_addon(NAME, SOURCE.read_bytes(), GUID, OUTPUT,
                      'Seeker Drone G-50 Entity Probe'))
