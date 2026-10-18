extends RefCounted
## Authoring only: subtract a union of empty 4D boxes from solid boxes.
## The result is disjoint convex solids, all handled by the existing core.
static func box(low: Vector4, high: Vector4, tag: String = "shell") -> Dictionary:
	return {"min": low, "max": high, "tag": tag}

static func subtract(solid: Dictionary, opening: Dictionary) -> Array[Dictionary]:
	var low: Vector4 = solid.min.max(opening.min)
	var high: Vector4 = solid.max.min(opening.max)
	for axis in range(4):
		if low[axis] >= high[axis]:
			return [solid]
	var remainder_low: Vector4 = solid.min
	var remainder_high: Vector4 = solid.max
	var pieces: Array[Dictionary] = []
	for axis in range(4):
		if remainder_low[axis] < low[axis]:
			var end := remainder_high
			end[axis] = low[axis]
			pieces.append(box(remainder_low, end, solid.tag))
			remainder_low[axis] = low[axis]
		if remainder_high[axis] > high[axis]:
			var start := remainder_low
			start[axis] = high[axis]
			pieces.append(box(start, remainder_high, solid.tag))
			remainder_high[axis] = high[axis]
	return pieces

static func carve(envelope: Dictionary, openings: Array) -> Array[Dictionary]:
	var solids: Array[Dictionary] = [envelope]
	for opening in openings:
		var next: Array[Dictionary] = []
		for solid in solids:
			next.append_array(subtract(solid, opening))
		solids = next
	return solids

static func tube(a: Vector4, b: Vector4, radius: float = 0.8) -> Dictionary:
	return box(a.min(b) - Vector4.ONE * radius, a.max(b) + Vector4.ONE * radius)

static func wall(x: float, z: float, w: float) -> Array[Dictionary]:
	return carve(box(Vector4(x - 0.35, -2, -4, -2), Vector4(x + 0.35, 2, 4, 5), "gate"),
		[box(Vector4(x - 1, -0.8, z - 0.8, w - 0.8), Vector4(x + 1, 0.8, z + 0.8, w + 0.8))])
