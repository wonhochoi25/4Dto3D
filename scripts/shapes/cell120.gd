extends "res://scripts/shapes/shape_4d.gd"
const Orbits = preload("res://scripts/shapes/coordinate_orbits.gd")
## Seven coordinate orbits of the regular 120-cell, normalized to radius 2.
## Coordinate reference and permutation convention are documented in README.md.
func _init() -> void:
	display_name = "120-cell"
	var phi := (1.0 + sqrt(5.0)) / 2.0
	var inverse := 1.0 / phi
	for seed in [Vector4(2, 2, 0, 0), Vector4(sqrt(5.0), 1, 1, 1), Vector4(phi, phi, phi, inverse * inverse), Vector4(phi * phi, inverse, inverse, inverse)]:
		vertices.append_array(Orbits.signed_permutations(seed))
	for seed in [Vector4(phi * phi, inverse * inverse, 1, 0), Vector4(sqrt(5.0), inverse, phi, 0), Vector4(2, 1, phi, inverse)]:
		vertices.append_array(Orbits.signed_permutations(seed, true))
	normalize_radius()
	connect_shortest_pairs()
	capture_original()
