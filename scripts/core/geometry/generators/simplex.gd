extends "res://scripts/core/geometry/geometry_4d.gd"
## Five equidistant points. A tetrahedral base lies in a constant-W hyperplane.
func _init() -> void:
	display_name = "5-cell (simplex)"
	vertices = [Vector4(1, 1, 1, -1.0 / sqrt(5.0)), Vector4(1, -1, -1, -1.0 / sqrt(5.0)), Vector4(-1, 1, -1, -1.0 / sqrt(5.0)), Vector4(-1, -1, 1, -1.0 / sqrt(5.0)), Vector4(0, 0, 0, 4.0 / sqrt(5.0))]
	normalize_radius()
	connect_shortest_pairs()
	capture_original()
