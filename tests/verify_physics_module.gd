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
	print("Physics module failures: ",failures)
	quit(1 if failures else 0)
