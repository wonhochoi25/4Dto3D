extends SceneTree
## Must run with only core/physics and core/math copied into a clean project.
const World = preload("res://scripts/core/physics/physics_world_4d.gd")
const Collider = preload("res://scripts/core/physics/collision/convex_vertices_4d.gd")
const Math4D = preload("res://scripts/core/math/transform_4d.gd")
class Probe:
	static func query(_a: Dictionary,_b: Dictionary,_options: Dictionary={}) -> Dictionary:
		return {"status":"separated","reason":"Module backend replacement probe"}
class Geometry:
	var vertices: Array[Vector4] = []
var failures := 0
func check(ok: bool,label: String):
	if not ok: failures+=1; push_error(label)
func _initialize():
	var world := World.new()
	for i in range(3): check(world.configure_body(i,["static","kinematic","dynamic"][i],Vector4(1,2,3,4)),"Create body")
	world.step(0.5)
	check(world.matrices()[0][4]==0,"Static")
	check(world.matrices()[1][19]==2 and world.matrices()[2][19]==2,"Moving bodies")
	var saved := world.snapshot()
	world.step(0.5)
	check(saved[2][3]==2,"Snapshot independent")
	world.restore(saved)
	check(world.matrices()[2][19]==2,"Restore")
	world.reset()
	check(world.matrices()[2][19]==0,"Reset")
	world.set_gravity(Vector4(0,0,0,2))
	world.apply_force(2,Vector4(2,0,0,0))
	world.apply_impulse(2,Vector4(1,0,0,0))
	world.step(0.5)
	check(world.bodies[2][4]==3 and world.bodies[2][7]==5,"Isolated forces impulse gravity")
	world.remove_body(1)
	check(not world.bodies.has(1) and not world.motion_settings.has(1),"Remove")
	var geometry := Geometry.new()
	for mask in range(16):
		var p := Vector4.ZERO
		for k in range(4): p[k]=1 if mask&(1<<k) else -1
		geometry.vertices.append(p)
	var a := {"geometry":geometry,"world":Math4D.identity()}
	var b := {"geometry":geometry,"world":Math4D.translation(Vector4(0,0,0,1))}
	var result := world.query_collision(a,b,{"include_penetration":true})
	check(result.status=="intersecting" and absf(result.penetration.depth-1)<1e-4,"Standalone collision/EPA")
	world.collision_backend=Probe
	check(world.query_collision(a,b).reason.contains("probe"),"Independent backend replacement")
	world.configure_body(1,"dynamic",Vector4(0,0,0,2),{"restitution":1.0})
	world.configure_body(2,"static",Vector4.ZERO)
	world.resolve_impulses([{"body_a":1,"body_b":2,"result":result}])
	check(absf(world.linear_velocity(1).w+2)<0.0001,"Isolated backend-neutral collision impulse")
	var mass=preload("res://scripts/core/physics/mass_properties_4d.gd")
	check(world.configure_body(5,"dynamic",Vector4.ZERO,{"mass_properties":mass.uniform_box(1,Vector4(2,2,2,2),Vector4(3,0,0,0)),"angular_velocity":[90,0,0,0,0,0]}),"Isolated mass properties")
	world.set_gravity(Vector4.ZERO)
	world.step(1)
	check((Math4D.apply(world.matrices()[5],Vector4(3,0,0,0))-Vector4(3,0,0,0)).length()<0.00001,"Isolated COM pivot")
	check(absf(world.mass_properties(5).inertia[0]-2.0/3)<0.00001,"Isolated tesseract inertia")
	var prior_angular: float=world.bodies[5][24]
	world.apply_point_impulses({5:{"impulse":Vector4(0,1,0,0),"point":Vector4(4,0,0,0)}})
	check(absf(world.bodies[5][24]-prior_angular-rad_to_deg(1.5))<0.0001,"Isolated off-center impulse")
	print("Physics module failures: ",failures)
	quit(1 if failures else 0)
