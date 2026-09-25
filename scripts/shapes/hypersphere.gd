extends "res://scripts/shapes/shape_4d.gd"
## Radially project the subdivided cube boundary onto x²+y²+z²+w²=4.
func _init() -> void:
	display_name = "Hypersphere (sampled)"
	description = "Radius 2 · 80 surface samples joined by chords"
	var lattice: Array[Vector4] = []
	for x in range(-1, 2):
		for y in range(-1, 2):
			for z in range(-1, 2):
				for w in range(-1, 2):
					var point := Vector4(x, y, z, w)
					if point == Vector4.ZERO:
						continue
					lattice.append(point)
					vertices.append(point.normalized() * 2.0)
	for i in range(lattice.size()):
		for j in range(i + 1, lattice.size()):
			var difference := (lattice[i] - lattice[j]).abs()
			if difference.x + difference.y + difference.z + difference.w != 1.0:
				continue
			# Both endpoints must share a boundary face; omit interior lattice links.
			for axis in range(4):
				if absf(lattice[i][axis]) == 1.0 and lattice[i][axis] == lattice[j][axis]:
					edges.append(Vector2i(i, j))
					break

	capture_original()
