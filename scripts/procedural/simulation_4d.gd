extends RefCounted
## Fixed-step dynamic state only. Procedural poses remain functions of time.
## Each body's packed state: position[4], velocity[4], orientation[16], angular velocity[6].
## Bodies are reserved for future physics integration; no colliders or forces yet.
const Math4D = preload("res://scripts/geometry/transform_4d.gd")
var initial_bodies: Dictionary = {}
var bodies: Dictionary = {}

func add_body(id: int, position: Vector4, velocity: Vector4) -> void:
	var state := PackedFloat64Array()
	state.resize(30)
	for i in range(4):
		state[i] = position[i]
		state[4 + i] = velocity[i]
		state[8 + i * 4 + i] = 1.0
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
		var state: PackedFloat64Array = bodies[id]
		for axis in range(4): state[axis] += state[4 + axis] * dt
		var rotation := Math4D.new()
		for plane in range(6): rotation.angles[plane] = state[24 + plane] * dt
		var matrix := rotation.rotation_matrix()
		var old := state.duplicate()
		for row in range(4):
			for col in range(4):
				var value := 0.0
				for k in range(4): value += matrix[row * 5 + k] * old[8 + k * 4 + col]
				state[8 + row * 4 + col] = value
		bodies[id] = state
