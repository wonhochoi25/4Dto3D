"""Check physics and recorder module boundaries, then run physically isolated copies."""
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

project = Path(__file__).resolve().parents[1]
for script in (project / "scripts/core/physics").rglob("*.gd"):
    for dependency in re.findall(r'["\'](res://[^"\']+)["\']', script.read_text()):
        assert dependency.startswith(("res://scripts/core/physics/", "res://scripts/core/math/", "res://scripts/core/geometry/")), (script, dependency)
for script in (project / "scripts/core/playback").glob("*.gd"):
    assert "res://scripts/core/physics/" not in script.read_text(), script
for folders, test, marker in [
    (["physics", "math"], "verify_physics_module", "Physics module failures: 0"),
    (["playback"], "verify_recording_module", "Recorder module passed"),
]:
    with tempfile.TemporaryDirectory(prefix="4d-module-") as directory:
        root = Path(directory)
        for folder in folders:
            shutil.copytree(project / "scripts/core" / folder, root / "scripts/core" / folder)
        shutil.copyfile(project / "tests" / (test + ".gd"), root / "test.gd")
        (root / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Module check"\n')
        result = subprocess.run([sys.argv[1], "--headless", "--path", str(root), "--log-file", str(root / "run.log"), "--script", "test.gd"], capture_output=True, text=True, timeout=30)
        print(result.stdout, end="")
        print(result.stderr, end="")
        assert result.returncode == 0 and marker in result.stdout and "SCRIPT ERROR" not in result.stderr
print("PASS: physics without scene/session/playback; recorder without physics")
