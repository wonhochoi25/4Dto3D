extends RefCounted
## Public runtime API. No Node, UI, IO, mesh or projection dependency.
## Mutations invalidate simulation history; display-only edits belong to adapters.
signal state_changed(time: float)
signal scene_changed
## Fires for evaluated simulation samples, including intermediate steps and replay. Read-only observers.
signal contacts_evaluated(time: float, reports: Array)
var contact_reports: Array[Dictionary]=[]
var validated_contacts: Array[Dictionary]=[]
## Configuration changes require invalidate() to restart recorded history.
var collision_impulses_enabled := true
var impulse_result: Dictionary = {}
var impulse_options: Dictionary = {"iterations":32,"contact_margin":0.005,"bounce_threshold":1.0,"velocity_tolerance":0.000001}
var prescribed_contact_velocities: Dictionary = {}
var prescribed_contact_frames: Dictionary = {}
var overlap_correction_enabled := true
var overlap_options: Dictionary = {"slop":0.0001,"iterations":8}
var overlap_result: Dictionary = {}
var correction_time := 0.0
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
	# Preserve authored starting poses; response begins on the first simulated step.
	overlap_result={}
	impulse_result={}
	if collision_impulses_enabled and time>playback.start and physics.bodies.size()>1:
		correction_time=time
		var before=scene.sample(time)
		if before==null: return false
		prepare_contact_velocities(before,time)
		var reports=physics.query_contacts(Binding.colliders(scene,physics,before),{"include_penetration":true})
		var options:=impulse_options.duplicate()
		options.dt=Recording.STEP
		impulse_result=physics.resolve_impulses(reports,contact_velocity,contact_impulses,options,contact_point_velocity,contact_point_impulses)
	if overlap_correction_enabled and time>playback.start and physics.bodies.size()>1:
		correction_time=time
		overlap_result=physics.resolve_overlaps(correction_colliders,overlap_options,correct_positions)
		if not sync_dynamic(): return false
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
	if not Binding.configure(scene,physics,id,body_type,initial_velocity,motion,playback.start):
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
## Physics owns mutable state afterward, including velocity and pending forces.
func configure_dynamic_initial(id: int, expressions: Dictionary) -> bool:
	var track := InitialMotion.new()
	if not track.configure(expressions,playback.start):
		error=track.error
		return false
	var values: Dictionary=track.sample(playback.start)
	values.mass=physics.motion_settings.get(id,{}).get("mass",1.0)
	values.restitution=physics.motion_settings.get(id,{}).get("restitution",0.0)
	if physics.motion_settings.get(id,{}).has("local_mass_properties"): values.mass_properties=physics.motion_settings[id].local_mass_properties
	if not Binding.configure(scene,physics,id,"dynamic",values.velocity,values,playback.start):
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
			values.restitution=physics.motion_settings.get(id,{}).get("restitution",0.0)
			var local_properties: Dictionary=physics.motion_settings.get(id,{}).get("local_mass_properties",{}).duplicate(true)
			var reference_properties:=physics.mass_properties(id)
			if not reference_properties.is_empty(): values.mass_properties=reference_properties
			physics.configure_body(id,"dynamic",values.velocity,values)
			if not local_properties.is_empty(): physics.motion_settings[id].local_mass_properties=local_properties
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

## Adapter callbacks keep physics independent of hierarchy and transform tracks.
func correction_colliders() -> Dictionary:
	if not sync_dynamic(): return {}
	var evaluated = scene.sample(correction_time)
	return {} if evaluated==null else Binding.colliders(scene,physics,evaluated)

func correct_positions(displacements: Dictionary) -> bool:
	var evaluated = scene.sample(correction_time)
	if evaluated==null: return false
	var local := {}
	for id in displacements:
		if physics.body_types.get(id)!="dynamic": continue
		var delta: Vector4=displacements[id]
		if not physics.motion_settings.has(id):
			# Legacy make_dynamic stores position in parent * offset coordinates.
			var entry: Dictionary=scene.entries[id]
			var math4d=preload("res://scripts/core/math/transform_4d.gd")
			var graph=preload("res://scripts/core/scene/transform_graph_4d.gd")
			var inverse=graph.inverse(math4d.multiply(evaluated[entry.parent].world,entry.offset))
			if inverse.is_empty(): return false
			delta=math4d.apply(inverse,delta,0.0)
		local[id]=delta
	return physics.translate_bodies(local)

