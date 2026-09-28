extends RefCounted
## Motion law only. No lifecycle, recording, collision, scene or UI responsibilities.
const Math4D = preload("res://scripts/core/math/transform_4d.gd")
static func step_state(previous: PackedFloat64Array, initial: PackedFloat64Array, body_type: String, dt: float, gravity: Vector4 = Vector4.ZERO) -> PackedFloat64Array:
	if body_type=="static": return initial.duplicate()
	var state := previous.duplicate()
	state[40] += dt
	# Dynamics own simulated velocity. Kinematics retain host-prescribed velocity.
	if body_type=="dynamic":
		for axis in range(4): state[4+axis]+=(gravity[axis]+state[42+axis]/state[41])*dt
	# Forces are accumulated for exactly one simulation step, never replayed twice.
	for axis in range(4): state[42+axis]=0.0
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
