extends RefCounted
## One physical 4D world. Changing the coordinate frame never translates an object.
const Levels = preload("res://game/levels.gd")
const Frame = preload("res://game/frame.gd")
const Motor = preload("res://hybrid/imported/scripts/game/swept_player_4d.gd")
const CELL_HALF := Vector4.ONE * 0.34
const SPEED := 4.5
const RUN_SPEED := 7.2
const GRAVITY := 18.0
const JUMP := 6.1
var definition: Dictionary
var frame := Frame.new()
var player := Vector4.ZERO
var velocity := 0.0
var grounded := false
var manual_gravity := false
var held := ""
var cells: Array[Dictionary] = []
var powered: Dictionary = {}
var solids: Array[Dictionary] = []
var obstacles: Array[Dictionary] = []
var motor := Motor.new()
var cell_motor := Motor.new()
var checkpoint: Dictionary = {}
var message := ""
var revision := 0
var won := false
var shifts := 0
var falls := 0
var running := false

func _init(index: int = 0, selectable_gravity: bool = false) -> void:
	definition = Levels.build(index)
	manual_gravity = selectable_gravity
	player = definition.spawn
	motor.half_size = frame.half_size()
	cell_motor.half_size = CELL_HALF
	for source in definition.cubes:
		cells.append({"id": source.id, "p": source.p, "start": source.p, "secured": false, "velocity": 0.0, "gravity": 2})
	for source in definition.solids:
		var lo: Vector4 = source.low; var hi: Vector4 = source.high
		var body := motor.descriptor((lo + hi) * 0.5, (hi - lo) * 0.5)
		body.bounds = {"low": lo, "high": hi}; body.source = source
		solids.append(body); obstacles.append(body)
	remember_checkpoint()

func cell(id: String) -> Dictionary:
	for c in cells:
		if c.id == id: return c
	return {}

func cell_body(c: Dictionary) -> Dictionary:
	var body := cell_motor.descriptor(c.p, CELL_HALF)
	body.bounds = {"low": c.p - CELL_HALF, "high": c.p + CELL_HALF}
	return body

func player_obstacles() -> Array[Dictionary]:
	var result: Array[Dictionary] = obstacles.duplicate()
	for c in cells:
		if c.id != held and not c.secured: result.append(cell_body(c))
	return result

func limits_low() -> Vector4:
	return definition.bounds_low - Vector4.ONE * 20

func limits_high() -> Vector4:
	return definition.bounds_high + Vector4.ONE * 20

func step(direction: Vector3, jump: bool, dt: float, forward: Vector3, sprint: bool = false) -> void:
	if won: return
	var axis: int = frame.gravity
	var axes := frame.axes()
	var blocking := player_obstacles()
	grounded = motor.sweep_blocked(player, axis, -0.035, blocking)
	if jump and grounded: velocity = JUMP
	velocity = maxf(velocity - GRAVITY * dt, -22.0)
	running = sprint and direction.length() > 0.1
	var planar := Vector3(direction.x, 0, direction.z).limit_length(1.0) * (RUN_SPEED if running else SPEED) * dt
	var requested := frame.to_world(planar)
	requested[axis] = velocity * dt
	var before := player
	player = motor.move(player, requested, [axes[0], axes[2], axis], blocking, limits_low(), limits_high())
	if absf(player[axis] - before[axis] - requested[axis]) > 0.001: velocity = 0.0
	grounded = motor.sweep_blocked(player, axis, -0.035, blocking)
	if not held.is_empty():
		var c := cell(held)
		var target := player + frame.to_world(forward * 1.25 + Vector3.UP * 0.5)
		# Held cells stay attached to the current slice; released cells keep their 4D position.
		c.p = cell_motor.move(c.p, target - c.p, axes, obstacles, limits_low(), limits_high())
		c.gravity = axis
		if c.p.distance_to(player) > 3.1:
			held = ""; message = "Tether released: cell caught on the architecture. T recalls cells."
	for c in cells:
		if c.secured or c.id == held: continue
		var gravity: int = c.gravity
		c.velocity = maxf(c.velocity - GRAVITY * dt, -22.0)
		var delta := Vector4.ZERO; delta[gravity] = c.velocity * dt
		var old: Vector4 = c.p
		c.p = cell_motor.move(c.p, delta, [gravity], obstacles, limits_low(), limits_high())
		if absf(c.p[gravity] - old[gravity] - delta[gravity]) > 0.001: c.velocity = 0.0
		if outside(c.p): c.p = c.start; c.velocity = 0.0; c.gravity = 2
	if outside(player): respawn()
	var pad := nearby_pad()
	if not pad.is_empty() and grounded: remember_checkpoint()
	var goal: Vector4 = definition.exit
	if frame.mode == definition.exit_mode and (definition.goal_circuit.is_empty() or powered.has(definition.goal_circuit)) and player.distance_to(goal) < 1.2:
		won = true; held = ""; running = false; message = "Chamber complete."

