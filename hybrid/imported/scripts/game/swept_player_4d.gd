extends RefCounted
## Game motor, not a second physics engine. Queries the core's replaceable backend.
## A translating axis-aligned player box sweeps out an EXACT box along one axis.
## Bisect that swept volume to stop before first contact, including far endpoints.
const Box4D = preload("res://scripts/core/geometry/generators/tesseract.gd")
const Transform4D = preload("res://scripts/core/math/transform_4d.gd")
const Bounds4D = preload("res://scripts/core/physics/broad_phase_4d.gd")
const Backend = preload("res://scripts/core/physics/collision/collision_backend.gd")
const SKIN := 0.0001
var geometry := Box4D.new()
var half_size := Vector4.ONE * 0.2
var query: Callable = Backend.query
var error := ""
var query_count := 0

func descriptor(center: Vector4, half_extent: Vector4) -> Dictionary:
	var matrix := Transform4D.translation(center)
	for axis in range(4):
		matrix[axis * 5 + axis] = half_extent[axis]
	return {"geometry": geometry, "world": matrix}

func blocked(point: Vector4, obstacles: Array[Dictionary]) -> bool:
	return sweep_blocked(point, 0, 0.0, obstacles)

func sweep_blocked(point: Vector4, axis: int, distance: float, obstacles: Array[Dictionary]) -> bool:
	var center := point
	var extent := half_size
	center[axis] += distance * 0.5
	extent[axis] += absf(distance) * 0.5
	var moving := descriptor(center, extent)
	var bounds := {"low": center - extent, "high": center + extent}
	for obstacle in obstacles:
		if not Bounds4D.overlap(bounds, obstacle.bounds, SKIN):
			continue
		query_count += 1
		var result: Dictionary = query.call(moving, obstacle)
		if result.get("status", "indeterminate") != "separated":
			if result.get("status", "indeterminate") != "intersecting":
				error = "Collision unresolved: " + str(result.get("reason", "Missing backend status"))
			return true
	return false

func move(point: Vector4, delta: Vector4, axes: Array, obstacles: Array[Dictionary],
		low: Vector4, high: Vector4) -> Vector4:
	error = ""
	query_count = 0
	var result := point
	for axis in axes:
		var distance := clampf(result[axis] + delta[axis], low[axis], high[axis]) - result[axis]
		if absf(distance) < 0.0000001:
			continue
		if not sweep_blocked(result, axis, distance, obstacles):
			result[axis] += distance
			continue
		var safe := 0.0
		var blocked_fraction := 1.0
		for iteration in range(22):
			if (blocked_fraction - safe) * absf(distance) < SKIN * 0.25:
				break
			var middle := (safe + blocked_fraction) * 0.5
			if sweep_blocked(result, axis, distance * middle, obstacles):
				blocked_fraction = middle
			else:
				safe = middle
		result[axis] += signf(distance) * maxf(0.0, absf(distance) * safe - SKIN)
	return result
