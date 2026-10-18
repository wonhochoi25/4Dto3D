extends RefCounted
## Convex-polytope cross-section before projection. Requires complete hull edges.
## Supports a unit normal and any orthonormal three-row basis perpendicular to it.
const Projection4D = preload("res://scripts/core/math/projection_4d.gd")

static func intersect(vertices: Array[Vector4], edges: Array[Vector2i], normal: Vector4,
		offset: float, rows: Array[Vector4], origin: Vector4 = Vector4.ZERO) -> PackedVector3Array:
	assert(rows.size() == 3 and absf(normal.length_squared() - 1.0) < 0.0001)
	for i in range(3):
		assert(absf(rows[i].dot(normal)) < 0.0001 and absf(rows[i].length_squared() - 1.0) < 0.0001)
		for j in range(i):
			assert(absf(rows[i].dot(rows[j])) < 0.0001)
	var points: Array[Vector4] = []
	var distances: Array[float] = []
	# Relative to the local cloud scale, not its distance from the world origin.
	var scale := 1.0
	if not vertices.is_empty():
		for vertex in vertices:
			scale = maxf(scale, vertex.distance_to(vertices[0]))
	var epsilon := scale * 0.000001
	for vertex in vertices:
		var distance := normal.dot(vertex) - offset
		distances.append(distance)
		if absf(distance) <= epsilon:
			append_unique(points, vertex - origin, epsilon)
	for edge in edges:
		assert(edge.x >= 0 and edge.y >= 0 and edge.x < vertices.size() and edge.y < vertices.size())
		var a := distances[edge.x]
		var b := distances[edge.y]
		if (a < -epsilon and b > epsilon) or (b < -epsilon and a > epsilon):
			var point := vertices[edge.x].lerp(vertices[edge.y], a / (a - b))
			append_unique(points, point - origin, epsilon)
	var projection := Projection4D.new()
	projection.rows = rows
	return projection.project(points)

static func append_unique(points: Array[Vector4], point: Vector4, epsilon: float) -> void:
	for existing in points:
		if point.distance_squared_to(existing) <= epsilon * epsilon:
			return
	points.append(point)
