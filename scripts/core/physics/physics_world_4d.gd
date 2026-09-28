extends RefCounted
## Standalone physics coordinator: body lifecycle, integration, snapshots and collision backend.
## Depends only on physics helpers and math; no scene, playback, UI or IO.
## Packed body state includes pose, rates, mass, pending forces and elapsed time; see body_4d.gd.
## Central forces/impulses and gravity; position correction is separate from integration; contact impulses are separate; continuous torque integration is future work.
const MassProperties = preload("res://scripts/core/physics/mass_properties_4d.gd")
const Angular = preload("res://scripts/core/physics/angular_response_4d.gd")
const Body = preload("res://scripts/core/physics/body_4d.gd")
const Integrator = preload("res://scripts/core/physics/integrator_4d.gd")
var collision_backend = preload("res://scripts/core/physics/collision/collision_backend.gd")
var motion_settings: Dictionary = {}
var error := ""
var gravity := Vector4.ZERO:
	set(value):
		if value.is_finite(): gravity=value
		else: error="Gravity must be finite"
var initial_bodies: Dictionary = {}
var bodies: Dictionary = {}
var body_types: Dictionary = {}

func add_body(id: int, position: Vector4, velocity: Vector4, body_type: String = "dynamic") -> void:
	var state := Body.initial_state(position,velocity)
	motion_settings.erase(id)
	body_types[id] = body_type
	initial_bodies[id] = state
	bodies[id] = state.duplicate()

func reset() -> void:
	restore(initial_bodies)

func snapshot() -> Dictionary:
	var result := {}
	for id in bodies: result[id] = bodies[id].duplicate()
	return result

func restore(state: Dictionary) -> void:
	bodies.clear()
	for id in state: bodies[id] = state[id].duplicate()

func step(dt: float) -> void:
	if not is_finite(dt) or dt <= 0:
		error="Step duration must be finite and positive"
		return
	for id in bodies:
		# External pose drivers are sampled by the host scene adapter, never integrated twice.
		if motion_settings.get(id,{}).get("source", "rates") == "tracks": continue
		bodies[id] = Integrator.step_state(bodies[id],initial_bodies[id],body_types.get(id,"dynamic"),dt,gravity)

func remove_body(id: int) -> void:
	motion_settings.erase(id)
	body_types.erase(id)
	initial_bodies.erase(id)
	bodies.erase(id)

## Body IDs are host-owned handles. Physics has no scene graph dependency.
## Optional motion: positive mass, restitution in [0,1], six-element angular_velocity.
## Legacy zero acceleration fields are accepted; nonzero acceleration is rejected.
## Angular velocity is degrees/s in fixed world planes.
func configure_body(id: int, body_type: String, velocity: Vector4, motion: Dictionary = {}) -> bool:
	error = ""
	var source = motion.get("source","rates")
	if source not in ["rates","tracks"] or (source == "tracks" and body_type != "kinematic"):
		error = "Track-driven motion requires a kinematic body"
		return false
	var acceleration = motion.get("acceleration",Vector4.ZERO)
	var angular = motion.get("angular_velocity",PackedFloat64Array([0,0,0,0,0,0]))
	var alpha = motion.get("angular_acceleration",PackedFloat64Array([0,0,0,0,0,0]))
	if body_type not in Body.TYPES or not velocity.is_finite() or not acceleration is Vector4:
		error = "Valid body type and finite motion components are required"
		return false
	if not acceleration.is_finite() or not valid_planes(angular) or not valid_planes(alpha):
		error = "Acceleration needs four finite components; angular fields need six finite components"
		return false
	if acceleration != Vector4.ZERO:
		error="Use forces or gravity instead of acceleration"
		return false
	for value in alpha:
		if value != 0:
			error="Angular acceleration is not supported; continuous torque integration comes later"
			return false
	var restitution = motion.get("restitution",0.0)
	if not (restitution is float or restitution is int) or not is_finite(restitution) or restitution<0 or restitution>1:
		error="Restitution must be between zero and one"
		return false
	var mass = motion.get("mass",1.0)
	if not (mass is float or mass is int) or not is_finite(mass) or mass<=0:
		error="Mass must be finite and positive"
		return false
	var mass_properties: Dictionary={}
	if motion.has("mass_properties"):
		if not motion.mass_properties is Dictionary:
			error="Mass properties must be a dictionary"
			return false
		mass_properties=MassProperties.validated(motion.mass_properties,mass)
		if mass_properties.is_empty():
			error="Mass properties require a finite center and positive definite central second moment matching body mass"
			return false
	add_body(id,Vector4.ZERO,Vector4.ZERO if body_type=="static" else velocity,body_type)
	var state: PackedFloat64Array = initial_bodies[id]
	state[41]=mass
	if not mass_properties.is_empty():
		for axis in range(4): state[30+axis]=mass_properties.center_of_mass[axis]
	if body_type != "static":
		for plane in range(6): state[24+plane]=angular[plane]
	initial_bodies[id]=state
	bodies[id]=state.duplicate()
	motion_settings[id] = {"type":body_type,"source":source,"restitution":float(restitution),"mass":float(mass),"velocity":velocity,"acceleration":acceleration,
		"angular_velocity":PackedFloat64Array(angular),"angular_acceleration":PackedFloat64Array(alpha)}
	if not mass_properties.is_empty(): motion_settings[id].mass_properties=mass_properties
	return true

