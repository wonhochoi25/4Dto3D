"""Verify literal entry-file replacement with all GJK/EPA implementation files absent."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

project = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="collision-backend-swap-") as directory:
    root = Path(directory)
    for folder in ("scripts", "tests", "scenes", "data"):
        if (project / folder).exists():
            shutil.copytree(project / folder, root / folder)
    shutil.copyfile(project / "project.godot", root / "project.godot")
    backend = root / "scripts/core/collision"
    for path in backend.iterdir():
        if path.name != "collision_backend.gd":
            path.unlink()
    shutil.copyfile(root / "tests/fixtures/collision_backend_probe.gd", backend / "collision_backend.gd")
    result = subprocess.run([sys.argv[1], "--headless", "--path", str(root), "--log-file", str(root / "run.log"),
                             "--script", "tests/verify_collision_backend.gd"], capture_output=True, text=True, timeout=60)
    print(result.stdout, end="")
    print(result.stderr, end="")
    assert result.returncode == 0 and "Collision backend failures: 0" in result.stdout
    assert "SCRIPT ERROR" not in result.stderr
print("PASS: replacing only backend entry + deleting GJK/EPA implementation works")
