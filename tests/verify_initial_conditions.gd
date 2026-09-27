extends SceneTree
const Session = preload("res://scripts/core/session_4d.gd")
const Box = preload("res://scripts/core/geometry/generators/tesseract.gd")
const Math4D = preload("res://scripts/core/math/transform_4d.gd")
var failures := 0
func check(ok: bool,label: String):
	if not ok: failures+=1; push_error(label)
func _initialize(): call_deferred("verify")
func verify():
	var session := Session.new()
	var parent := session.add_geometry(Box.new(),{}, {"position":{"W":"t"},"rotation":{"XY":"30*t"},"scale":"1+t"})
	session.configure_kinematic(parent)
	var child := session.add_geometry(Box.new(),{"position":{"X":"2+t"}}, {"position":{"Y":"3+t"}})
	session.configure_body(child,"static",Vector4.ZERO)
	check(session.reparent(child,parent,false),"Parent static")
	var initial := session.world_vertices(child)
	check(session.seek(1),"Advance static hierarchy")
	var parent_transform := Math4D.new()
	parent_transform.position.w=1
	parent_transform.scale=Vector4.ONE*2
	parent_transform.angles[0]=30
	var points := session.world_vertices(child)
	for i in range(points.size()): check((points[i]-Math4D.apply(parent_transform.matrix(),initial[i])).length()<1e-5,"Static inherits translation rotation scale with frozen local pose")
	check(session.reparent(child,0,true),"Unparent static preserving current pose")
	var unparented := session.world_vertices(child)
	session.seek(1)
	check(session.world_vertices(child)==unparented,"Unparented static fixed")
	var id := session.add_geometry(Box.new(),{"position":{"W":"t"}})
	check(session.set_range(2,5),"Nonzero run start")
	check(session.configure_dynamic_initial(id,{"velocity.0":"2*t", "acceleration.0":"t", "angular_velocity.2":"15*t", "angular_acceleration.2":"t+1"}),"Configure initial expressions")
	check(session.physics.bodies[id][4]==4 and session.physics.bodies[id][30]==2,"Evaluate at start")
	check(session.physics.bodies[id][26]==30 and session.physics.bodies[id][36]==3,"Angular initial expressions")
	check(session.seek(3),"Simulate initialized rates")
	check(absf(session.physics.bodies[id][4]-6)<1e-8,"Velocity evolves rather than resampling")
	check(session.physics.bodies[id][30]==2,"Acceleration remains stored")
	var end := session.world_vertices(id)
	session.seek(2.5)
	session.seek(3)
	check(session.world_vertices(id)==end,"Exact replay")
	session.invalidate()
	# Simulate a future interaction changing velocity/acceleration; no collision solver needed.
	session.physics.bodies[id][4]=100
	session.physics.bodies[id][30]=7
	session.physics.bodies[id][26]=80
	session.physics.step(0.5)
	check(session.physics.bodies[id][4]==103.5 and session.physics.bodies[id][26]==81.5,"Physics changes survive initial expressions")
	session.invalidate()
	check(session.physics.bodies[id][4]==4 and session.physics.bodies[id][30]==2,"Reset restores initial expressions")
	check(session.set_range(3,5),"Change start time")
	check(session.physics.bodies[id][4]==6 and session.physics.bodies[id][30]==3,"Start change re-evaluates")
	var saved: Dictionary=session.physics.snapshot()
	check(not session.configure_dynamic_initial(id,{"velocity.0":"sqrt(-1)"}),"Reject invalid initial expression")
	check(session.physics.snapshot()==saved,"Invalid edit is atomic")
	check(session.configure_dynamic_initial(id,{"velocity.0":"sqrt(t-2)"}),"Time-domain expression")
	check(not session.set_range(1,5) and session.playback.start==3,"Invalid start rejected atomically")
	check(session.configure_kinematic(id) and not session.initial_motion_tracks.has(id),"Switch mode clears initial driver")
	var ui = preload("res://scripts/sandbox/physics/physics_scene.gd").new()
	root.add_child(ui)
	var card=ui.add_shape(0)
	await process_frame
	var uid: int=card.get_meta("group_id")
	var editor: Dictionary=ui.body_editors[uid]
	editor.picker.select(2)
	editor.fields[0].text="5*cos(t)"
	editor.fields[4].text="2+t"
	ui.apply_body(uid,editor.picker,editor.fields)
	check(not ui.session.initial_motion_tracks.has(uid),"UI rejects initial motion expressions")
	editor.fields[0].text="5"
	editor.fields[4].text="2"
	ui.apply_body(uid,editor.picker,editor.fields)
	check(ui.session.motion_settings[uid].velocity.x==5,"UI applies numeric velocity")
	ui.run_motion()
	check(ui.session.playback.direction==1,"Applied expressions can run")
	ui.session.pause()
	editor.fields[0].text="6*cos(t)"
	ui.run_motion()
	check(ui.session.playback.direction==0,"Draft expression blocks Run")
	ui.queue_free()
	await process_frame
	print("Initial condition failures: ",failures)
	quit(1 if failures else 0)
