extends "res://scripts/core/geometry/geometry_4d.gd"
## The cross-polytope: positive/negative points on each of the four axes.
func _init() -> void:
	display_name = "16-cell"
	for axis in range(4):
		for sign_value in [-1.0, 1.0]:
			var point := Vector4.ZERO
			point[axis] = sign_value * 2.0
			vertices.append(point)
	connect_shortest_pairs()
	capture_original()
