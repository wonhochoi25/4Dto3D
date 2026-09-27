extends SceneTree
const Probe = preload("res://tests/fixtures/collision_backend_probe.gd")
var failures := 0
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		push_error(label)
func _initialize(): call_deferred("verify")
func verify():
	var scene = load("res://scripts/sandbox/procedural/procedural_scene.gd").new()
	root.add_child(scene)
	var a = scene.add_shape(0)
	var b = scene.add_shape(0)
	await process_frame
	var inspector = scene.collision_inspector
	var session = inspector.session
	# Default adapter results contain no simplex or algorithm-specific required fields.
	var ids: Array = session.scene.objects.keys()
	var initial: Dictionary = session.query_collision(ids[0],ids[1])
	check(initial.has("status") and initial.has("reason"),"Default contract")
	check(not initial.has("simplex"),"No algorithm internals exposed")
	var original = session.collision_backend
	session.collision_backend = Probe
	var points = b.object.last_points.duplicate()
	var frame_count: int = scene.recording.frames.size()
	inspector.toggle.button_pressed = true
	inspector.penetration_toggle.button_pressed = true
	for status in ["intersecting","separated","indeterminate"]:
		Probe.response = {"status":status,"reason":"Minimal result"}
		inspector.update_query()
		check(inspector.last_result.status == status,"Backend status survives")
		check(not inspector.interval_view.visible,"No invented interval data")
		if status == "intersecting": check(inspector.report.text.contains("unavailable"),"Missing penetration supported")
	Probe.response = {"status":"separated","reason":"Distance-only result","distance":2.0}
	inspector.update_query()
	check(inspector.report.text.contains("Distance estimate") and not inspector.interval_view.visible,"Distance without bounds or axis")
	Probe.response = {"status":"intersecting","reason":"Depth-only result","penetration":{"status":"penetrating","reason":"Depth available","converged":true,"depth":0.5}}
	inspector.update_query()
	check(inspector.report.text.contains("Penetration depth: 0.500000") and not inspector.report.text.contains("Translation for B"),"Depth without direction or translation")
	check(Probe.requested_penetration,"Options forwarded")
	var count := Probe.calls
	check(session.query_collision(ids[0],ids[0]).status=="indeterminate" and Probe.calls==count,"Invalid IDs handled independently")
	check(b.object.last_points==points and scene.recording.frames.size()==frame_count,"Read-only backend integration")
	session.collision_backend = original
	inspector.update_query()
	scene.queue_free()
	await process_frame
	print("Collision backend failures: ",failures)
	quit(1 if failures else 0)
