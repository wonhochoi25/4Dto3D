extends SceneTree
const World=preload("res://scripts/core/physics/physics_world_4d.gd")
const Mass=preload("res://scripts/core/physics/mass_properties_4d.gd")
var failures:=0
func check(ok: bool,label: String):
	if not ok: failures+=1;push_error(label)
func _initialize():
	for mu in [0.0,0.5,2.0]:
		var w:=World.new()
		w.configure_body(1,"static",Vector4.ZERO,{"friction":mu})
		w.configure_body(2,"dynamic",Vector4(1,-1,1,1),{"friction":mu})
		var report={"body_a":1,"body_b":2,"result":{"status":"intersecting","penetration":{"status":"touching","converged":true,"direction":PackedFloat64Array([0,1,0,0])}}}
		w.resolve_impulses([report])
		var v:=w.linear_velocity(2)
		check(absf(v.y)<0.00001,"Normal solved")
		check(absf(v.x-v.z)<0.00001 and absf(v.z-v.w)<0.00001,"Isotropic 3D tangent response")
		var expected:=maxf(0,sqrt(3)-mu)
		check(absf(v.length()-expected)<0.00001,"Coulomb bound and stopping")
		check(v.length_squared()<=4,"Friction cannot add energy")
	var Session=preload("res://scripts/core/session_4d.gd")
	var Box=preload("res://scripts/core/geometry/generators/tesseract.gd")
	var s=Session.new()
	s.set_gravity(Vector4(0,-9.81,0,0))
	var floor_id=s.add_geometry(Box.new(),{"scale":{"X":10,"Z":10,"W":10}})
	var body=s.add_geometry(Box.new(),{"position":{"Y":2}})
	s.configure_body(floor_id,"static",Vector4.ZERO,{"friction":0.8})
	s.configure_body(body,"dynamic",Vector4(2,0,0,1),{"friction":0.8,"mass_properties":Mass.uniform_box(1,Vector4(2,2,2,2))})
	check(s.seek(2),"Sliding scene simulated")
	check(s.physics.linear_velocity(body).length()<0.02,"Real manifold friction stops sliding")
	var snapshot=s.physics.snapshot();s.seek(0);s.seek(2)
	check(s.physics.snapshot()==snapshot,"Friction replay exact")
	print("Friction failures: ",failures)
	quit(1 if failures else 0)
