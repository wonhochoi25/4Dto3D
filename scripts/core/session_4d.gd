extends RefCounted
## Public runtime API. No Node, UI, IO, mesh or projection dependency.
## Mutations invalidate simulation history; display-only edits belong to adapters.
signal state_changed(time: float)
signal scene_changed
## Fires for evaluated simulation samples, including intermediate steps and replay. Read-only observers.
signal contacts_evaluated(time: float, reports: Array)
var contact_reports: Array[Dictionary]=[]
var validated_contacts: Array[Dictionary]=[]
var contact_options: Dictionary={"include_penetration":true}
const Scene = preload("res://scripts/core/scene/scene_4d.gd")
const Recording = preload("res://scripts/core/playback/simulation_recording.gd")
const Playback = preload("res://scripts/core/playback/playback_4d.gd")
const Physics = preload("res://scripts/core/physics/physics_world_4d.gd")
const Binding = preload("res://scripts/core/scene/physics_binding_4d.gd")
var physics_binding := Binding.new()
var validated_state: Variant = null
var validated_time := NAN
const InitialMotion = preload("res://scripts/core/animation/initial_motion_4d.gd")
var initial_motion_tracks: Dictionary = {}
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
	initial_motion_tracks.erase(id)
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
	initial_motion_tracks.erase(id)
	physics.add_body(id, position, velocity)
	invalidate()

func make_procedural(id: int) -> void:
	initial_motion_tracks.erase(id)
	physics.remove_body(id)
	invalidate()

func sync_dynamic() -> bool:
	return physics_binding.sync(scene,physics,playback.start)

func validate_step(time: float) -> bool:
	if not sync_dynamic():
		error = scene.error
		return false
	var evaluated = scene.sample(time)
	validated_state = evaluated
	validated_time = time
	if evaluated == null: error = scene.error
	else: validated_contacts = evaluate_contacts(evaluated,time)
	return evaluated != null

func invalidate() -> void:
	if not refresh_initial_motion(playback.start):
		playback.pause()
		return
	physics_binding.invalidate()
	pending_seek = null
	playback.busy = false
	playback.pause()
	recording.reset(playback.start, playback.end)
	playback.time = playback.start
	seek(playback.start)

func seek(time: float, budget: int = 2147483647) -> bool:
	if not is_finite(time): return false
	error = Binding.run_error(scene,physics) if time > playback.start else ""
	if not error.is_empty():
		playback.pause()
		return false
	validated_state = null
	validated_time = NAN
	validated_contacts=[]
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
		if evaluated != null: validated_contacts=evaluate_contacts(evaluated,target_time)
	if evaluated == null:
		error = scene.error
		return false
	contact_reports = validated_contacts
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
	if not refresh_initial_motion(from,false): return false
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

## Explicit read-only narrow-phase query, independent of automatic per-step reports.
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
	initial_motion_tracks.erase(id)
	error = ""
	invalidate()
	return true

func start_body_motion() -> bool:
	error = Binding.run_error(scene,physics)
	if not error.is_empty(): return false
	if playback.time >= playback.end: invalidate()
	play(1)
	return true

## Reuse scene tracks as a kinematic pose driver; rates are not additionally applied.
func configure_kinematic(id: int) -> bool:
	return configure_body(id,"kinematic",Vector4.ZERO,{"source":"tracks"})

## Transform tracks supply the initial pose; these expressions supply initial rates.
## Physics owns mutable state afterward, including stored acceleration.
func configure_dynamic_initial(id: int, expressions: Dictionary) -> bool:
	var track := InitialMotion.new()
	if not track.configure(expressions,playback.start):
		error=track.error
		return false
	var values: Dictionary=track.sample(playback.start)
	values.mass=physics.motion_settings.get(id,{}).get("mass",1.0)
	if not Binding.configure(scene,physics,id,"dynamic",values.velocity,values):
		error=Binding.configuration_error(scene,physics,id)
		return false
	initial_motion_tracks[id]=track
	invalidate()
	return true

## Evaluate every body before committing, so invalid start-time edits are atomic.
func refresh_initial_motion(time: float, commit: bool = true) -> bool:
	var evaluated := {}
	for id in initial_motion_tracks:
		var values = initial_motion_tracks[id].sample(time)
		if values==null:
			error="Body %d: %s" % [id,initial_motion_tracks[id].error]
			return false
		evaluated[id]=values
	if commit:
		for id in evaluated:
			var values: Dictionary=evaluated[id]
			values.mass=physics.motion_settings.get(id,{}).get("mass",1.0)
			physics.configure_body(id,"dynamic",values.velocity,values)
	return true

## Runtime inputs branch recorded history; reset discards these inputs, restoring launch state.
func apply_force(id: int, force: Vector4) -> bool:
	if pending_seek!=null:
		error="Finish or cancel the pending seek before applying inputs"
		return false
	if not physics.apply_force(id,force):
		error=physics.error
		return false
	recording.commit_current()
	error=""
	return true

func apply_impulse(id: int, impulse: Vector4) -> bool:
	if pending_seek!=null:
		error="Finish or cancel the pending seek before applying inputs"
		return false
	if not physics.apply_impulse(id,impulse):
		error=physics.error
		return false
	recording.commit_current()
	error=""
	return true

func set_gravity(value: Vector4) -> bool:
	if not physics.set_gravity(value):
		error=physics.error
		return false
	invalidate()
	return true

func set_kinematic_velocity(id: int, velocity: Vector4, angular: PackedFloat64Array = PackedFloat64Array([0,0,0,0,0,0])) -> bool:
	if pending_seek!=null:
		error="Finish or cancel the pending seek before applying inputs"
		return false
	if not physics.set_kinematic_velocity(id,velocity,angular):
		error=physics.error
		return false
	recording.commit_current()
	error=""
	return true

## Scene has already evaluated the authoritative 4D geometry; display projection is absent.
func evaluate_contacts(evaluated: Dictionary, time: float) -> Array[Dictionary]:
	var reports := physics.query_contacts(Binding.colliders(scene,physics,evaluated),contact_options)
	contacts_evaluated.emit(time,reports.duplicate(true))
	return reports
