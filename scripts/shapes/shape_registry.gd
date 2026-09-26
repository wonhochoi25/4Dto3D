extends RefCounted
## Add one entry here after implementing a Shape4D-derived generator.
## IDs are stable cache keys; display names are independent UI labels.
const CUSTOM_DIRECTORY := "res://data/custom_shapes"
const BUILT_INS = [
	{"id": "tesseract", "name": "Tesseract (8-cell)", "script": preload("res://scripts/shapes/tesseract.gd")},
	{"id": "hypersphere", "name": "Hypersphere (sampled)", "script": preload("res://scripts/shapes/hypersphere.gd")},
	{"id": "simplex", "name": "5-cell (simplex)", "script": preload("res://scripts/shapes/simplex.gd")},
	{"id": "cell16", "name": "16-cell", "script": preload("res://scripts/shapes/cell16.gd")},
	{"id": "cell24", "name": "24-cell", "script": preload("res://scripts/shapes/cell24.gd")},
	{"id": "cell120", "name": "120-cell", "script": preload("res://scripts/shapes/cell120.gd")},
	{"id": "cell600", "name": "600-cell", "script": preload("res://scripts/shapes/cell600.gd")},
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
		return preload("res://scripts/shapes/file_shape_4d.gd").new(entry.path)
	return entry.script.new()
