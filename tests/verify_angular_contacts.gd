extends SceneTree
const World=preload("res://scripts/core/physics/physics_world_4d.gd")
const Mass=preload("res://scripts/core/physics/mass_properties_4d.gd")
const Angular=preload("res://scripts/core/physics/angular_response_4d.gd")
const Math4D=preload("res://scripts/core/math/transform_4d.gd")
const Session=preload("res://scripts/core/session_4d.gd")
const Box=preload("res://scripts/core/geometry/generators/tesseract.gd")
var failures:=0
func check(ok: bool,label: String):
	if not ok: failures+=1; push_error(label)
func report(n: Vector4,p: Vector4) -> Array:
	return [{"body_a":1,"body_b":2,"result":{"status":"intersecting","penetration":{"status":"penetrating","converged":true,"direction":PackedFloat64Array([n.x,n.y,n.z,n.w]),"point_a":p,"point_b":p}}}]
func energy(w) -> float:
	var result:=0.0
	for id in w.bodies:
		if w.body_types[id]!="dynamic": continue
		result+=0.5*w.bodies[id][41]*w.linear_velocity(id).length_squared()
		var tensor=w.world_mass_properties(id).inertia
		for i in range(6):
			for j in range(6): result+=0.5*deg_to_rad(w.bodies[id][24+i])*tensor[i*6+j]*deg_to_rad(w.bodies[id][24+j])
	return result
func momentum(w) -> PackedFloat64Array:
	var result:=PackedFloat64Array([0,0,0,0,0,0])
	for id in w.bodies:
		if w.body_types[id]!="dynamic": continue
		var omega:=PackedFloat64Array()
		for i in range(6): omega.append(deg_to_rad(w.bodies[id][24+i]))
		var spin=Angular.multiply(w.world_mass_properties(id).inertia,omega)
		var orbit=Angular.moment(w.center_of_mass(id),w.linear_velocity(id)*w.bodies[id][41])
		for i in range(6): result[i]+=spin[i]+orbit[i]
	return result
func _initialize():
	for plane in range(6):
		var w:=World.new()
		var axes: Vector2i=Math4D.PLANES[plane]
		var p:=Vector4.ZERO
		var n:=Vector4.ZERO
		p[axes.x]=1;n[axes.y]=1
		w.configure_body(1,"dynamic",n*2,{"mass_properties":Mass.uniform_box(1,Vector4(2,2,2,2))})
		w.configure_body(2,"static",Vector4.ZERO)
		w.resolve_impulses(report(n,p))
		check(absf(deg_to_rad(w.bodies[1][24+plane])+1.2)<0.00001,"Angular sign/units plane %d"%plane)
		check(absf((w.linear_velocity(1)+w.angular_point_velocity(1,p)).dot(n))<0.00001,"Contact normal stops")
		for other in range(6):
			if other!=plane: check(w.bodies[1][24+other]==0,"Unrelated planes unchanged")
	var w:=World.new()
	w.configure_body(1,"dynamic",Vector4(2,0,0,0),{"mass_properties":Mass.uniform_box(1,Vector4(2,2,2,2)),"restitution":1})
	w.configure_body(2,"dynamic",Vector4.ZERO,{"mass":2,"mass_properties":Mass.uniform_box(2,Vector4(2,2,2,2),Vector4(2,0,0,0)),"restitution":1})
	var before_energy:=energy(w)
	var before_momentum:=momentum(w)
	w.resolve_impulses(report(Vector4(1,0,0,0),Vector4(1,1,0,0)))
	check(absf(energy(w)-before_energy)<0.00001,"Elastic total energy")
	var after_momentum:=momentum(w)
	for i in range(6): check(absf(after_momentum[i]-before_momentum[i])<0.00001,"Angular momentum conservation")
	check((w.linear_velocity(1)+2*w.linear_velocity(2)-Vector4(2,0,0,0)).length()<0.00001,"Linear momentum conservation")
	# An impulse whose line passes through COM produces no torque.
	w=World.new()
	w.configure_body(1,"dynamic",Vector4(2,0,0,0),{"mass_properties":Mass.uniform_box(1,Vector4(2,2,2,2))})
	w.configure_body(2,"static",Vector4.ZERO)
	w.resolve_impulses(report(Vector4(1,0,0,0),Vector4(1,0,0,0)))
	check(w.linear_velocity(1)==Vector4.ZERO,"Centered impact stops")
	for i in range(6): check(w.bodies[1][24+i]==0,"Centered impact has no spin")
	# Rotation alone can make a contact approach. Kinematics are never changed by response.
	w.configure_body(1,"dynamic",Vector4.ZERO,{"mass_properties":Mass.uniform_box(1,Vector4(2,2,2,2))})
	w.configure_body(2,"kinematic",Vector4.ZERO,{"angular_velocity":[90,0,0,0,0,0]})
	w.resolve_impulses(report(Vector4(1,0,0,0),Vector4(0,1,0,0)))
	check(w.linear_velocity(1).x<0 and w.bodies[2][24]==90,"Rotating kinematic pushes body")
	var s:=Session.new()
	var a:=s.add_geometry(Box.new())
	var b:=s.add_geometry(Box.new(),{"position":{"X":2.05,"Y":1.5}})
	s.configure_body(a,"dynamic",Vector4(6,0,0,0),{"mass_properties":Mass.uniform_box(1,Vector4(2,2,2,2))})
	s.configure_body(b,"static",Vector4.ZERO)
	check(s.seek(1.0/60),"Real backend impact")
	var spin:=0.0
	for i in range(6): spin+=absf(s.physics.bodies[a][24+i])
	check(spin>0.001,"Real witness points produce rotation")
	var frame=s.physics.snapshot()
	s.seek(0);s.seek(1.0/60)
	check(s.physics.snapshot()==frame,"Angular replay exact")
	s.invalidate();s.seek(1.0/60)
	check(s.physics.snapshot()==frame,"Angular reset exact")
	print("Angular contact failures: ",failures)
	quit(1 if failures else 0)
