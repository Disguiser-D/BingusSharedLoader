"""Build the read-only runtime probe; this is not the gameplay mod."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_addon import build_addon  # noqa: E402

NAME = 'mods/tzy/seeker_drone_probe'
GUID = '86b96475-23dc-45a0-a5f7-4a4faecd76a7'
SOURCE = Path(__file__).with_name('probe.lua')
OUTPUT = ROOT / 'build/seeker_drone/Seeker-Drone-Probe.zip'


if __name__ == '__main__':
    print(build_addon(NAME, SOURCE.read_bytes(), GUID, OUTPUT,
                      'Seeker Drone Runtime Probe'))