func outside(p: Vector4) -> bool:
	for axis in range(4):
		if p[axis] < definition.bounds_low[axis] - 6 or p[axis] > definition.bounds_high[axis] + 6: return true
	return false

func remember_checkpoint() -> void:
	checkpoint = {"p": player, "mode": frame.mode, "gravity": frame.gravity}

func respawn() -> void:
	falls += 1
	if not held.is_empty():
		var c := cell(held)
		c.p = c.start; c.velocity = 0.0; c.gravity = 2; held = ""
	player = checkpoint.p; frame.mode = checkpoint.mode; frame.gravity = checkpoint.gravity
	motor.half_size = frame.half_size(); velocity = 0.0; running = false
	message = "Returned to the last station. Carried cell returned to its start."
	revision += 1

func nearby_pad() -> Dictionary:
	for pad in definition.pads:
		if frame.mode in pad.modes and player.distance_to(pad.p) <= 1.35: return pad
	return {}

func switch_mode(target: int = -1) -> bool:
	var pad := nearby_pad()
	if pad.is_empty():
		message = "Change coordinate systems at a station. Walk to change W."; return false
	if target < 0:
		var i: int = pad.modes.find(frame.mode)
		target = pad.modes[(i + 1) % pad.modes.size()]
	if target == frame.mode: return false
	if not target in pad.modes:
		message = "This station supports " + mode_names(pad.modes) + "."; return false
	var next_gravity: int = Frame.priority_axis(target)
	if manual_gravity and frame.gravity in Frame.MODES[target].visible: next_gravity = frame.gravity
	return change_frame(target, next_gravity)

func choose_gravity(axis: int = -1) -> bool:
	if not manual_gravity:
		message = "Priority gravity: Z > X > Y > W. Selectable gravity is available in the pause menu."; return false
	if nearby_pad().is_empty():
		message = "Choose gravity at a station."; return false
	var visible: Array = Frame.MODES[frame.mode].visible
	if axis < 0: axis = visible[(visible.find(frame.gravity) + 1) % visible.size()]
	if not axis in visible:
		message = "Gravity must belong to the current visible axes."; return false
	if axis == frame.gravity: return false
	return change_frame(frame.mode, axis)

func change_frame(mode: int, gravity: int) -> bool:
	var old_mode: int = frame.mode; var old_gravity: int = frame.gravity
	var carry_offset := Vector3.ZERO if held.is_empty() else frame.to_view(cell(held).p - player)
	frame.mode = mode; frame.gravity = gravity
	motor.half_size = frame.half_size()
	if motor.blocked(player, player_obstacles()):
		frame.mode = old_mode; frame.gravity = old_gravity; motor.half_size = frame.half_size()
		message = "Not enough clearance for your new standing orientation. Recenter on the station."; return false
	# The player stays fixed in 4D. Held cargo is an attachment: carry its local
	# pose into the new frame and anchor its hidden coordinate to the player.
	if not held.is_empty(): reanchor_held_cell(carry_offset)
	velocity = 0.0; running = false; shifts += 1; revision += 1
	grounded = motor.sweep_blocked(player, gravity, -0.035, player_obstacles())
	if grounded: remember_checkpoint()
	message = "%s / down is -%s. Player coordinates preserved." % [Frame.MODES[mode].name, Frame.AXIS_NAMES[gravity]]
	return true

