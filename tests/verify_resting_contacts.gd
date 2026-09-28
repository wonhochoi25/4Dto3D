extends SceneTree
const Session=preload("res://scripts/core/session_4d.gd")
const World=preload("res://scripts/core/physics/physics_world_4d.gd")
const Box=preload("res://scripts/core/geometry/generators/tesseract.gd")
var failures:=0
func check(ok: bool,label: String):
	if not ok: failures+=1; push_error(label)
func contact(a: int,b: int,status: String="intersecting",gap: float=0) -> Dictionary:
	return {"body_a":a,"body_b":b,"result":{"status":status,"gap":gap,"direction":PackedFloat64Array([0,1,0,0]),"penetration":{"status":"penetrating","converged":true,"direction":PackedFloat64Array([0,1,0,0])}}}
func _initialize():
	var w:=World.new()
	w.configure_body(1,"static",Vector4.ZERO)
	w.configure_body(2,"dynamic",Vector4(0,-0.1,0,0),{"restitution":1})
	w.resolve_impulses([contact(1,2)])
	check(absf(w.linear_velocity(2).y)<1e-8,"Slow impact does not bounce")
	w.configure_body(2,"dynamic",Vector4(0,-3,0,0),{"restitution":1})
	w.resolve_impulses([contact(1,2)])
	check(absf(w.linear_velocity(2).y-3)<1e-8,"Fast impact still bounces")
	w.configure_body(2,"dynamic",Vector4(0,-1,0,0))
	w.resolve_impulses([contact(1,2,"separated",0.002)])
	check(absf(w.linear_velocity(2).y+0.12)<1e-6,"Speculative constraint allows gap closure")
	w.configure_body(2,"dynamic",Vector4(0,1,0,0))
	w.resolve_impulses([contact(1,2)])
	check(w.linear_velocity(2).y==1,"Surface never pulls leaving body back")
	w.configure_body(2,"dynamic",Vector4(0,-1,0,0))
	w.resolve_impulses([contact(1,2,"separated",0.1)])
	check(w.linear_velocity(2).y==-1,"Outside margin unaffected")
	# Reverse pair order deliberately requires repeated propagation through the stack.
	w.configure_body(2,"dynamic",Vector4(0,-1,0,0))
	w.configure_body(3,"dynamic",Vector4(0,-1,0,0),{"mass":2})
	var solved=w.resolve_impulses([contact(2,3),contact(1,2)],Callable(),Callable(),{"iterations":128})
	check(solved.iterations>1 and absf(w.linear_velocity(3).y)<0.00001,"Iterative support propagation")
	var saved=w.snapshot()
	check(w.resolve_impulses([],Callable(),Callable(),{"dt":0}).status=="invalid_options" and saved==w.snapshot(),"Invalid solver settings atomic")
	for axis in [1,3]:
		var s:=Session.new()
		var gravity:=Vector4.ZERO
		gravity[axis]=-9.81
		s.set_gravity(gravity)
		var floor_id:=s.add_geometry(Box.new())
		var settings={"position":{("Y" if axis==1 else "W"):2.2}}
		var id:=s.add_geometry(Box.new(),settings)
		s.configure_body(floor_id,"static",Vector4.ZERO)
		s.configure_body(id,"dynamic",Vector4.ZERO,{"restitution":0.1})
		check(s.seek(2.0),"Settle under gravity")
		check(absf(s.physics.linear_velocity(id)[axis])<0.0001,"Resting speed axis %d"%axis)
		var center: float=2.2+s.physics.bodies[id][axis]
		check(absf(center-2.0)<0.002,"Resting position axis %d"%axis)
		var frame=s.physics.snapshot()
		s.seek(1.0);s.seek(2.0)
		check(s.physics.snapshot()==frame,"Resting replay exact")
		s.invalidate();s.seek(2.0)
		check(s.physics.snapshot()==frame,"Resting reset exact")
		print("Resting axis ",axis," passed checks")
	# Three dynamic bodies, mixed masses, shared support chain.
	var s:=Session.new()
	s.set_gravity(Vector4(0,-9.81,0,0))
	var ids: Array[int]=[]
	for i in range(4):
		var id:=s.add_geometry(Box.new(),{"position":{"Y":i*2.0}})
		s.configure_body(id,"static" if i==0 else "dynamic",Vector4.ZERO,{"mass":float(i+1)})
		ids.append(id)
	check(s.seek(2.0),"Stack simulated")
	for i in range(1,4):
		check(absf(s.physics.linear_velocity(ids[i]).y)<0.005,"Stack speed %d"%i)
		check(absf(s.physics.bodies[ids[i]][1])<0.015,"Stack drift %d"%i)
	print("Resting contact failures: ",failures)
	quit(1 if failures else 0)
