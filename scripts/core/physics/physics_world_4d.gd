extends RefCounted
## Standalone physics coordinator: body lifecycle, integration, snapshots and collision backend.
## Depends only on physics helpers and math; no scene, playback, UI or IO.
## Packed body state includes pose, rates, accelerations and elapsed time; see body_4d.gd.
## Integration does not invoke collision detection; no forces or response yet.
const Body = preload("res://scripts/core/physics/body_4d.gd")
const Integrator = preload("res://scripts/core/physics/integrator_4d.gd")
var collision_backend = preload("res://scripts/core/physics/collision/collision_backend.gd")
var motion_settings: Dictionary = {}
var error := ""
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
	for id in bodies:
		# External pose drivers are sampled by the host scene adapter, never integrated twice.
		if motion_settings.get(id,{}).get("source", "rates") == "tracks": continue
		bodies[id] = Integrator.step_state(bodies[id],initial_bodies[id],body_types.get(id,"dynamic"),dt)

func remove_body(id: int) -> void:
	motion_settings.erase(id)
	body_types.erase(id)
	initial_bodies.erase(id)
	bodies.erase(id)

## Body IDs are host-owned handles. Physics has no scene graph dependency.
## Optional motion: acceleration Vector4 and six-element angular_velocity/angular_acceleration.
## Angular quantities are degrees/s and degrees/s² in fixed world planes.
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
	add_body(id,Vector4.ZERO,Vector4.ZERO if body_type=="static" else velocity,body_type)
	var state: PackedFloat64Array = initial_bodies[id]
	if body_type != "static":
		for axis in range(4): state[30+axis]=acceleration[axis]
		for plane in range(6):
			state[24+plane]=angular[plane]
			state[34+plane]=alpha[plane]
	initial_bodies[id]=state
	bodies[id]=state.duplicate()
	motion_settings[id] = {"type":body_type,"source":source,"velocity":velocity,"acceleration":acceleration,
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
