extends RefCounted
## The game is a host of the upstream Scene4D graph, math, geometry and collision.
## Scene4D is used directly: a player-controlled puzzle needs no timeline recording.
const Scene4D = preload("res://scripts/core/scene/scene_4d.gd")
const Box4D = preload("res://scripts/core/geometry/generators/tesseract.gd")
const Transform4D = preload("res://scripts/core/math/transform_4d.gd")
const Projection4D = preload("res://scripts/core/math/projection_4d.gd")
const Slice4D = preload("res://hybrid/imported/scripts/core/math/slice_4d.gd")
const Bounds4D = preload("res://scripts/core/physics/broad_phase_4d.gd")
const Motor = preload("res://hybrid/imported/scripts/game/swept_player_4d.gd")
const AXIS_NAMES := ["X", "Y", "Z", "W"]
# Display X/Y/Z -> world axes. Preserve world Y as up whenever available.
const MODES := [
	{"name": "XYZ", "axes": [0, 1, 2], "hidden": 3},
	{"name": "YZW", "axes": [3, 1, 2], "hidden": 0},
	{"name": "XYW", "axes": [0, 1, 3], "hidden": 2},
	{"name": "XZW", "axes": [0, 3, 2], "hidden": 1},
]
const START := Vector4(-2.0, 0.0, 0.0, 0.0)
const MIN_CENTER := Vector4(-4.0, -2.0, -2.0, -1.0)
const MAX_CENTER := Vector4(4.0, 2.0, 2.0, 4.0)
const HALF_SIZE := 0.2
const SKIN := 0.0001
const GOAL_MIN := Vector4(1.55, -0.55, -0.55, 2.4)
const GOAL_MAX := Vector4(2.45, 0.55, 0.55, 3.6)
const GUIDE_MIN := Vector4(-3.8, -0.7, -0.7, 2.4)
const GUIDE_MAX := Vector4(-0.8, 0.7, 0.7, 3.6)

var scene := Scene4D.new()
var state: Dictionary = {}
var solid_ids: Array[int] = []
var obstacles: Array[Dictionary] = []
var motor := Motor.new()
var player_id := 0
var guide_id := 0
var goal_id := 0
var player_position: Vector4:
	get:
		return Transform4D.apply(collider(player_id).world, Vector4.ZERO)

func _init() -> void:
	# Six 4D boxes form a slab minus a finite 4D doorway.
	add_box("Lower frame", Vector4(-0.5, -3, -3, -2), Vector4(0.5, -1, 3, 5))
	add_box("Upper frame", Vector4(-0.5, 1, -3, -2), Vector4(0.5, 3, 3, 5))
	add_box("Back frame", Vector4(-0.5, -1, -3, -2), Vector4(0.5, 1, -1, 5))
	add_box("Front frame", Vector4(-0.5, -1, 1, -2), Vector4(0.5, 1, 3, 5))
	add_box("Low W plug", Vector4(-0.5, -1, -1, -2), Vector4(0.5, 1, 1, 2))
	add_box("High W plug", Vector4(-0.5, -1, -1, 4), Vector4(0.5, 1, 1, 5))

	guide_id = add_shape("Approach guide", GUIDE_MIN, GUIDE_MAX)
	goal_id = add_shape("Exit", GOAL_MIN, GOAL_MAX)
	player_id = add_shape("Player", -Vector4.ONE * HALF_SIZE, Vector4.ONE * HALF_SIZE)
	scene.dynamic_matrices[player_id] = Transform4D.translation(START)
	refresh_scene()

func add_shape(label: String, low: Vector4, high: Vector4) -> int:
	var shape := Box4D.new()
	shape.display_name = label
	var center := (low + high) * 0.5
	var extent := (high - low) * 0.5
	var position_settings := {}
	var scale_settings := {}
	for axis in range(4):
		position_settings[AXIS_NAMES[axis]] = center[axis]
		scale_settings[AXIS_NAMES[axis]] = extent[axis]
	var id: int = scene.add_geometry(shape, {"position": position_settings, "scale": scale_settings})
	assert(id != 0, scene.error)
	return id

func add_box(label: String, low: Vector4, high: Vector4) -> void:
	solid_ids.append(add_shape(label, low, high))

func collider(id: int) -> Dictionary:
	var object: Dictionary = scene.objects[id]
	return {"geometry": object.geometry, "world": state[object.leaf_id].world}

func refresh_scene() -> void:
	state = scene.sample(0.0)
	obstacles.clear()
	for id in solid_ids:
		var descriptor := collider(id)
		descriptor["bounds"] = Bounds4D.bounds(descriptor)
		obstacles.append(descriptor)

func set_player(point: Vector4) -> void:
	if not state.is_empty() and player_position.is_equal_approx(point):
		return
	scene.dynamic_matrices[player_id] = Transform4D.translation(point)
	state = scene.sample(0.0)

static func basis_rows(mode: int) -> Array[Vector4]:
	var rows: Array[Vector4] = []
	for axis in MODES[mode].axes:
		var row := Vector4.ZERO
		row[axis] = 1.0
		rows.append(row)
	return rows

static func to_view(point: Vector4, mode: int) -> Vector3:
	var projection := Projection4D.new()
	projection.rows = basis_rows(mode)
	return projection.project([point])[0]

static func to_world_delta(delta: Vector3, mode: int) -> Vector4:
	var rows := basis_rows(mode)
	return rows[0] * delta.x + rows[1] * delta.y + rows[2] * delta.z

func slice_points(id: int, mode: int, coordinate: float) -> PackedVector3Array:
	var normal := Vector4.ZERO
	normal[MODES[mode].hidden] = 1.0
	return Slice4D.intersect(scene.world_vertices(id, state), scene.objects[id].geometry.edges,
		normal, coordinate, basis_rows(mode))

func move_player(point: Vector4, delta: Vector3, mode: int) -> Vector4:
	var result := motor.move(point, to_world_delta(delta, mode), MODES[mode].axes,
		obstacles, MIN_CENTER, MAX_CENTER)
	set_player(result)
	return result

func is_blocked(point: Vector4) -> bool:
	return motor.blocked(point, obstacles)

func reached_goal(point: Vector4) -> bool:
	# A zero-size trigger test in the goal's LOCAL frame, through core transforms.
	var inverse := Scene4D.inverse(collider(goal_id).world)
	if inverse.is_empty():
		return false
	var local := Transform4D.apply(inverse, point)
	for axis in range(4):
		if absf(local[axis]) > 1.0:
			return false
	return true
