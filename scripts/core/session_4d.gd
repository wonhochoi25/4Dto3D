extends RefCounted
## Public runtime API. No Node, UI, IO, mesh or projection dependency.
## Mutations invalidate simulation history; display-only edits belong to adapters.
signal state_changed(time: float)
signal scene_changed
const Scene = preload("res://scripts/core/scene/scene_4d.gd")
const Recording = preload("res://scripts/core/playback/simulation_recording.gd")
const Playback = preload("res://scripts/core/playback/playback_4d.gd")
const Physics = preload("res://scripts/core/physics/physics_world_4d.gd")
const Binding = preload("res://scripts/core/scene/physics_binding_4d.gd")
var physics_binding := Binding.new()
var validated_state: Variant = null
var validated_time := NAN
var scene := Scene.new()
var physics := Physics.new()
var recording := Recording.new(physics)
var playback := Playback.new()
var state: Dictionary = {}
var pending_seek: Variant = null
var error := ""
# Physics translation offsets; legacy make_dynamic retains its original semantics.
var motion_settings: Dictionary:
	get: return physics.motion_settings

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
	physics.remove_body(id)
	invalidate()
	scene_changed.emit()
	return true

func replace_geometry(id: int, geometry) -> void:
	scene.objects[id].geometry = geometry
	invalidate()

## Dynamic motion is local to the object's group parent frame. Geometry track remains usable.
func make_dynamic(id: int, position: Vector4, velocity: Vector4) -> void:
	assert(scene.objects.has(id))
	physics.add_body(id, position, velocity)
	invalidate()

func make_procedural(id: int) -> void:
	physics.remove_body(id)
	invalidate()

func sync_dynamic() -> void:
	physics_binding.sync(scene,physics,playback.start)

func validate_step(time: float) -> bool:
	sync_dynamic()
	var evaluated = scene.sample(time)
	validated_state = evaluated
	validated_time = time
	if evaluated == null: error = scene.error
	return evaluated != null

func invalidate() -> void:
	physics_binding.invalidate()
	pending_seek = null
	playback.busy = false
	playback.pause()
	recording.reset(playback.start, playback.end)
	playback.time = playback.start
	seek(playback.start)

func seek(time: float, budget: int = 2147483647) -> bool:
	if not is_finite(time): return false
	error = ""
	validated_state = null
	validated_time = NAN
	if not recording.seek(time, validate_step, budget):
		playback.pause()
		sync_dynamic()
		return false
	if not recording.ready_at(time):
		sync_dynamic()
		return true
	var target_time := recording.time_at(recording.current_step)
	var evaluated = validated_state
	if validated_time != target_time or evaluated == null:
		sync_dynamic()
		evaluated = scene.sample(target_time)
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
	physics.restore(recording.frames[recording.current_step] if not recording.frames.is_empty() else {})
	sync_dynamic()

## Replace this script with any backend implementing docs/COLLISION_BACKEND.md.
## Assigning another script here also allows isolated backend tests/integration.
var collision_backend:
	get: return physics.collision_backend
	set(value): physics.collision_backend = value

## Read-only narrow-phase query. Other session features do not invoke this backend.
func query_collision(a_id: int, b_id: int, include_penetration: bool = false) -> Dictionary:
	if a_id == b_id or not scene.objects.has(a_id) or not scene.objects.has(b_id):
		return {"status":"indeterminate","reason":"Choose two different existing objects"}
	var a: Dictionary = scene.objects[a_id]
	var b: Dictionary = scene.objects[b_id]
	if not state.has(a.leaf_id) or not state.has(b.leaf_id):
		return {"status":"indeterminate","reason":"No valid evaluated state"}
	return physics.query_collision(
		{"geometry":a.geometry,"world":state[a.leaf_id].world},
		{"geometry":b.geometry,"world":state[b.leaf_id].world},
		{"include_penetration":include_penetration})

## Physics-mode motion is an offset from the edited group pose. All edits restart history.
func configure_body(id: int, body_type: String, initial_velocity: Vector4, motion: Dictionary = {}) -> bool:
	if not Binding.configure(scene,physics,id,body_type,initial_velocity,motion):
		error = Binding.configuration_error(scene,physics,id)
		return false
	error = ""
	invalidate()
	return true

func start_body_motion() -> bool:
	error = Binding.run_error(scene,physics)
	if not error.is_empty(): return false
	if playback.time >= playback.end: invalidate()
	play(1)
	return true
