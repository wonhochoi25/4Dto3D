extends SceneTree
const Mass=preload("res://scripts/core/physics/mass_properties_4d.gd")
const World=preload("res://scripts/core/physics/physics_world_4d.gd")
const Math4D=preload("res://scripts/core/math/transform_4d.gd")
const Session=preload("res://scripts/core/session_4d.gd")
const Box=preload("res://scripts/core/geometry/generators/tesseract.gd")
var failures:=0
func check(ok: bool,label: String):
	if not ok: failures+=1; push_error(label)
func _initialize():
	var props:=Mass.validated(Mass.uniform_box(12,Vector4(2,4,6,8)),12)
	var expected=[20,40,68,52,80,100]
	for i in range(6):
		check(absf(props.inertia[i*6+i]-expected[i])<1e-9,"Analytic plane inertia %d"%i)
		for j in range(6):
			var value:=0.0
			for k in range(6): value+=props.inertia[i*6+k]*props.inverse_inertia[k*6+j]
			check(absf(value-(1 if i==j else 0))<1e-9,"Inverse identity")
	var rotation:=Math4D.new()
	rotation.angles[0]=45
	var rotated:=Mass.transformed(props,rotation.matrix())
	check(absf(rotated.inertia[1*6+3]+6)<0.00001,"Rotation creates coupled plane inertia")
	# Independent quadrature: 16 points reproduce a box's central second moment.
	var omega=[0.2,-0.7,1.1,0.3,-0.5,0.8]
	var energy:=0.0
	for bits in range(16):
		var r:=Vector4.ZERO
		for axis in range(4): r[axis]=Vector4(2,4,6,8)[axis]/sqrt(12.0)*(1 if bits&(1<<axis) else -1)
		r=Math4D.apply(rotation.matrix(),r,0)
		var v:=Vector4.ZERO
		for plane in range(6):
			var axes: Vector2i=Math4D.PLANES[plane]
			v[axes.x]-=omega[plane]*r[axes.y]
			v[axes.y]+=omega[plane]*r[axes.x]
		energy+=0.5*(12.0/16)*v.length_squared()
	var tensor_energy:=0.0
	for i in range(6):
		for j in range(6): tensor_energy+=0.5*omega[i]*rotated.inertia[i*6+j]*omega[j]
	check(absf(energy-tensor_energy)<0.0001,"Full tensor rotational energy")
	var translated:=Mass.transformed(props,Math4D.translation(Vector4(10,20,30,40)))
	check(translated.inertia==props.inertia,"Translation does not change central inertia")
	var scale:=Math4D.new()
	scale.scale=Vector4(2,1,1,1)
	var scaled:=Mass.transformed(props,scale.matrix())
	check(scaled.mass==12 and absf(scaled.inertia[0]-32)<1e-9,"Nonuniform scale at fixed mass")
	var invalid=props.duplicate(true)
	invalid.second_moment[0]=-1
	check(Mass.validated(invalid,12).is_empty(),"Nonphysical moment rejected")
	invalid=props.duplicate(true)
	invalid.second_moment[1]=3
	check(Mass.validated(invalid,12).is_empty(),"Asymmetry rejected")
	check(Mass.uniform_box(1,Vector4(0,2,2,2)).is_empty(),"Zero-volume box rejected")
	var w:=World.new()
	var center:=Vector4(3,0,0,0)
	check(w.configure_body(1,"dynamic",Vector4(1,0,0,0),{"mass":2,"mass_properties":Mass.uniform_box(2,Vector4(2,2,2,2),center),"angular_velocity":[90,0,0,0,0,0]}),"Explicit COM configuration")
	w.step(1)
	check((w.center_of_mass(1)-Vector4(4,0,0,0)).length()<1e-6,"COM moves linearly")
	check((Math4D.apply(w.matrices()[1],center)-w.center_of_mass(1)).length()<1e-6,"Rotation fixes moving COM")
	check((Math4D.apply(w.matrices()[1],center+Vector4(1,0,0,0))-Vector4(4,1,0,0)).length()<1e-6,"Geometry rotates about COM")
	check((w.world_mass_properties(1).center_of_mass-w.center_of_mass(1)).length()<1e-6,"World properties center")
	var copy=w.mass_properties(1)
	copy.second_moment[0]=999
	check(w.mass_properties(1).second_moment[0]!=999,"Owned property copies")
	var saved=w.snapshot()
	check(not w.configure_body(1,"dynamic",Vector4.ZERO,{"mass":3,"mass_properties":props}),"Mismatched mass rejected")
	check(saved==w.snapshot(),"Invalid configuration atomic")
	w.reset()
	check(w.center_of_mass(1)==center,"Reset keeps COM")
	w.restore(saved)
	check(w.center_of_mass(1)==Vector4(4,0,0,0),"Snapshot preserves COM")
	w.configure_body(2,"static",Vector4.ZERO,{"mass_properties":Mass.uniform_box(1,Vector4(2,2,2,2))})
	for v in w.inverse_inertia_world(2): check(v==0,"Static inverse inertia zero")
	# Scene uses shape-local input; authored translations don't become an orbit about World.
	var s:=Session.new()
	var id:=s.add_geometry(Box.new(),{"position":{"X":5},"scale":{"X":2}})
	check(s.configure_body(id,"dynamic",Vector4.ZERO,{"mass_properties":Mass.uniform_box(1,Vector4(2,2,2,2)),"angular_velocity":[90,0,0,0,0,0]}),"Session shape-local mass properties")
	check(absf(s.physics.mass_properties(id).inertia[0]-5.0/3)<1e-6,"Authored scale changes inertia")
	s.seek(1)
	var mean:=Vector4.ZERO
	for v in s.world_vertices(id): mean+=v/16.0
	check((mean-Vector4(5,0,0,0)).length()<0.00001,"Translated tesseract spins in place")
	var frame=s.physics.snapshot()
	s.seek(0);s.seek(1)
	check(frame==s.physics.snapshot(),"Session replay exact")
	check(s.set_geometry_expressions(id,{"position.0":"7","scale.0":"3"},false),"Starting transform edit")
	check(s.physics.center_of_mass(id)==Vector4(7,0,0,0),"Edited pose refreshes center")
	check(absf(s.physics.mass_properties(id).inertia[0]-10.0/3)<1e-6,"Edited scale refreshes inertia")
	check(s.configure_dynamic_initial(id,{"velocity.0":"1","angular_velocity.0":"90"}),"Expression initialization retains properties")
	s.seek(1)
	check((s.physics.center_of_mass(id)-Vector4(8,0,0,0)).length()<0.00001,"Expression initialization COM")
	s.invalidate()
	check(absf(s.physics.mass_properties(id).inertia[0]-10.0/3)<1e-6,"Initial-condition reset retains inertia")
	print("Mass property failures: ",failures)
	quit(1 if failures else 0)
