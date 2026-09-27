extends RefCounted
## A query-local convex hull collider. Transform once, support-scan many times.
## Double arrays keep matrix multiplication and simplex arithmetic in float64.
var points: Array[PackedFloat64Array] = []
var center := PackedFloat64Array([0,0,0,0])
var radius := 0.0
var valid := true

func _init(vertices: Array[Vector4], world: PackedFloat64Array) -> void:
	if vertices.is_empty() or world.size() != 25:
		valid = false
		return
	var low := PackedFloat64Array([INF,INF,INF,INF])
	var high := PackedFloat64Array([-INF,-INF,-INF,-INF])
	for vertex in vertices:
		var p := PackedFloat64Array([0,0,0,0])
		for row in range(4):
			p[row] = world[row * 5 + 4]
			for col in range(4): p[row] += world[row * 5 + col] * vertex[col]
			if not is_finite(p[row]): valid = false
			low[row] = minf(low[row],p[row])
			high[row] = maxf(high[row],p[row])
		points.append(p)
	for axis in range(4): center[axis] = low[axis] * 0.5 + high[axis] * 0.5
	for p in points:
		var squared := 0.0
		for axis in range(4): squared += (p[axis]-center[axis]) ** 2
		radius = maxf(radius, sqrt(squared))
	valid = valid and is_finite(radius)

func support(direction: PackedFloat64Array) -> PackedFloat64Array:
	var best := -INF
	var result: PackedFloat64Array = points[0]
	for p in points:
		var value := 0.0
		for axis in range(4): value += (p[axis]-center[axis]) * direction[axis]
		if value > best:
			best = value
			result = p
	return result
