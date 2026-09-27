"""Build the read-only game.dll resource-hash locator."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_addon import build_addon  # noqa: E402

NAME = 'mods/tzy/seeker_drone_memory_probe'
GUID = '6b89bf5d-d971-4fb3-b608-09d719015077'
SOURCE = Path(__file__).with_name('memory_probe.lua')
OUTPUT = ROOT / 'build/seeker_drone/Seeker-Drone-Memory-Probe.zip'

if __name__ == '__main__':
    print(build_addon(NAME, SOURCE.read_bytes(), GUID, OUTPUT,
                      'Seeker Drone Read-Only Memory Probe'))
