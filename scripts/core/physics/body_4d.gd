extends RefCounted
## Body-state layout belongs to physics, never to session or scene code.
## position[0:4], velocity[4:8], orientation[8:24], angular velocity[24:30].
## Reference center of mass[30:34], reserved[34:40], elapsed seconds[40], mass[41], pending force[42:46].
## Reserved slots keep earlier pose/rate offsets stable; they no longer drive motion.
const Math4D = preload("res://scripts/core/math/transform_4d.gd")
const TYPES = ["static","kinematic","dynamic"]
static func initial_state(position: Vector4, velocity: Vector4) -> PackedFloat64Array:
	var state := PackedFloat64Array()
	state.resize(46)
	state[41]=1.0
	for i in range(4):
		state[i]=position[i]
		state[4+i]=velocity[i]
		state[8+i*4+i]=1.0
	return state

static func matrix(state: PackedFloat64Array) -> PackedFloat64Array:
	var result := Math4D.identity()
	for row in range(4):
		result[row*5+4]=state[row]
		for col in range(4):
			result[row*5+col]=state[8+row*4+col]
			result[row*5+4]-=state[8+row*4+col]*state[30+col]
		result[row*5+4]+=state[30+row]
	return result
