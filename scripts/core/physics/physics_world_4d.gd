extends RefCounted
## Standalone physics coordinator: body lifecycle, integration, snapshots and collision backend.
## Depends only on physics helpers and math; no scene, playback, UI or IO.
## Each body's packed state: position[4], velocity[4], orientation[16], angular velocity[6].
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
		bodies[id] = Integrator.step_state(bodies[id],initial_bodies[id],body_types.get(id,"dynamic"),dt)

func remove_body(id: int) -> void:
	motion_settings.erase(id)
	body_types.erase(id)
	initial_bodies.erase(id)
	bodies.erase(id)

## Body IDs are host-owned handles. Physics has no scene graph dependency.
func configure_body(id: int, body_type: String, velocity: Vector4) -> bool:
	error = ""
	if body_type not in Body.TYPES or not velocity.is_finite():
		error = "Body type and finite initial velocity are required"
		return false
	add_body(id,Vector4.ZERO,Vector4.ZERO if body_type=="static" else velocity,body_type)
	motion_settings[id] = {"type":body_type,"velocity":velocity}
	return true

func matrices() -> Dictionary:
	var result := {}
	for id in bodies: result[id] = Body.matrix(bodies[id])
	return result

func query_collision(a: Dictionary, b: Dictionary, options: Dictionary = {}) -> Dictionary:
	return collision_backend.query(a,b,options)
