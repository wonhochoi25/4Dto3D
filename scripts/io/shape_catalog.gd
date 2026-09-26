extends RefCounted
## Add one entry here after implementing a Shape4D-derived generator.
## IDs are stable cache keys; display names are independent UI labels.
const CUSTOM_DIRECTORY := "res://data/custom_shapes"
const BUILT_INS = [
	{"id": "tesseract", "name": "Tesseract (8-cell)", "script": preload("res://scripts/core/geometry/generators/tesseract.gd")},
	{"id": "hypersphere", "name": "Hypersphere (sampled)", "script": preload("res://scripts/core/geometry/generators/hypersphere.gd")},
	{"id": "simplex", "name": "5-cell (simplex)", "script": preload("res://scripts/core/geometry/generators/simplex.gd")},
	{"id": "cell16", "name": "16-cell", "script": preload("res://scripts/core/geometry/generators/cell16.gd")},
	{"id": "cell24", "name": "24-cell", "script": preload("res://scripts/core/geometry/generators/cell24.gd")},
	{"id": "cell120", "name": "120-cell", "script": preload("res://scripts/core/geometry/generators/cell120.gd")},
	{"id": "cell600", "name": "600-cell", "script": preload("res://scripts/core/geometry/generators/cell600.gd")},
]
# Sorted file paths provide stable cache IDs even when display names repeat.
static var ENTRIES: Array = discover()

static func discover(directory: String = CUSTOM_DIRECTORY) -> Array:
	var entries := BUILT_INS.duplicate(true)
	var files := DirAccess.get_files_at(directory)
	files.sort()
	for filename in files:
		if filename.get_extension().to_lower() != "json": continue
		var path := directory.path_join(filename)
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary:
			push_warning("Cannot read custom shape: " + path)
			continue
		entries.append({"id": "custom:" + path, "name": str(data.get("name", filename.get_basename())), "path": path})
	return entries

static func create(index: int):
	var entry: Dictionary = ENTRIES[index]
	if entry.has("path"):
		return preload("res://scripts/io/shape_json_loader.gd").new(entry.path)
	return entry.script.new()

## IO resolves assets; runtime construction receives in-memory geometry and settings.
static func asset(index: int) -> Dictionary:
	var geometry = create(index)
	var entry: Dictionary = ENTRIES[index]
	var defaults := {}
	if entry.has("path"):
		defaults = geometry.procedural_defaults
	else:
		geometry.faces = JSON.parse_string(FileAccess.get_file_as_string("res://data/faces/%s.json" % entry.id))
	return {"geometry": geometry, "defaults": defaults}
