extends "res://scripts/core/geometry/geometry_4d.gd"
var procedural_defaults: Dictionary = {}
## Sandbox loader: assumes a correctly formatted JSON file, with zero-based indices.
## Registry supplies a file from data/custom_shapes; each instance owns fresh data.

func _init(path: String) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	display_name = data.get("name", "Custom shape")
	for point in data["vertices"]:
		vertices.append(Vector4(point[0], point[1], point[2], point[3]))
	for edge in data["edges"]:
		edges.append(Vector2i(edge[0], edge[1]))
	faces = data.get("faces", [])
	procedural_defaults = data.get("procedural_defaults", {})
	capture_original()