static func valid_planes(values) -> bool:
	if not (values is Array or values is PackedFloat64Array or values is PackedFloat32Array): return false
	if values.size()!=6: return false
	for value in values:
		if not (value is float or value is int) or not is_finite(value): return false
	return true

func matrices() -> Dictionary:
	var result := {}
	write_matrices(result)
	return result

## Fill a caller-owned output buffer; do not expose mutable body state.
func write_matrices(result: Dictionary) -> void:
	result.clear()
	for id in bodies: result[id] = Body.matrix(bodies[id])

func query_collision(a: Dictionary, b: Dictionary, options: Dictionary = {}) -> Dictionary:
	return collision_backend.query(a,b,options)

## World axes, acceleration units. Configuration: callers reset their recordings on edits.
func set_gravity(value: Vector4) -> bool:
	if not value.is_finite():
		error="Gravity must be finite"
		return false
	gravity=value
	error=""
	return true

func dynamic_input(id: int, value: Vector4) -> bool:
	error=""
	if not bodies.has(id) or body_types.get(id)!="dynamic":
		error="Forces and impulses require an existing dynamic body"
		return false
	if not value.is_finite():
		error="Force/impulse must be finite"
		return false
	return true

## Central world-space force, accumulated until the next step. Call each step for sustained force.
func apply_force(id: int, force: Vector4) -> bool:
	if not dynamic_input(id,force): return false
	var state: PackedFloat64Array=bodies[id].duplicate()
	for axis in range(4):
		state[42+axis]+=force[axis]
		if not is_finite(state[42+axis]):
			error="Force accumulation overflow"
			return false
	bodies[id]=state
	return true

## Instantaneous central impulse: delta velocity = impulse / mass, independent of dt.
func apply_impulse(id: int, impulse: Vector4) -> bool:
	if not dynamic_input(id,impulse): return false
	var state: PackedFloat64Array=bodies[id].duplicate()
	for axis in range(4):
		state[4+axis]+=impulse[axis]/state[41]
		if not is_finite(state[4+axis]):
			error="Impulse overflow"
			return false
	bodies[id]=state
	return true

## Host may vary these prescribed rates before each step. Dynamics cannot use this API.
func set_kinematic_velocity(id: int, velocity: Vector4, angular: PackedFloat64Array = PackedFloat64Array([0,0,0,0,0,0])) -> bool:
	error=""
	if not bodies.has(id) or body_types.get(id)!="kinematic" or motion_settings.get(id,{}).get("source","rates")=="tracks":
		error="Velocity targets require a rate-driven kinematic body"
		return false
	if not velocity.is_finite() or not valid_planes(angular):
		error="Prescribed rates must be finite (six angular components)"
		return false
	var state: PackedFloat64Array=bodies[id].duplicate()
	for axis in range(4): state[4+axis]=velocity[axis]
	for plane in range(6): state[24+plane]=angular[plane]
	bodies[id]=state
	return true

## Host supplies evaluated local geometry/world matrices after stepping and hierarchy evaluation.
## Keeps physics independent of scene ownership, projection, and JSON loading.
func query_contacts(colliders: Dictionary, options: Dictionary = {"include_penetration":true}) -> Array[Dictionary]:
	return preload("res://scripts/core/physics/contact_queries_4d.gd").query(body_types,colliders,collision_backend,options)

## Caller supplies fresh world-space colliders. Default body translations are world-space.
## A scene adapter can supply a pair translator for parent-relative body coordinates.
func resolve_overlaps(colliders: Callable, options: Dictionary = {}, translate: Callable = Callable()) -> Dictionary:
	return preload("res://scripts/core/physics/overlap_solver_4d.gd").solve(self,colliders,
		translate if translate.is_valid() else translate_bodies,options)

## Atomic position-only edit; velocities, orientation, forces and initial conditions stay intact.
func translate_bodies(displacements: Dictionary) -> bool:
	var updates := {}
	for id in displacements:
		if body_types.get(id)!="dynamic": continue
		var delta: Vector4=displacements[id]
		if not delta.is_finite() or not bodies.has(id): return false
		var next: PackedFloat64Array=bodies[id].duplicate()
		for axis in range(4):
			next[axis]+=delta[axis]
			if not is_finite(next[axis]): return false
		updates[id]=next
	for id in updates: bodies[id]=updates[id]
	return not updates.is_empty()

## Consume reports from current, pre-correction geometry. Defaults assume world-space rates.
## Host callbacks adapt externally driven velocities and non-world body coordinates.
func resolve_impulses(reports: Array, velocity: Callable = Callable(), apply_pair: Callable = Callable(), options: Dictionary = {}, point_velocity: Callable = Callable(), apply_at_points: Callable = Callable()) -> Dictionary:
	return preload("res://scripts/core/physics/impulse_solver_4d.gd").solve(self,reports,
		velocity if velocity.is_valid() else linear_velocity,
		apply_pair if apply_pair.is_valid() else apply_contact_impulses,options,
		point_velocity,apply_at_points if apply_at_points.is_valid() else apply_point_impulses)

