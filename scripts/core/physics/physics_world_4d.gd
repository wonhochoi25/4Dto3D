extends RefCounted
## Standalone physics coordinator: body lifecycle, integration, snapshots and collision backend.
## Depends only on physics helpers and math; no scene, playback, UI or IO.
## Packed body state includes pose, rates, accelerations and elapsed time; see body_4d.gd.
## Central forces/impulses and gravity; collision response and torque are separate future work.
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
## Optional motion: positive mass and six-element angular_velocity.
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
			error="Angular acceleration is not supported; torque/inertia come later"
			return false
	var mass = motion.get("mass",1.0)
	if not (mass is float or mass is int) or not is_finite(mass) or mass<=0:
		error="Mass must be finite and positive"
		return false
	add_body(id,Vector4.ZERO,Vector4.ZERO if body_type=="static" else velocity,body_type)
	var state: PackedFloat64Array = initial_bodies[id]
	state[41]=mass
	if body_type != "static":
		for plane in range(6): state[24+plane]=angular[plane]
	initial_bodies[id]=state
	bodies[id]=state.duplicate()
	motion_settings[id] = {"type":body_type,"source":source,"mass":float(mass),"velocity":velocity,"acceleration":acceleration,
		"angular_velocity":PackedFloat64Array(angular),"angular_acceleration":PackedFloat64Array(alpha)}
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
