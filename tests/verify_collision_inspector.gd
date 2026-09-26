extends SceneTree
var failures := 0
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		push_error(label)
func _initialize(): call_deferred("verify")
func verify():
	root.size = Vector2i(1440,900)
	var scene = load("res://scripts/sandbox/procedural/procedural_scene.gd").new()
	root.add_child(scene)
	var a = scene.add_shape(0)
	var b = scene.add_shape(0)
	b.fields["position.3"].text = "3"
	scene.apply_card(b)
	await process_frame
	await process_frame
	var inspector = scene.collision_inspector
	inspector.toggle.button_pressed = true
	check(inspector.last_result.status == "separated", "W-only separation")
	check(a.object.last_points == b.object.last_points, "Identical XYZ projections despite 4D separation")
	check(inspector.interval_view.visible and inspector.last_result.gap > 0, "Visible interval evidence")
	check(a.renderer.collision_color.a > 0, "Collision overlay enabled")
	var count: int = scene.recording.frames.size()
	inspector.update_query()
	check(scene.recording.frames.size() == count, "Read-only query")
	b.fields["position.3"].text = "1"
	scene.apply_card(b)
	check(inspector.last_result.status == "intersecting", "Live edit refresh")
	inspector.toggle.button_pressed = false
	check(a.renderer.collision_color.a == 0, "Overlay cleared")
	scene.remove_card(b)
	await process_frame
	inspector.toggle.button_pressed = true
	check(inspector.report.text == "Add two shapes to compare.", "Removal updates selectors")
	scene.queue_free()
	await process_frame
	print("Collision inspector failures: ",failures)
	quit(1 if failures else 0)
