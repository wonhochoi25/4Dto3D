extends RefCounted
## Generate distinct signed permutations of a coordinate seed.
## even_only restricts coordinate permutations to even parity (not sign changes).
static func signed_permutations(seed: Vector4, even_only: bool = false) -> Array[Vector4]:
	var unique := {}
	var result: Array[Vector4] = []
	for a in range(4):
		for b in range(4):
			for c in range(4):
				for d in range(4):
					var order := [a, b, c, d]
					if a == b or a == c or a == d or b == c or b == d or c == d:
						continue
					var inversions := 0
					for i in range(4):
						for j in range(i + 1, 4):
							if order[i] > order[j]:
								inversions += 1
					if even_only and inversions % 2 != 0:
						continue
					for signs in range(16):
						var point := Vector4.ZERO
						for axis in range(4):
							point[axis] = seed[order[axis]] * (-1.0 if signs & (1 << axis) else 1.0)
						if not unique.has(point):
							unique[point] = true
							result.append(point)
	return result
