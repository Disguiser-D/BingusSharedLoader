"""Build a menu-only, read-only LuaJIT function-address probe."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_addon import build_addon  # noqa: E402

NAME = 'mods/tzy/seeker_drone_funcinfo_probe'
GUID = '8db35124-2d19-4c70-927e-965f88a2d450'
SOURCE = Path(__file__).with_name('funcinfo_probe.lua')
OUTPUT = ROOT / 'build/seeker_drone/Seeker-Drone-Funcinfo-Probe.zip'


if __name__ == '__main__':
    print(build_addon(NAME, SOURCE.read_bytes(), GUID, OUTPUT,
                      'Seeker Drone Read-Only Funcinfo Probe'))