## Track-driven transforms are retained for material-point backward differences.
## Center velocities remain the fallback when witnesses or inverse transforms are unavailable.
func prepare_contact_velocities(current: Dictionary, time: float) -> void:
	prescribed_contact_velocities.clear()
	prescribed_contact_frames.clear()
	var previous: Variant=null
	for id in physics.body_types:
		var driven: bool=physics.motion_settings.get(id,{}).get("source","rates")=="tracks"
		var inherited_static: bool=physics.body_types[id]=="static" and scene.entries[id].parent!=0
		if not driven and not inherited_static: continue
		if previous==null:
			# The recorder's last frame is the actual previous physics step, even during long seeks.
			var current_bodies=physics.snapshot()
			if not recording.frames.is_empty(): physics.restore(recording.frames.back())
			sync_dynamic()
			previous=scene.sample(time-Recording.STEP)
			physics.restore(current_bodies)
			sync_dynamic()
		if previous==null: continue
		var leaf: int=scene.objects[id].leaf_id
		prescribed_contact_frames[id]={"current":current[leaf].world,"previous":previous[leaf].world}
		var center:=Vector4.ZERO
		var vertices=scene.objects[id].geometry.vertices
		for vertex in vertices: center+=vertex
		if not vertices.is_empty(): center/=vertices.size()
		var math4d=preload("res://scripts/core/math/transform_4d.gd")
		prescribed_contact_velocities[id]=(math4d.apply(current[leaf].world,center)-math4d.apply(previous[leaf].world,center))/Recording.STEP

func contact_velocity(id: int) -> Vector4:
	if prescribed_contact_velocities.has(id): return prescribed_contact_velocities[id]
	var velocity:=physics.linear_velocity(id)
	if not physics.motion_settings.has(id):
		var evaluated=scene.sample(correction_time)
		var entry: Dictionary=scene.entries[id]
		var math4d=preload("res://scripts/core/math/transform_4d.gd")
		velocity=math4d.apply(math4d.multiply(evaluated[entry.parent].world,entry.offset),velocity,0.0)
	return velocity

func contact_impulses(impulses: Dictionary) -> bool:
	var local:=impulses.duplicate()
	for id in local:
		if physics.body_types.get(id)!="dynamic" or physics.motion_settings.has(id): continue
		var evaluated=scene.sample(correction_time)
		if evaluated==null: return false
		var entry: Dictionary=scene.entries[id]
		var math4d=preload("res://scripts/core/math/transform_4d.gd")
		var graph=preload("res://scripts/core/scene/transform_graph_4d.gd")
		var inverse=graph.inverse(math4d.multiply(evaluated[entry.parent].world,entry.offset))
		if inverse.is_empty(): return false
		local[id]=math4d.apply(inverse,local[id],0.0)
	return physics.apply_contact_impulses(local)

## Track-driven contacts use motion of the same material point, including rotation/scale.
func contact_point_velocity(id: int, point: Vector4) -> Vector4:
	if prescribed_contact_frames.has(id):
		var frame: Dictionary=prescribed_contact_frames[id]
		var graph=preload("res://scripts/core/scene/transform_graph_4d.gd")
		var math4d=preload("res://scripts/core/math/transform_4d.gd")
		var inverse=graph.inverse(frame.current)
		if not inverse.is_empty():
			var local=math4d.apply(inverse,point)
			return (point-math4d.apply(frame.previous,local))/Recording.STEP
		return contact_velocity(id) # Singular transform: center-motion fallback.
	return contact_velocity(id)+physics.angular_point_velocity(id,point)

func contact_point_impulses(entries: Dictionary) -> bool:
	var local:=entries.duplicate(true)
	for id in local:
		if physics.body_types.get(id)!="dynamic" or physics.motion_settings.has(id): continue
		# Legacy parent-relative bodies have no inertia; only translate their linear impulse.
		var evaluated=scene.sample(correction_time)
		if evaluated==null: return false
		var entry: Dictionary=scene.entries[id]
		var math4d=preload("res://scripts/core/math/transform_4d.gd")
		var graph=preload("res://scripts/core/scene/transform_graph_4d.gd")
		var inverse=graph.inverse(math4d.multiply(evaluated[entry.parent].world,entry.offset))
		if inverse.is_empty(): return false
		local[id].impulse=math4d.apply(inverse,local[id].impulse,0.0)
	return physics.apply_point_impulses(local)
