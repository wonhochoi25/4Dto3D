extends "res://scripts/shapes/shape_4d.gd"
## Sandbox loader: assumes a correctly formatted JSON file, with zero-based indices.
## Edit data/custom_shape.json and restart to reload the Playground's cached instance.
const DEFAULT_PATH := "res://data/custom_shape.json"
var faces: Array = []

func _init(path: String = DEFAULT_PATH) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	display_name = data.get("name", "Custom shape")
	for point in data["vertices"]:
		vertices.append(Vector4(point[0], point[1], point[2], point[3]))
	for edge in data["edges"]:
		edges.append(Vector2i(edge[0], edge[1]))
	faces = data.get("faces", [])
	capture_original()
