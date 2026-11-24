extends RefCounted
## Continuous collision for an axis-aligned 4D box whose center and half-extents
## interpolate linearly. Each obstacle constrains the same time interval in XYZW.
const SKIN := 0.001
const CONTACT_BACKOFF := 0.00002

static func bounds(center: Vector4, half: Vector4) -> Dictionary:
	return {"low": center - half, "high": center + half}

static func overlap_interval(from: Vector4, to: Vector4, half_from: Vector4,
		half_to: Vector4, low: Vector4, high: Vector4) -> Vector2:
	var enter := 0.0
	var leave := 1.0
	var start_min := from - half_from
	var start_max := from + half_from
	var end_min := to - half_to
	var end_max := to + half_to
	for axis in range(4):
		# Both inequalities must stay nonnegative for the boxes to overlap.
		var at_start := Vector2(start_max[axis] - low[axis], high[axis] - start_min[axis])
		var at_end := Vector2(end_max[axis] - low[axis], high[axis] - end_min[axis])
		for side in range(2):
			var a := at_start[side]
			var b := at_end[side]
			if a < 0.0 and b < 0.0:
				return Vector2(-1, -1)
			if a < 0.0:
				enter = maxf(enter, a / (a - b))
			elif b < 0.0:
				leave = minf(leave, a / (a - b))
			if enter > leave:
				return Vector2(-1, -1)
	return Vector2(enter, leave)

static func safe_fraction(from: Vector4, to: Vector4, half_from: Vector4,
		half_to: Vector4, obstacles: Array[Dictionary]) -> float:
	var hit := 1.0
	var padding := Vector4.ONE * SKIN
	var face_travel := (to - from).length() + (half_to - half_from).length()
	var backoff := CONTACT_BACKOFF / maxf(face_travel, CONTACT_BACKOFF)
	for obstacle in obstacles:
		var interval := overlap_interval(from, to, half_from, half_to,
			obstacle.low - padding, obstacle.high + padding)
		if interval.x < 0.0:
			continue
		if interval.x == 0.0 and maintains_separation(from, to, half_from, half_to, obstacle):
			continue
		# Back off in world units so a short keyboard step cannot round onto contact.
		hit = minf(hit, maxf(0.0, interval.x - backoff))
	return hit

static func maintains_separation(from: Vector4, to: Vector4, half_from: Vector4,
		half_to: Vector4, obstacle: Dictionary) -> bool:
	var start_min := from - half_from
	var start_max := from + half_from
	var end_min := to - half_to
	var end_max := to + half_to
	for axis in range(4):
		# Linear faces stay separated if either side keeps its initial clearance.
		if start_max[axis] <= obstacle.low[axis] and end_max[axis] <= start_max[axis]:
			return true
		if start_min[axis] >= obstacle.high[axis] and end_min[axis] >= start_min[axis]:
			return true
	return false
