extends "res://scripts/core/geometry/geometry_4d.gd"
const Orbits = preload("res://scripts/core/geometry/generators/coordinate_orbits.gd")
## H4 coordinates: 8 axis points, 16 hypercube points, 96 even permutations.
## Coordinate reference and normalization are documented in README.md.
func _init() -> void:
	display_name = "600-cell"
	var phi := (1.0 + sqrt(5.0)) / 2.0
	vertices.append_array(Orbits.signed_permutations(Vector4(2, 0, 0, 0)))
	vertices.append_array(Orbits.signed_permutations(Vector4(1, 1, 1, 1)))
	vertices.append_array(Orbits.signed_permutations(Vector4(phi, 1, 1.0 / phi, 0), true))
	connect_shortest_pairs()
	capture_original()
