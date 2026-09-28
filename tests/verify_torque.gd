extends SceneTree
const World=preload("res://scripts/core/physics/physics_world_4d.gd")
const Mass=preload("res://scripts/core/physics/mass_properties_4d.gd")
const Angular=preload("res://scripts/core/physics/angular_response_4d.gd")
var failures:=0
func check(ok: bool,label: String):
	if not ok: failures+=1;push_error(label)
func momentum(w) -> PackedFloat64Array:
	var omega:=PackedFloat64Array()
	for i in range(6): omega.append(deg_to_rad(w.bodies[1][24+i]))
	return Angular.multiply(w.world_mass_properties(1).inertia,omega)
func energy(w) -> float:
	var m:=momentum(w);var value:=0.0
	for i in range(6): value+=0.5*m[i]*deg_to_rad(w.bodies[1][24+i])
	return value
func _initialize():
	var w:=World.new()
	w.configure_body(1,"dynamic",Vector4.ZERO,{"mass_properties":Mass.uniform_box(1,Vector4(2,2,2,2))})
	w.apply_torque(1,PackedFloat64Array([2,0,0,0,0,0]))
	w.step(0.1)
	check(absf(momentum(w)[0]-0.2)<0.000001,"Torque changes angular momentum")
	w.step(0.1)
	check(absf(momentum(w)[0]-0.2)<0.000001,"Torque consumed once")
	w.configure_body(1,"dynamic",Vector4.ZERO,{"mass_properties":Mass.uniform_box(1,Vector4(1,2,3,4)),"angular_velocity":[30,40,20,10,50,15]})
	var initial:=momentum(w);var e:=energy(w)
	var initial_rates: PackedFloat64Array=w.bodies[1].slice(24,30)
	for step in range(300): w.step(1.0/120)
	var final:=momentum(w)
	for i in range(6): check(absf(initial[i]-final[i])<0.00001,"World angular momentum conserved")
	check(absf(energy(w)-e)/e<0.001,"Bounded energy error")
	check(w.bodies[1].slice(24,30)!=initial_rates,"Asymmetric free rotation changes omega")
	var r=w.matrices()[1]
	for i in range(4):
		for j in range(4):
			var dot:=0.0
			for k in range(4): dot+=r[k*5+i]*r[k*5+j]
			check(absf(dot-(1 if i==j else 0))<0.00001,"Orientation orthogonal")
	print("Torque failures: ",failures)
	quit(1 if failures else 0)
