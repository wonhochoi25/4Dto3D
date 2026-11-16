#!/usr/bin/env python3
"""Run authoritative campaign routes and presentation/input checks."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', str(Path.home() / 'Applications/Godot.app/Contents/MacOS/Godot')))
parser.add_argument('--rendered', action='store_true', help='Run presentation in a real Compatibility-renderer window and capture PNGs')
args = parser.parse_args()
project = Path(__file__).resolve().parents[2]
failed = False
with tempfile.TemporaryDirectory(prefix='seam-tests-') as logs:
    for i, suite in enumerate(['test_campaign.gd', 'test_presentation.gd']):
        display = ['--rendering-method', 'gl_compatibility', '--windowed'] if args.rendered and i == 1 else ['--headless']
        try:
            result = subprocess.run([args.godot, *display, '--path', str(project), '--script',
                                     f'res://game/tests/{suite}', '--log-file', str(Path(logs) / f'{i}.log')],
                                    capture_output=True, text=True, timeout=180)
            output = result.stdout + result.stderr
            print(output, flush=True)
            # macOS headless Godot may emit a system certificate lookup error in a sandbox.
            lines = output.splitlines()
            errors = [line for line in lines if ('ERROR:' in line or 'FAIL:' in line)
                      and 'Condition "ret != noErr"' not in line]
            failed |= result.returncode != 0 or bool(errors)
        except subprocess.TimeoutExpired:
            print(f'FAIL: {suite} timed out', flush=True)
            failed = True
print('FAIL' if failed else 'PASS: both SEAM suites')
raise SystemExit(int(failed))
