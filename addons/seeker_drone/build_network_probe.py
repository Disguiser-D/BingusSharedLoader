"""Build the read-only native seeker network-association probe."""
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts'))
from build_addon import build_addon  # noqa: E402

NAME='mods/tzy/seeker_drone_network_probe'
GUID='8679d43e-8d57-4b1c-83c0-b242a7b0282f'
SOURCE=Path(__file__).with_name('network_probe.lua')
OUTPUT=ROOT/'build/seeker_drone/Seeker-Drone-Network-Probe.zip'

if __name__=='__main__':
    print(build_addon(NAME,SOURCE.read_bytes(),GUID,OUTPUT,
                      'Seeker Drone Read-Only Network Probe'))
