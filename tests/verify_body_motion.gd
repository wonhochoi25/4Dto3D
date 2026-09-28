extends SceneTree
const Session = preload("res://scripts/core/session_4d.gd")
const Box = preload("res://scripts/core/geometry/generators/tesseract.gd")
var failures := 0
func check(ok: bool, label: String):
	if not ok:
		failures+=1
		push_error(label)
func _initialize(): call_deferred("verify")
func verify():
	var session := Session.new()
	var ids := []
	for type in ["static","kinematic","dynamic"]:
		var id := session.add_geometry(Box.new(),{"position":{"X":2},"rotation":{"XW":30},"scale":{"Y":2}}, {"position":{"W":3},"rotation":{"XY":20},"scale":2})
		ids.append(id)
		check(session.configure_body(id,type,Vector4(1,2,3,4)),"Configure "+type)
	var initial := {}
	for id in ids: initial[id]=session.world_vertices(id)
	check(session.seek(2),"Seek forward")
	for i in range(3):
		var points := session.world_vertices(ids[i])
		for k in range(points.size()):
			var expected: Vector4=initial[ids[i]][k]+(Vector4.ZERO if i==0 else Vector4(2,4,6,8))
			check((points[k]-expected).length()<1e-4,"World velocity preserves transformed geometry")
	var end := session.world_vertices(ids[2])
	check(session.seek(0.5) and session.seek(2),"Recorded backward/forward")
	check(session.world_vertices(ids[2])==end,"Deterministic replay")
	session.invalidate()
	check(session.world_vertices(ids[2])==initial[ids[2]],"Reset restores starting pose")
	var sim=session.recording.simulation
	var kin: PackedFloat64Array=sim.bodies[ids[1]]
	var dyn: PackedFloat64Array=sim.bodies[ids[2]]
	kin[4]=9
	dyn[4]=9
	sim.bodies[ids[1]]=kin
	sim.bodies[ids[2]]=dyn
	sim.step(1)
	check(sim.set_kinematic_velocity(ids[1],Vector4(1,2,3,4)),"Explicit kinematic prescription")
	check(not sim.apply_impulse(ids[1],Vector4.ONE) and sim.bodies[ids[2]][0]==9,"Prescribed vs simulated ownership")
	check(not session.configure_body(ids[0],"invalid",Vector4.ZERO),"Invalid type rejected")
	session.invalidate()
	check(session.reparent(ids[2],ids[0]),"Paused parenting allowed")
	check(not session.start_body_motion(),"Parented run explicitly blocked")
	check(session.remove_object(ids[2]) and not session.motion_settings.has(ids[2]) and not sim.body_types.has(ids[2]),"Removal cleans body metadata")
	print("Body motion failures: ",failures)
	quit(1 if failures else 0)
