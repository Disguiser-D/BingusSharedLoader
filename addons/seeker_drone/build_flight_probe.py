"""Build the read-only G-50 flight-state probe."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_addon import build_addon  # noqa: E402

NAME = 'mods/tzy/seeker_drone_flight_probe'
GUID = '1ee9dd35-70a7-41b4-9e9a-8e03332ed694'
SOURCE = Path(__file__).with_name('flight_probe.lua')
OUTPUT = ROOT / 'build/seeker_drone/Seeker-Drone-Flight-Probe.zip'

if __name__ == '__main__':
    print(build_addon(NAME, SOURCE.read_bytes(), GUID, OUTPUT,
                      'Seeker Drone Read-Only Flight Probe'))
