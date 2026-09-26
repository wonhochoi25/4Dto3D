extends RefCounted
## Public runtime API. No Node, UI, IO, mesh or projection dependency.
## Mutations invalidate simulation history; display-only edits belong to adapters.
signal state_changed(time: float)
signal scene_changed
const Scene = preload("res://scripts/core/scene/scene_4d.gd")
const Recording = preload("res://scripts/core/playback/simulation_recording.gd")
const Playback = preload("res://scripts/core/playback/playback_4d.gd")
const Math4D = preload("res://scripts/core/math/transform_4d.gd")
var scene := Scene.new()
var recording := Recording.new()
var playback := Playback.new()
var state: Dictionary = {}
var pending_seek: Variant = null
var error := ""

func _init() -> void:
	playback.time_requested.connect(request_seek)
	recording.reset(playback.start, playback.end)

func add_geometry(geometry, geometry_settings: Dictionary = {}, group_settings: Dictionary = {}) -> int:
	var id := scene.add_geometry(geometry, geometry_settings, group_settings, playback.start)
	if id == 0:
		error = scene.error
		return 0
	invalidate()
	scene_changed.emit()
	return id

func set_expressions(id: int, group: bool, expressions: Dictionary, keep_anchor: bool = true) -> bool:
	error = ""
	if not scene.objects.has(id):
		error = "Unknown object ID"
		return false
	var track = scene.objects[id].group if group else scene.objects[id].track
	track.keep_anchor_in_place = keep_anchor
	var before: Dictionary = track.sources.duplicate()
	if not track.apply_sources(expressions, playback.time):
		error = track.error
		return false
	if track.sources != before: invalidate()
	return true

func set_geometry_expressions(id: int, expressions: Dictionary, keep_anchor: bool = true) -> bool:
	return set_expressions(id, false, expressions, keep_anchor)

func set_group_expressions(id: int, expressions: Dictionary, keep_anchor: bool = true) -> bool:
	return set_expressions(id, true, expressions, keep_anchor)

func reparent(id: int, parent: int, keep_world: bool = true) -> bool:
	if not scene.objects.has(id) or (parent != 0 and not scene.objects.has(parent)): return false
	if not scene.can_parent(id, parent):
		error = "Cannot parent an object to itself or its descendants"
		return false
	if keep_world:
		if not scene.reparent(id, parent, playback.time):
			error = scene.error
			return false
	else: scene.entries[id].parent = parent
	invalidate()
	scene_changed.emit()
	return true

func remove_object(id: int) -> bool:
	if not scene.remove_object(id, playback.time):
		error = scene.error
		return false
	recording.simulation.initial_bodies.erase(id)
	recording.simulation.bodies.erase(id)
	invalidate()
	scene_changed.emit()
	return true

func replace_geometry(id: int, geometry) -> void:
	scene.objects[id].geometry = geometry
	invalidate()

## Dynamic motion is local to the object's group parent frame. Geometry track remains usable.
func make_dynamic(id: int, position: Vector4, velocity: Vector4) -> void:
	assert(scene.objects.has(id))
	recording.simulation.add_body(id, position, velocity)
	invalidate()

func make_procedural(id: int) -> void:
	recording.simulation.initial_bodies.erase(id)
	recording.simulation.bodies.erase(id)
	invalidate()

func sync_dynamic() -> void:
	scene.dynamic_matrices.clear()
	for id in recording.simulation.bodies:
		var body: PackedFloat64Array = recording.simulation.bodies[id]
		var matrix := Math4D.identity()
		for row in range(4):
			matrix[row * 5 + 4] = body[row]
			for col in range(4): matrix[row * 5 + col] = body[8 + row * 4 + col]
		scene.dynamic_matrices[id] = matrix

func validate_step(time: float) -> bool:
	sync_dynamic()
	var evaluated = scene.sample(time)
	if evaluated == null: error = scene.error
	return evaluated != null

func invalidate() -> void:
	pending_seek = null
	playback.busy = false
	playback.pause()
	recording.reset(playback.start, playback.end)
	playback.time = playback.start
	seek(playback.start)

func seek(time: float, budget: int = 2147483647) -> bool:
	if not is_finite(time): return false
	error = ""
	if not recording.seek(time, validate_step, budget):
		playback.pause()
		sync_dynamic()
		return false
	if not recording.ready_at(time):
		sync_dynamic()
		return true
	sync_dynamic()
	var evaluated = scene.sample(recording.time_at(recording.current_step))
	if evaluated == null:
		error = scene.error
		return false
	state = evaluated
	playback.time = recording.time_at(recording.current_step)
	state_changed.emit(playback.time)
	return true

func request_seek(time: float) -> void:
	pending_seek = time
	playback.busy = true
	advance_seek()

func advance_seek(budget: int = 120) -> void:
	if pending_seek == null: return
	var target: float = pending_seek
	if not seek(target, budget) or recording.ready_at(target):
		pending_seek = null
		playback.busy = false

func advance(delta: float) -> void:
	if pending_seek != null: advance_seek()
	else: playback.advance(delta)

func set_range(from: float, to: float) -> bool:
	if not is_finite(from) or not is_finite(to) or from >= to: return false
	var reset_needed := from != playback.start
	playback.pause()
	playback.start = from
	playback.end = to
	pending_seek = null
	playback.busy = false
	if reset_needed: invalidate()
	else:
		recording.trim(to)
		request_seek(clampf(playback.time, from, to))
	return true

func world_vertices(id: int) -> Array[Vector4]:
	return scene.world_vertices(id, state)

func play(direction: int = 1) -> void:
	playback.direction = clampi(direction, -1, 1)

func pause() -> void:
	playback.pause()

func cancel_seek() -> void:
	pending_seek = null
	playback.busy = false
	playback.pause()
	recording.simulation.restore(recording.frames[recording.current_step] if not recording.frames.is_empty() else {})
	sync_dynamic()
