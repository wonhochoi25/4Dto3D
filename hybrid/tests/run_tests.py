#!/usr/bin/env python3
"""Run hybrid geometry/gameplay checks and upstream first-person regressions."""
from pathlib import Path
import subprocess
import tempfile
import argparse

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', default=str(Path.home() / 'Applications/Godot.app/Contents/MacOS/Godot'))
args = parser.parse_args()
project = Path(__file__).resolve().parents[2]
suites = ['hybrid/imported/tests/campaign/test_chambers.gd', 'hybrid/tests/test_hybrid.gd',
          'tests/verify_artifact_puzzle.gd', 'tests/verify_guided_experience.gd']
failed = False
with tempfile.TemporaryDirectory(prefix='hybrid-tests-') as logs:
    for i, suite in enumerate(suites):
        try:
            result = subprocess.run([args.godot, '--headless', '--path', str(project), '--script',
                                     'res://' + suite, '--log-file', str(Path(logs) / f'{i}.log')],
                                    capture_output=True, text=True, timeout=120)
            output = result.stdout + result.stderr
            print(output, flush=True)
            failed |= result.returncode != 0 or 'ERROR:' in output or 'SCRIPT ERROR' in output
        except subprocess.TimeoutExpired:
            print(f'FAIL: {suite} timed out', flush=True)
            failed = True
print('FAIL' if failed else 'PASS: all four suites')
raise SystemExit(int(failed))
