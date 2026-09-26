extends SceneTree
const Session = preload("res://scripts/core/session_4d.gd")
const Geometry = preload("res://scripts/core/geometry/geometry_4d.gd")
var failures := 0
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		push_error(label)
func _initialize():
	var session := Session.new()
	var geometry := Geometry.new()
	geometry.vertices = [Vector4(1,0,0,0), Vector4(0,1,0,0)]
	geometry.edges = [Vector2i(0,1)]
	var a := session.add_geometry(geometry)
	var b := session.add_geometry(geometry)
	check(a != 0 and b != 0, "In-memory objects without UI or IO")
	geometry.vertices[0].x = 7
	check(session.world_vertices(a)[0].x == 1 and session.world_vertices(b)[0].x == 1, "Runtime owns independent geometry copies")
	check(session.reparent(b,a), "Core reparent")
	check(not session.reparent(a,b), "Cycles rejected without mutation")
	var unchanged: Dictionary = session.scene.objects[a].track.sources.duplicate()
	var invalid: Dictionary = unchanged.duplicate()
	invalid["position.0"] = "invalid("
	check(not session.set_geometry_expressions(a,invalid), "Invalid edits rejected")
	check(session.scene.objects[a].track.sources == unchanged, "Failed edit is atomic")
	var source: Dictionary = session.scene.objects[a].track.sources.duplicate()
	source["position.0"] = "10"
	check(session.set_geometry_expressions(a,source), "Core geometry edit")
	check(session.world_vertices(b)[0].x == 1, "Geometry edit excludes children")
	source = session.scene.objects[a].group.sources.duplicate()
	source["position.1"] = "2*t"
	check(session.set_group_expressions(a,source), "Core group edit")
	check(session.seek(1), "Seek")
	check(session.world_vertices(b)[0].y == 2, "Group affects child")
	session.make_dynamic(b,Vector4.ZERO,Vector4(0,0,0,3))
	session.seek(2)
	check(absf(session.world_vertices(b)[0].w-6) < 0.00001, "Dynamic body drives scene geometry")
	var before = session.world_vertices(b)
	session.seek(0)
	session.seek(2)
	check(session.world_vertices(b) == before, "Recorded replay restores scene")
	check(session.set_range(-1,3), "Negative initial time")
	session.play(1)
	for frame in range(60): session.advance(1.0/60.0)
	check(absf(session.playback.time) < 0.00001, "Headless playback without timeline widget")
	check(session.remove_object(a), "Remove parent without editor")
	check(session.scene.objects.has(b), "Child retained")
	print("Core failures: ",failures)
	quit(1 if failures else 0)