func reanchor_held_cell(local_offset: Vector3) -> void:
	var c := cell(held)
	# Sweep outward from the player to avoid placing the attachment through a wall.
	# This also brings an out-of-slice cell back without any cargo alignment test.
	c.p = cell_motor.move(player, frame.to_world(local_offset.limit_length(1.6)),
		frame.axes(), obstacles, limits_low(), limits_high())
	c.gravity = frame.gravity
	c.velocity = 0.0

static func mode_names(modes: Array) -> String:
	var names := PackedStringArray()
	for mode in modes: names.append(Frame.MODES[mode].name)
	return " / ".join(names)

func visible_box(low: Vector4, high: Vector4) -> bool:
	var hidden: int = frame.hidden()
	return player[hidden] >= low[hidden] and player[hidden] <= high[hidden]

static func ray_box(origin: Vector3, direction: Vector3, lo: Vector3, hi: Vector3, reach: float) -> float:
	var near := 0.0; var far := reach
	for axis in range(3):
		if absf(direction[axis]) < 0.00001:
			if origin[axis] < lo[axis] or origin[axis] > hi[axis]: return INF
		else:
			var a: float = (lo[axis] - origin[axis]) / direction[axis]
			var b: float = (hi[axis] - origin[axis]) / direction[axis]
			near = maxf(near, minf(a, b)); far = minf(far, maxf(a, b))
			if near > far: return INF
	return near

func focus(forward: Vector3) -> Dictionary:
	var eye: Vector3 = frame.to_view(player) + Vector3(0, 0.64, 0)
	var nearest := 2.7
	var result := {}
	for body in obstacles:
		if not visible_box(body.bounds.low, body.bounds.high): continue
		nearest = minf(nearest, ray_box(eye, forward, frame.to_view(body.bounds.low), frame.to_view(body.bounds.high), nearest))
	for s in definition.sockets:
		if powered.has(s.id) or not visible_box(s.p - Vector4.ONE * 0.65, s.p + Vector4.ONE * 0.65): continue
		var p: Vector3 = frame.to_view(s.p)
		var hit := ray_box(eye, forward, p - Vector3.ONE * 0.65, p + Vector3.ONE * 0.65, nearest)
		if hit < nearest:
			nearest = hit; result = {"kind": "socket", "data": s, "text": "E  Power " + s.label if not held.is_empty() else s.label + " / bring a cell"}
	if held.is_empty():
		for c in cells:
			if c.secured or not visible_box(c.p - CELL_HALF, c.p + CELL_HALF): continue
			var p: Vector3 = frame.to_view(c.p)
			var hit := ray_box(eye, forward, p - Vector3.ONE * 0.34, p + Vector3.ONE * 0.34, nearest)
			if hit < nearest:
				nearest = hit; result = {"kind": "cell", "data": c, "text": "E  Carry cell"}
	return result

func interact(forward: Vector3) -> bool:
	var target := focus(forward)
	if target.get("kind", "") == "socket" and not held.is_empty():
		var s: Dictionary = target.data; var c := cell(held)
		if c.p.distance_to(s.p) > 3.0:
			message = "Bring the cell closer in all four dimensions."; return false
		c.secured = true; c.p = s.p
		held = ""; powered[s.id] = true; revision += 1
		message = s.label + " powered. Cell secured in 4D."; return true
	if not held.is_empty():
		cell(held).velocity = 0.0; held = ""; message = "Cell released."; return true
	if target.get("kind", "") == "cell":
		held = target.data.id
		reanchor_held_cell(frame.to_view(cell(held).p - player))
		message = "Cell tethered. It follows you through coordinate changes."; return true
	return false

func recall_cells() -> void:
	held = ""
	for c in cells:
		if not c.secured: c.p = c.start; c.velocity = 0.0; c.gravity = 2
	message = "Unsecured cells returned. Powered receivers stay on."; revision += 1
