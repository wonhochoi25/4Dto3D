extends SceneTree
const World = preload("res://scripts/core/physics/physics_world_4d.gd")
const Session = preload("res://scripts/core/session_4d.gd")
const Box = preload("res://scripts/core/geometry/generators/tesseract.gd")
const Math4D = preload("res://scripts/core/math/transform_4d.gd")
var failures := 0
func check(ok: bool, label: String):
	if not ok: failures+=1; push_error(label)
func _initialize(): call_deferred("verify")
func verify():
	var world := World.new()
	var motion := {"acceleration":Vector4(2,-2,4,-4),"angular_velocity":[10,0,0,0,0,0],"angular_acceleration":[20,0,0,0,0,0]}
	for id in range(3): check(world.configure_body(id,["static","kinematic","dynamic"][id],Vector4.ONE,motion),"Configure all rates")
	world.step(0.5)
	world.step(0.5)
	check(world.bodies[0][0]==0 and world.bodies[0][8]==1,"Static ignores all motion")
	for id in [1,2]:
		check(absf(world.bodies[id][0]-2.5)<1e-8,"Semi-implicit displacement")
		check(world.bodies[id][4]==3 and world.bodies[id][24]==30,"Acceleration changes rates")
		check(absf(world.bodies[id][8]-cos(deg_to_rad(25)))<1e-8,"Angular acceleration integrates orientation")
	var saved := world.snapshot()
	world.bodies[1][4]=100
	world.bodies[1][24]=100
	world.bodies[2][4]=100
	world.bodies[2][24]=100
	world.step(0.5)
	check(world.bodies[1][4]==4 and world.bodies[1][24]==40,"Kinematic prescribed rates")
	check(world.bodies[2][4]==101 and world.bodies[2][24]==110,"Dynamic simulated rates")
	check(saved[2][4]==3,"Snapshot independent")
	world.restore(saved)
	check(world.bodies[2][40]==1,"Elapsed time restored")
	check(not world.configure_body(2,"dynamic",Vector4.ZERO,{"angular_velocity":[1]}),"Reject wrong plane count")
	check(not world.configure_body(2,"dynamic",Vector4.ZERO,{"acceleration":Vector4(NAN,0,0,0)}),"Reject nonfinite values")
	check(world.bodies[2]==saved[2],"Invalid edit preserves state")
	for plane in range(6):
		var angular := PackedFloat64Array([0,0,0,0,0,0])
		angular[plane]=90
		world.configure_body(3,"dynamic",Vector4.ZERO,{"angular_velocity":angular})
		world.step(1)
		var expected := Math4D.new()
		expected.angles=angular
		check(world.matrices()[3]==expected.rotation_matrix(),"Plane order %s" % plane)
	var session := Session.new()
	var id := session.add_geometry(Box.new(),{}, {"rotation":{"XW":90}})
	session.configure_body(id,"dynamic",Vector4.ONE,motion)
	var initial := session.world_vertices(id)
	session.seek(1)
	var end := session.world_vertices(id)
	session.seek(0.5)
	session.seek(1)
	check(end==session.world_vertices(id),"Exact accelerated replay")
	session.invalidate()
	check(initial==session.world_vertices(id),"Reset pose and history")
	# Rotation increment acts on the left of an already rotated starting group.
	session.configure_body(id,"dynamic",Vector4.ZERO,{"angular_velocity":[90,0,0,0,0,0]})
	session.seek(1)
	var rot := Math4D.new()
	rot.angles[0]=90
	check((session.world_vertices(id)[0]-Math4D.apply(rot.rotation_matrix(),initial[0])).length()<1e-5,"World-plane rotation")
	var ui = preload("res://scripts/sandbox/physics/physics_scene.gd").new()
	root.add_child(ui)
	var card=ui.add_shape(0)
	await process_frame
	var key: int=card.get_meta("group_id")
	var editor: Dictionary=ui.body_editors[key]
	check(editor.fields.size()==20,"All UI components present")
	editor.picker.select(2)
	editor.fields[4].text="2"
	editor.fields[8].text="30"
	editor.fields[14].text="10"
	ui.apply_body(key,editor.picker,editor.fields)
	check(ui.session.motion_settings[key].angular_acceleration[0]==10,"UI commits angular acceleration")
	ui.run_motion()
	check(ui.session.playback.direction==1,"Applied fields allow Run")
	ui.session.pause()
	editor.fields[19].text="2"
	ui.run_motion()
	check(ui.session.playback.direction==0,"Pending angular edit blocks Run")
	ui.queue_free()
	await process_frame
	print("Acceleration failures: ",failures)
	quit(1 if failures else 0)
