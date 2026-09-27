"""Build the read-only API inventory probe; not the gameplay mod."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_addon import build_addon  # noqa: E402

NAME = 'mods/tzy/seeker_drone_api_probe'
GUID = 'e9d1503c-d759-40d8-b810-b46bb2d983e9'
SOURCE = Path(__file__).with_name('api_probe.lua')
OUTPUT = ROOT / 'build/seeker_drone/Seeker-Drone-API-Probe.zip'


if __name__ == '__main__':
    print(build_addon(NAME, SOURCE.read_bytes(), GUID, OUTPUT,
                      'Seeker Drone Read-Only API Probe'))
