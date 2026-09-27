"""Build the one-shot G-50 generation experiment, not the gameplay mod."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_addon import build_addon  # noqa: E402

NAME = 'mods/tzy/seeker_drone_spawn_probe'
GUID = 'bd86d06b-84e2-4b94-af5e-88f718c87034'
SOURCE = Path(__file__).with_name('spawn_probe.lua')
OUTPUT = ROOT / 'build/seeker_drone/Seeker-Drone-Spawn-Probe.zip'

if __name__ == '__main__':
    print(build_addon(NAME, SOURCE.read_bytes(), GUID, OUTPUT,
                      'Seeker Drone G-50 Spawn Probe'))
