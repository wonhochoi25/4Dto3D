extends SceneTree
## Regression for removal of prescribed acceleration; angular velocity still integrates.
const World=preload("res://scripts/core/physics/physics_world_4d.gd")
func _initialize():
	var w:=World.new()
	assert(not w.configure_body(0,"dynamic",Vector4.ZERO,{"acceleration":Vector4.ONE}))
	assert(not w.configure_body(0,"dynamic",Vector4.ZERO,{"angular_acceleration":[1,0,0,0,0,0]}))
	assert(w.configure_body(0,"dynamic",Vector4.ZERO,{"angular_velocity":[0,0,90,0,0,0]}))
	w.step(1)
	assert(absf(w.bodies[0][8])<1e-8 and w.bodies[0][26]==90)
	print("Acceleration removal passed")
	quit()
