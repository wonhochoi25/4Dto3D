extends "res://hybrid/imported/scripts/game/puzzle_world.gd"

const Grab = preload("res://hybrid/object_interaction/grab_controller_4d.gd")
const PLAYER_START := Vector4(-3, 0, 0, 0)
const OBJECT_START := Vector4(-1.4, 0, 0, 0)
const OBJECT_HALF := Vector4(0.28, 0.32, 0.37, 0.24)
const ROOM_LOW := Vector4(-8, -2.8, -5, -2)
const ROOM_HIGH := Vector4(9, 2.8, 5, 7)
const TARGET := Vector4(3.65, 0, 0, 2.6)
const TARGET_HALF := Vector4(0.75, 0.65, 0.65, 0.42)

var object_id: int
var artifact := Grab.Box.new(OBJECT_START, OBJECT_HALF)
var player_half := Vector4.ONE * HALF_SIZE
var grab := Grab.new(player_half)
var placed := false
var message := ""
var room_bounds: Array[Dictionary] = []
var player_blocked := false

var hold: Grab.Hold:
	get: return grab.hold
var object_position: Vector4:
	get: return artifact.position
var object_scale: float:
	get: return artifact.scale
var carry_limited: bool:
	get: return grab.carry_limited

func _init() -> void:
	scene = Scene4D.new()
	solid_ids.clear()
	for axis in range(4):
		var outer_low := ROOM_LOW - Vector4.ONE * 0.5
		var outer_high := ROOM_HIGH + Vector4.ONE * 0.5
		var low_end := outer_high
		var high_start := outer_low
		low_end[axis] = ROOM_LOW[axis]
		high_start[axis] = ROOM_HIGH[axis]
		add_solid("Room", outer_low, low_end)
		add_solid("Room", high_start, outer_high)
	add_solid("Near wall", Vector4(0.2, -2.8, 2.3, -2), Vector4(0.55, 2.8, 5, 7))
	add_solid("Alcove lip", Vector4(3.3, -2.8, -5, -2), Vector4(3.6, 2.8, -2.3, 7))
	add_solid("W lip", Vector4(4.8, -2.8, -0.7, 0.82), Vector4(5.1, 2.8, 0.7, 1.14))
	player_id = add_shape("Player", -player_half, player_half)
	object_id = add_shape("Artifact", -OBJECT_HALF, OBJECT_HALF)
	goal_id = add_shape("Placement zone", TARGET - TARGET_HALF, TARGET + TARGET_HALF)
	reset()

func add_solid(label: String, low: Vector4, high: Vector4) -> void:
	add_box(label, low, high)
	room_bounds.append({"low": low, "high": high})

func reset() -> void:
	grab.release()
	placed = false
	player_blocked = false
	message = ""
	artifact.position = OBJECT_START
	artifact.scale = 1.0
	sync_scene(PLAYER_START)

func sync_scene(player: Vector4) -> void:
	scene.dynamic_matrices[player_id] = Transform4D.translation(player)
	var pose := Transform4D.translation(artifact.position)
	for axis in range(4):
		pose[axis * 5 + axis] = artifact.scale
	scene.dynamic_matrices[object_id] = pose
	state = scene.sample(0.0)

func object_in_slice(mode: int) -> bool:
	return artifact.in_slice(player_position, MODES[mode].hidden)

func interact(action: Grab.Hold, mode: int, forward: Vector3) -> void:
	if hold == action:
		var released := grab.release()
		var offset := (released.position - TARGET).abs()
		placed = offset.x <= TARGET_HALF.x and offset.y <= TARGET_HALF.y \
			and offset.z <= TARGET_HALF.z and offset.w <= TARGET_HALF.w
		message = "Placement confirmed." if placed else "Released at size ×%.2f." % released.scale
		return

	match grab.pickup(artifact, action, player_position, MODES[mode], forward, room_bounds):
		Grab.Result.OK:
			placed = false
			message = ""
		Grab.Result.ALREADY_HOLDING:
			message = "Release with G before picking up with T." if hold == Grab.Hold.RESIZE else "Release with T before picking up with G."
		Grab.Result.DISABLED:
			message = "That pickup action is disabled for this artifact."
		Grab.Result.MISS:
			message = "Aim directly at the artifact in a slice that contains it."

func try_switch_slice(next_mode: int, forward: Vector3) -> bool:
	var before := object_position
	match grab.try_switch_slice(player_position, MODES[next_mode], forward, room_bounds):
		Grab.Result.RESIZING:
			message = "Release with G before changing slices. Use T to carry the new size."
		Grab.Result.DESTINATION_BLOCKED:
			message = "The artifact won't fit in front of you in the other slice."
		Grab.Result.PATH_BLOCKED:
			message = "The artifact's path to the other slice is blocked. Move or change your aim."
		Grab.Result.OK:
			if object_position != before:
				sync_scene(player_position)
			player_blocked = false
			message = ""
			return true
	return false

func update_grab(mode: int, forward: Vector3, delta: float) -> void:
	var before := object_position
	var old_scale := object_scale
	grab.update(player_position, MODES[mode], forward, delta, room_bounds)
	if object_position != before or object_scale != old_scale:
		sync_scene(player_position)

func move_in_slice(delta: Vector3, mode: int) -> void:
	var start := player_position
	var before := object_position
	var requested := to_world_delta(delta, mode)
	var constraints := room_bounds
	if hold == Grab.Hold.RELEASED:
		constraints = room_bounds.duplicate()
		constraints.append(Grab.Placement.bounds(object_position, artifact.half_extents()))
	var player := grab.move_player(start, requested, MODES[mode].axes, constraints)
	if player != start or object_position != before:
		sync_scene(player)
	player_blocked = (player - start - requested).length() > 0.0001
