extends SceneTree
const World=preload("res://scripts/core/physics/physics_world_4d.gd")
const Session=preload("res://scripts/core/session_4d.gd")
const Box=preload("res://scripts/core/geometry/generators/tesseract.gd")
const Math4D=preload("res://scripts/core/math/transform_4d.gd")
class Probe:
	static var calls:=0
	static func query(_a,_b,_options={}): calls+=1;return {"status":"separated"}
var failures:=0
func check(ok: bool,label: String):
	if not ok: failures+=1;push_error(label)
func _initialize():
	var w:=World.new()
	w.configure_body(1,"dynamic",Vector4.ZERO);w.configure_body(2,"static",Vector4.ZERO)
	w.collision_backend=Probe
	var colliders={1:{"geometry":Box.new(),"world":Math4D.identity()},2:{"geometry":Box.new(),"world":Math4D.translation(Vector4(0,0,0,20))}}
	check(w.query_contacts(colliders,{"broad_phase":true}).is_empty() and Probe.calls==0,"4D broad phase avoids narrow query")
	w.query_contacts(colliders)
	check(Probe.calls==1,"Explicit unfiltered reports retained")
	for i in range(40): w.finish_step([],1.0/60)
	check(w.is_sleeping(1),"Quiet body sleeps")
	var saved=w.snapshot()
	w.apply_impulse(1,Vector4(1,0,0,0))
	check(not w.is_sleeping(1),"Impulse wakes")
	w.restore(saved);check(w.is_sleeping(1),"Sleep state restored")
	w.apply_force(1,Vector4(1,0,0,0));check(not w.is_sleeping(1),"Force wakes")
	var s:=Session.new()
	var wall:=s.add_geometry(Box.new(),{"scale":{"X":0.05}})
	var bullet:=s.add_geometry(Box.new(),{"position":{"X":-5}})
	s.configure_body(wall,"static",Vector4.ZERO)
	s.configure_body(bullet,"dynamic",Vector4(600,0,0,0))
	s.apply_force(bullet,Vector4(0,0,0,30))
	check(s.seek(1.0/60),"Fast motion simulated")
	check(absf(s.physics.linear_velocity(bullet).w-0.5)<0.00001,"Force acts for entire subdivided interval")
	check(s.last_motion_substeps>1,"Adaptive substeps used")
	check(s.physics.linear_velocity(bullet).x<0.001,"Fast body stopped at thin wall")
	check(-5+s.physics.bodies[bullet][0]<0,"No tunneling")
	var frame=s.physics.snapshot();s.seek(0);s.seek(1.0/60)
	check(s.physics.snapshot()==frame,"Substep replay exact")
	s.invalidate();s.max_motion_substeps=1
	check(not s.seek(1.0/60) and s.playback.time==0,"Budget exhaustion rejects rather than tunnels")
	var rest:=Session.new();rest.set_gravity(Vector4(0,-9.81,0,0))
	var floor_id:=rest.add_geometry(Box.new());var body:=rest.add_geometry(Box.new(),{"position":{"Y":2}})
	rest.configure_body(floor_id,"static",Vector4.ZERO);rest.configure_body(body,"dynamic",Vector4.ZERO)
	rest.seek(1)
	check(rest.physics.is_sleeping(body),"Supported body sleeps under gravity")
	var Sweep=preload("res://scripts/core/physics/motion_substeps_4d.gd")
	var spin_states=w.snapshot()
	spin_states[1][24]=21600 # A complete turn per macro frame; endpoint positions alone miss it.
	colliders[2].world=Math4D.translation(Vector4(2.1,0,0,0))
	check(Sweep.required(colliders,colliders,w.body_types,0.2,spin_states)>1,"Rotational sweep budget sees full turns")
	print("Motion safety failures: ",failures)
	quit(1 if failures else 0)
