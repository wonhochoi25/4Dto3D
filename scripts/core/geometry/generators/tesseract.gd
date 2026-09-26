extends "res://scripts/core/geometry/geometry_4d.gd"
## Bit-coded corners of a centered edge-length-2 tesseract.
func _init() -> void:
	display_name = "Tesseract (8-cell)"
	for i in range(16):
		var point := Vector4()
		for axis in range(4):
			point[axis] = 1.0 if (i & (1 << axis)) else -1.0
		vertices.append(point)
	for i in range(16):
		for axis in range(4):
			# XOR flips exactly one coordinate sign, yielding an adjacent vertex.
			var neighbor := i ^ (1 << axis)
			# Keep each undirected edge once: 16 * 4 / 2 = 32 edges.
			if i < neighbor:
				edges.append(Vector2i(i, neighbor))
	capture_original()
