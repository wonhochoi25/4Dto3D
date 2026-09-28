extends SceneTree
const Session=preload("res://scripts/core/session_4d.gd")
const Box=preload("res://scripts/core/geometry/generators/tesseract.gd")
var failures:=0
func check(ok: bool,label: String):
	if not ok: failures+=1; push_error(label)
class Uncertain:
	static func query(_a,_b,_options={}):
		return {"status":"intersecting","penetration":{"status":"penetrating","converged":false,"depth":10,"direction":PackedFloat64Array([1,0,0,0])}}
func _initialize():
	for other_type in ["dynamic","static","kinematic"]:
		var s:=Session.new()
		var a:=s.add_geometry(Box.new())
		var b:=s.add_geometry(Box.new(),{"position":{"W":1.5}})
		s.configure_body(a,"dynamic",Vector4.ZERO,{"mass":1.0})
		s.configure_body(b,other_type,Vector4.ZERO,{"mass":3.0})
		check(s.physics.bodies[a][3]==0,"Authored initial pose preserved")
		check(s.seek(1.0/60),"Step succeeds")
		var pa: float=s.physics.bodies[a][3]
		var pb: float=s.physics.bodies[b][3]
		check(absf((pb-pa)-0.4999)<0.001,"W gap corrected: "+other_type)
		if other_type=="dynamic": check(absf(pa+3*pb)<0.00001,"Inverse mass weighting")
		else: check(pb==0,"Immovable body unchanged")
		check(s.physics.bodies[a][7]==0 and s.physics.bodies[b][7]==0,"No velocity impulse")
		var snapshot=s.physics.snapshot()
		s.seek(0);s.seek(1.0/60)
		check(s.physics.snapshot()==snapshot,"Replay exact")
		s.invalidate();s.seek(1.0/60)
		check(s.physics.snapshot()==snapshot,"Reset reproduces correction")
	var s:=Session.new()
	var a:=s.add_geometry(Box.new())
	var b:=s.add_geometry(Box.new(),{"position":{"X":1.5}})
	s.configure_body(a,"dynamic",Vector4.ZERO)
	s.configure_body(b,"static",Vector4.ZERO)
	s.collision_backend=Uncertain
	s.seek(1.0/60)
	check(s.physics.bodies[a][0]==0,"Unconverged backend skipped")
	# Multiple contacts: a middle dynamic box pushes a second dynamic box away from a wall.
	s=Session.new()
	for x in [0.0,1.5,3.0]:
		var id:=s.add_geometry(Box.new(),{"position":{"X":x}})
		s.configure_body(id,"static" if x==0 else "dynamic",Vector4.ZERO)
	s.overlap_options.iterations=32
	s.seek(1.0/60)
	for report in s.contact_reports:
		var pen: Dictionary=report.result.get("penetration",{})
		if pen.get("converged",false): check(pen.get("depth",0)<0.001,"Repeated pair correction")
	print("Overlap failures: ",failures)
	quit(1 if failures else 0)
