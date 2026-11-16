#!/bin/zsh
SEAM_PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SEAM_GODOT_BIN="${GODOT_BIN:-$HOME/Applications/Godot.app/Contents/MacOS/Godot}"
if [[ ! -x "$SEAM_GODOT_BIN" ]]; then
  SEAM_GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"
fi
if [[ ! -x "$SEAM_GODOT_BIN" ]]; then
  print 'Godot was not found. Open project.godot in Godot and press F5.'
  exit 1
fi
exec "$SEAM_GODOT_BIN" --path "$SEAM_PROJECT_DIR" --rendering-method gl_compatibility --windowed res://game/main.tscn "$@"