func linear_velocity(id: int) -> Vector4:
	if not bodies.has(id) or body_types.get(id)=="static": return Vector4.ZERO
	var body: PackedFloat64Array=bodies[id]
	return Vector4(body[4],body[5],body[6],body[7])

## Atomic central impulses; no changes to prescribed/static rates or angular velocity.
func apply_contact_impulses(impulses: Dictionary) -> bool:
	var updates: Dictionary={}
	for id in impulses:
		if body_types.get(id)!="dynamic": continue
		if not bodies.has(id): return false
		var impulse: Vector4=impulses[id]
		if not impulse.is_finite(): return false
		var next: PackedFloat64Array=bodies[id].duplicate()
		for axis in range(4):
			next[4+axis]+=impulse[axis]/next[41]
			if not is_finite(next[4+axis]): return false
		updates[id]=next
	for id in updates: bodies[id]=updates[id]
	return not updates.is_empty()

## Properties in the unrotated physics reference frame, returned as owned copies.
func mass_properties(id: int) -> Dictionary:
	return motion_settings.get(id,{}).get("mass_properties",{}).duplicate(true)

## Position slots store displacement of the reference center, preserving legacy offsets.
func center_of_mass(id: int) -> Vector4:
	if not bodies.has(id): return Vector4.ZERO
	var body: PackedFloat64Array=bodies[id]
	return Vector4(body[0]+body[30],body[1]+body[31],body[2]+body[32],body[3]+body[33])

## Rotate the distribution into world planes; inversion includes all six-plane coupling.
## Static/kinematic bodies still have geometric inertia, but zero response inverse inertia.
func world_mass_properties(id: int) -> Dictionary:
	var properties:=mass_properties(id)
	if properties.is_empty() or not bodies.has(id): return {}
	return MassProperties.transformed(properties,Body.matrix(bodies[id]))

func inverse_inertia_world(id: int) -> PackedFloat64Array:
	if body_types.get(id)!="dynamic":
		var zero:=PackedFloat64Array()
		zero.resize(36)
		return zero
	return world_mass_properties(id).get("inverse_inertia",PackedFloat64Array())

## Configuration update, not a runtime force: hosts must reset recorded history afterward.
func set_mass_properties(id: int, properties: Dictionary) -> bool:
	if not bodies.has(id):
		error="Unknown body ID"
		return false
	var checked:=MassProperties.validated(properties,bodies[id][41])
	if checked.is_empty():
		error="Invalid mass properties"
		return false
	if not motion_settings.has(id): motion_settings[id]={"type":body_types[id],"source":"rates"}
	motion_settings[id].mass_properties=checked
	for states in [bodies,initial_bodies]:
		var packed: PackedFloat64Array=states[id].duplicate()
		for axis in range(4): packed[30+axis]=checked.center_of_mass[axis]
		states[id]=packed
	return true

## Spin contribution at a world point. Unconfigured dynamic inertia retains linear-only response.
func angular_point_velocity(id: int, point: Vector4) -> Vector4:
	if not bodies.has(id) or body_types.get(id)=="static": return Vector4.ZERO
	if body_types.get(id)=="dynamic" and mass_properties(id).is_empty(): return Vector4.ZERO
	var omega:=PackedFloat64Array()
	for i in range(6): omega.append(deg_to_rad(bodies[id][24+i]))
	return Angular.surface_velocity(point-center_of_mass(id),omega)

func angular_inverse_mass(id: int, point: Vector4, normal: Vector4) -> float:
	var k:=Angular.moment(point-center_of_mass(id),normal)
	var response:=Angular.multiply(inverse_inertia_world(id),k)
	var result:=0.0
	for i in range(6): result+=k[i]*response[i]
	return result

## Atomic world-space impulses at contact points. Prescribed bodies never receive response.
## Each entry is {impulse: Vector4, point: Vector4}; updates both linear and angular rates.
func apply_point_impulses(entries: Dictionary) -> bool:
	var updates: Dictionary={}
	for id in entries:
		if body_types.get(id)!="dynamic": continue
		if not bodies.has(id): return false
		var impulse: Vector4=entries[id].impulse
		var point: Vector4=entries[id].point
		if not impulse.is_finite() or not point.is_finite(): return false
		var next: PackedFloat64Array=bodies[id].duplicate()
		var delta:=Angular.multiply(inverse_inertia_world(id),Angular.moment(point-center_of_mass(id),impulse))
		for axis in range(4):
			next[4+axis]+=impulse[axis]/next[41]
			if not is_finite(next[4+axis]): return false
		for plane in range(6):
			next[24+plane]+=rad_to_deg(delta[plane])
			if not is_finite(next[24+plane]): return false
		updates[id]=next
	for id in updates: bodies[id]=updates[id]
	return not updates.is_empty()
