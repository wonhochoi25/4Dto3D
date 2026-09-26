extends "res://scripts/core/geometry/geometry_4d.gd"
const Orbits = preload("res://scripts/core/geometry/generators/coordinate_orbits.gd")
## All signed permutations of (1,1,0,0), normalized to radius 2.
func _init() -> void:
	display_name = "24-cell"
	vertices = Orbits.signed_permutations(Vector4(1, 1, 0, 0))
	normalize_radius()
	connect_shortest_pairs()
	capture_original()
