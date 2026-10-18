extends "res://hybrid/imported/scripts/campaign/level_world.gd"
## A fixed-size 4D key and geometric plate. Neither projection nor mass controls the gate.
const KEY_HALF := Vector4(0.35, 0.35, 0.60, 0.25)
const KEY_START := Vector4(-2, 0, 0, 0)
const PLATE := Vector4(1.8, 0, 0, 3)
# Acceptance is based on the key CENTER entering the visible capture outline.
# Share these bounds with rendering so the displayed target is the actual trigger.
const PLATE_CAPTURE_HALF := Vector4(0.53, 0.53, 0.78, 0.43)
var key_id := -1
var plate_id := -1
var socket_id := -1
var gate_id := -1
var holding := false
var plate_active := false
var key_motor := Motor.new()
var interaction_message := ""
var key_position: Vector4:
	get: return Transform4D.apply(collider(key_id).world, Vector4.ZERO) if key_id >= 0 else Vector4.ZERO

func _init(index: int = 0) -> void:
	super(index)
	if not definition.get("key_chamber", false): return
	key_motor.half_size = KEY_HALF
	key_id = add_shape("Key", -KEY_HALF, KEY_HALF)
	scene.dynamic_matrices[key_id] = Transform4D.translation(KEY_START)
	plate_id = add_shape("Pressure plate", PLATE + Vector4(-0.65, -0.48, -0.9, -0.45), PLATE + Vector4(0.65, -0.35, 0.9, 0.45))
	socket_id = add_shape("Plate capture area", PLATE - PLATE_CAPTURE_HALF, PLATE + PLATE_CAPTURE_HALF)
	for id in solid_ids:
		if scene.objects[id].name == "exit_gate": gate_id = id
	marker_ids.clear() # Object/sensor signposts replace the walking-only route markers.
	refresh_scene()

func key_descriptor() -> Dictionary:
	var result := collider(key_id)
	result["bounds"] = Bounds4D.bounds(result)
	return result

func player_obstacles() -> Array[Dictionary]:
	var result: Array[Dictionary] = obstacles.duplicate()
	if key_id >= 0: result.append(key_descriptor())
	return result

func is_blocked(point: Vector4) -> bool:
	return motor.blocked(point, player_obstacles()) if key_id >= 0 else super.is_blocked(point)

func move_player(point: Vector4, delta: Vector3, mode: int) -> Vector4:
	if key_id < 0: return super.move_player(point, delta, mode)
	var result := point
	var key := key_position
	var requested := to_world_delta(delta, mode)
	if holding:
		# Sweep both bodies on each active axis, taking only the common safe distance.
		# The tether offset never changes, even when one body is outside the visible slice.
		for axis in MODES[mode].axes:
			var step := Vector4.ZERO
			step[axis] = requested[axis]
			var p := motor.move(result, step, [axis], obstacles, definition.low, definition.high)
			var k := key_motor.move(key, step, [axis], obstacles, definition.low, definition.high)
			var distance := signf(step[axis]) * minf(absf(p[axis] - result[axis]), absf(k[axis] - key[axis]))
			result[axis] += distance
			key[axis] += distance
		scene.dynamic_matrices[key_id] = Transform4D.translation(key)
	else:
		result = motor.move(point, requested, MODES[mode].axes, player_obstacles(), definition.low, definition.high)
	set_player(result)
	state = scene.sample(0.0)
	update_stage()
	return result

func update_stage() -> void:
	if plate_active: stage = 3
	elif holding: stage = 2 if absf(key_position.w - 3.0) < 0.55 else 1
	else: stage = 0

static func segment_hits_box(a: Vector4, b: Vector4, low: Vector4, high: Vector4) -> bool:
	var near := 0.0
	var far := 1.0
	for axis in range(4):
		var d := b[axis] - a[axis]
		if absf(d) < 0.000001:
			if a[axis] < low[axis] or a[axis] > high[axis]: return false
		else:
			var t1: float = (low[axis] - a[axis]) / d
			var t2: float = (high[axis] - a[axis]) / d
			near = maxf(near, minf(t1, t2))
			far = minf(far, maxf(t1, t2))
			if near > far: return false
	return true

func interact(mode: int, forward: Vector3) -> bool:
	if key_id < 0: return false
	if plate_active:
		interaction_message = "Key secured by the plate. The exit gate is latched open."
		return false
	if holding:
		holding = false
		try_activate_plate()
		interaction_message = "Plate activated — exit gate open." if plate_active else "Key released. Look at it and press G to grab again."
		update_stage()
		return true
	var origin := player_position
	var hidden: int = MODES[mode].hidden
	if absf(origin[hidden] - key_position[hidden]) > KEY_HALF[hidden] or origin.distance_to(key_position) > 1.8:
		interaction_message = "Move within 1.8 units of the key on a slice that contains it."
		return false
	var end := origin + to_world_delta(forward.normalized() * 1.8, mode)
	if not segment_hits_box(origin, end, key_position - KEY_HALF, key_position + KEY_HALF):
		interaction_message = "Aim the crosshair at the orange key, then press G."
		return false
	for obstacle in obstacles:
		if segment_hits_box(origin, key_position, obstacle.bounds.low, obstacle.bounds.high):
			interaction_message = "A wall blocks the key. You cannot grab through solids."
			return false
	holding = true
	interaction_message = "Key attached. Carrying preserves its offset in all four dimensions. G releases."
	update_stage()
	return true

func try_activate_plate() -> void:
	if holding or plate_active: return
	for axis in range(4):
		if absf(key_position[axis] - PLATE[axis]) > PLATE_CAPTURE_HALF[axis]: return
	# A magnetic plate secures the released key and latches the gate; no crush/reset race.
	plate_active = true
	solid_ids.erase(gate_id)
	refresh_scene()
	stage = 3

func reached_goal(point: Vector4) -> bool:
	return (key_id < 0 or plate_active) and super.reached_goal(point)

func reset() -> void:
	super.reset()
	if key_id < 0: return
	holding = false
	plate_active = false
	interaction_message = ""
	if not gate_id in solid_ids: solid_ids.append(gate_id)
	scene.dynamic_matrices[key_id] = Transform4D.translation(KEY_START)
	refresh_scene()
