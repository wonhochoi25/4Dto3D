extends RefCounted
## Motion law only. No lifecycle, recording, collision, scene or UI responsibilities.
const Math4D = preload("res://scripts/core/math/transform_4d.gd")
static func step_state(previous: PackedFloat64Array, initial: PackedFloat64Array, body_type: String, dt: float) -> PackedFloat64Array:
	if body_type=="static": return initial.duplicate()
	var state := previous.duplicate()
	state[40] += dt
	# Semi-implicit Euler: update rates first, then position/orientation.
	# Kinematic rates follow the prescribed clock, ignoring simulated rate changes.
	for axis in range(4):
		state[4+axis] = initial[4+axis]+initial[30+axis]*state[40] if body_type=="kinematic" else state[4+axis]+state[30+axis]*dt
	for plane in range(6):
		state[24+plane] = initial[24+plane]+initial[34+plane]*state[40] if body_type=="kinematic" else state[24+plane]+state[34+plane]*dt
	for axis in range(4): state[axis]+=state[4+axis]*dt
	# Translation-only bodies retain their orientation without matrix work.
	var rotating := false
	for plane in range(6): rotating = rotating or state[24+plane] != 0.0
	if not rotating: return state
	var rotation := Math4D.new()
	for plane in range(6): rotation.angles[plane]=state[24+plane]*dt
	var matrix := rotation.rotation_matrix()
	for row in range(4):
		for col in range(4):
			var value := 0.0
			for k in range(4): value+=matrix[row*5+k]*previous[8+k*4+col]
			state[8+row*4+col]=value
	return state
