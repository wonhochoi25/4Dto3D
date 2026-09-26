"""Prove core runs with no sandbox, IO, assets, or renderer installed."""
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

project = pathlib.Path(__file__).resolve().parents[1]
core = project / "scripts/core"
for script in core.rglob("*.gd"):
    source = script.read_text()
    for dependency in re.findall(r'["\'](res://[^"\']+)["\']', source):
        assert dependency.startswith("res://scripts/core/"), (script, dependency)
    assert not re.search(r"\b(?:FileAccess|DirAccess|RenderingServer)\b", source), script
    assert not re.search(r"^extends (?:Node\w*|Control|.*Container)\b", source, re.M), script
for layer in ["io", "rendering"]:
    for script in (project / "scripts" / layer).rglob("*.gd"):
        assert "res://scripts/sandbox/" not in script.read_text(), script

binary = sys.argv[1] if len(sys.argv) > 1 else shutil.which("godot")
assert binary, "Pass the Godot executable as the first argument"
with tempfile.TemporaryDirectory(prefix="core4d-isolation-") as directory:
    root = pathlib.Path(directory)
    shutil.copytree(core, root / "scripts/core")
    shutil.copyfile(project / "tests/verify_core.gd", root / "verify_core.gd")
    (root / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Core isolation"\n')
    result = subprocess.run([binary, "--headless", "--path", str(root), "--log-file", str(root / "run.log"),
                             "--script", "res://verify_core.gd"], text=True, capture_output=True, timeout=60)
    print(result.stdout, end="")
    print(result.stderr, end="")
    assert result.returncode == 0 and "Core failures: 0" in result.stdout
    assert "SCRIPT ERROR" not in result.stderr
print("PASS: core dependency boundaries and standalone minimal project")
