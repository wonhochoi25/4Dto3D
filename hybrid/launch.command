#!/bin/zsh
# Launch this scene without changing the repository's default lab scene.
HYBRID_PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HYBRID_GODOT_BIN="${GODOT_BIN:-$HOME/Applications/Godot.app/Contents/MacOS/Godot}"
if [[ ! -x "$HYBRID_GODOT_BIN" ]]; then
  HYBRID_GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"
fi
if [[ ! -x "$HYBRID_GODOT_BIN" ]]; then
  print 'Godot was not found. Open hybrid/training.tscn in Godot and press F6.'
  exit 1
fi
exec "$HYBRID_GODOT_BIN" --path "$HYBRID_PROJECT_DIR" --rendering-method gl_compatibility --windowed res://hybrid/training.tscn
