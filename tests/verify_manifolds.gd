extends SceneTree
const Session=preload("res://scripts/core/session_4d.gd")
const Box=preload("res://scripts/core/geometry/generators/tesseract.gd")
const Mass=preload("res://scripts/core/physics/mass_properties_4d.gd")
const Manifold=preload("res://scripts/core/physics/contact_manifold_4d.gd")
const Math4D=preload("res://scripts/core/math/transform_4d.gd")
var failures:=0
func check(ok: bool,label: String):
	if not ok: failures+=1;push_error(label)
func _initialize():
	var points=Manifold.points({"geometry":Box.new(),"world":Math4D.identity()},{"geometry":Box.new(),"world":Math4D.translation(Vector4(0,2,0,0))},Vector4(0,1,0,0))
	check(points.size()==8,"3D support volume has eight contact corners")
	for p in points: check(absf(p.y-1)<1e-6,"Common contact plane")
	for tilt in [0.0,5.0]:
		var s:=Session.new()
		s.impulse_options.iterations=64
		s.set_gravity(Vector4(0,-9.81,0,0))
		var floor_id:=s.add_geometry(Box.new(),{"scale":{"X":10,"Z":10,"W":10}})
		s.configure_body(floor_id,"static",Vector4.ZERO)
		var id:=s.add_geometry(Box.new(),{"position":{"Y":2.1},"rotation":{"XY":tilt}})
		s.configure_body(id,"dynamic",Vector4.ZERO,{"mass_properties":Mass.uniform_box(1,Vector4(2,2,2,2))})
		check(s.seek(2),"Rotational settling")
		var spin:=0.0
		for i in range(6): spin+=absf(s.physics.bodies[id][24+i])
		print("tilt ",tilt," velocity ",s.physics.linear_velocity(id)," spin ",spin)
		check(s.physics.linear_velocity(id).length()<0.03 and spin<2,"Rotational rest")
		var frame=s.physics.snapshot();s.seek(0);s.seek(2)
		check(s.physics.snapshot()==frame,"Manifold replay")
	var stack:=Session.new()
	stack.impulse_options.iterations=96
	stack.set_gravity(Vector4(0,0,0,-9.81))
	var ids:=[]
	for i in range(3):
		var id:=stack.add_geometry(Box.new(),{"position":{"W":2.0*i}})
		stack.configure_body(id,"static" if i==0 else "dynamic",Vector4.ZERO,{"mass_properties":Mass.uniform_box(1,Vector4(2,2,2,2))})
		ids.append(id)
	check(stack.seek(1),"Rotational stack simulation")
	for i in [1,2]:
		check(stack.physics.linear_velocity(ids[i]).length()<0.03,"Stack supported in W")
		for k in range(6): check(absf(stack.physics.bodies[ids[i]][24+k])<2,"Stack angular stability")
	print("Manifold failures: ",failures)
	quit(1 if failures else 0)
