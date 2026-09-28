extends SceneTree
const Session=preload("res://scripts/core/session_4d.gd")
const Box=preload("res://scripts/core/geometry/generators/tesseract.gd")
class Probe:
	static var calls:=0
	static func query(_a,_b,_options={}):
		calls+=1
		return {"status":"indeterminate","reason":"alternate backend"}
var failures:=0
func check(ok: bool,label: String):
	if not ok: failures+=1; push_error(label)
func _initialize():
	var s:=Session.new()
	var a:=s.add_geometry(Box.new())
	var b:=s.add_geometry(Box.new(),{"position":{"W":2.1}})
	s.configure_body(a,"dynamic",Vector4(0,0,0,6))
	s.configure_body(b,"static",Vector4.ZERO)
	check(s.contact_reports.size()==1,"Automatic initial pair")
	check(s.contact_reports[0].result.status=="separated","Hidden W gap")
	s.seek(1.0/60)
	check(s.contact_reports[0].result.status=="intersecting","Touching")
	s.seek(2.0/60)
	check(s.contact_reports[0].result.status=="intersecting","Overlap")
	check(s.contact_reports[0].result.has("penetration"),"Penetration info")
	check(absf(s.physics.bodies[a][3]-0.2)<1e-7 and s.physics.bodies[a][7]==6,"No response")
	s.seek(0)
	check(s.contact_reports[0].result.status=="separated","Replay reports restored time")
	s.seek(2.0/60)
	check(s.contact_reports[0].result.status=="intersecting","Replay overlap")
	var k:=s.add_geometry(Box.new())
	s.configure_kinematic(k)
	check(s.contact_reports.size()==2,"Skip static-kinematic pair")
	s.collision_backend=Probe
	Probe.calls=0
	s.seek(3.0/60)
	check(Probe.calls==6,"Every step uses replacement backend exactly once per pair")
	check(s.contact_reports[0].result.status=="indeterminate","Indeterminate preserved")
	s.seek(0)
	var previous=s.contact_reports.duplicate(true)
	s.seek(1,1)
	check(s.contact_reports==previous,"Partial seek retains displayed reports")
	s.cancel_seek()
	s.remove_object(a)
	check(s.contact_reports.is_empty(),"Removal / no dynamic pairs")
	print("Contact query failures: ",failures)
	quit(1 if failures else 0)
