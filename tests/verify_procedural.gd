extends SceneTree
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("verify")
func verify() -> void:
	root.size = Vector2i(1440, 900)
	var app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
	await process_frame
	check(app.pages.size() == 1 and app.active == 0, "Default playground")
	app.close_page(0)
	check(app.pages.size() == 1, "Unclosable playground")
	app.new_procedural()
	await process_frame
	var scene = app.pages[1]["scene"]
	var first = scene.add_shape(0)
	var second = scene.add_shape(0)
	check(scene.selected_card == second and second.visible and not first.visible, "Only newest editor selected")
	first.fields["position.0"].text = "t+3"
	scene.select_card(first)
	check(first.visible and not second.visible, "Single editor selection")
	scene.select_card(second)
	scene.select_card(first)
	check(first.fields["position.0"].text == "t+3", "Draft survives selection")
	first.fields["position.0"].text = "0"
	var temporary = scene.add_shape(0)
	scene.remove_card(temporary)
	check(scene.selected_card == second, "Remove selects nearest remaining shape")
	await process_frame
	await process_frame
	check(scene.panel.size.y < scene.get_viewport().get_visible_rect().size.y - 166, "Sidebar hugs short editor")
	check(scene.timeline.get_child(0).alignment == BoxContainer.ALIGNMENT_CENTER, "Playback controls centered")
	first.fields["angles.2"].text = "30*t"
	first.fields["projection.0"].text = "1+0.2*sin(t)"
	scene.apply_card(first)
	check(first.object.error.is_empty(), "Compile valid")
	check(scene.evaluate_time(2), "Evaluate t=2")
	var at_two = first.object.last_points.duplicate()
	check(scene.evaluate_time(4), "Evaluate t=4")
	check(scene.evaluate_time(2), "Reverse t=2")
	check(first.object.last_points == at_two, "Deterministic reverse")
	check(first.object.last_points != second.object.last_points, "Independent projections and transforms")
	var old_source = first.object.sources.duplicate()
	first.fields["scale.0"].text = "load(123)"
	scene.apply_card(first)
	check(first.object.sources == old_source, "Bad apply preserves expressions")
	first.fields["scale.0"].text = "sqrt(3-t)"
	scene.apply_card(first)
	check(first.object.error.is_empty(), "Apply valid at current time")
	var old_frame = first.object.last_points.duplicate()
	var second_frame = second.object.last_points.duplicate()
	check(not scene.evaluate_time(4), "Reject runtime error")
	check(first.object.last_points == old_frame and second.object.last_points == second_frame and scene.timeline.time == 2, "Atomic last valid frame")
	first.fields["scale.0"].text = "1"
	scene.apply_card(first)
	scene.timeline.direction = 1
	app.activate(0)
	check(scene.timeline.direction == 0, "Inactive paused")
	check(app.pages[1]["host"].process_mode == Node.PROCESS_MODE_DISABLED, "Inactive disabled")
	app.activate(1)
	for i in range(1, 7):
		var card = scene.add_shape(i)
		check(card.object.faces.size() > 0, "Shape faces")
		check(card.renderer.surface.mesh.get_surface_count() > 0, "Triangulated faces")
	# Timeline sampling, bounds, looping and input controls.
	scene.timeline.accept(5)
	scene.timeline.direction = -1
	scene.timeline._process(0.25)
	check(is_equal_approx(scene.timeline.time, 4.75), "Reverse playback")
	scene.timeline.scrub(1.25)
	check(scene.timeline.direction == 0 and scene.timeline.time == 1.25, "Manual time pauses")
	scene.timeline.looping = true
	scene.timeline.accept(0.1)
	scene.timeline.direction = -1
	scene.timeline._process(0.25)
	check(is_equal_approx(scene.timeline.time, 9.85), "Reverse looping")
	scene.timeline.looping = false
	scene.timeline.accept(0.1)
	scene.timeline.direction = -1
	scene.timeline._process(0.25)
	check(scene.timeline.time == 0 and scene.timeline.direction == 0, "Stop at range bound")
	scene.timeline.start_field.get_line_edit().text = "-5"
	scene.timeline.end_field.get_line_edit().text = "5"
	scene.timeline.set_range()
	scene.timeline.scrub(-2)
	check(scene.timeline.time == -2, "Negative time")
	await process_frame
	await process_frame
	var visible_size = app.pages[1]["viewport"].get_visible_rect().size
	check(scene.panel.get_rect().size.x < visible_size.x, "Procedural panel fits")
	check(scene.timeline.get_global_rect().end.x <= visible_size.x, "Timeline fits")
	check(scene.list.get_minimum_size().x <= scene.panel.size.x, "Cards fit panel")
	var started := Time.get_ticks_usec()
	for frame in range(30): scene.evaluate_time(frame / 30.0)
	print("All-shape CPU frame average ms: ", (Time.get_ticks_usec() - started) / 30000.0)
	app.new_procedural()
	check(app.pages[2]["scene"].cards.is_empty(), "New tab independent")
	app.close_page(1)
	check(app.pages.size() == 2 and app.active == 1, "Close other tab preserves active")
	app.close_page(1)
	check(app.pages.size() == 1 and app.active == 0, "Close active returns playground")
	await process_frame
	print("Procedural failures: ", failures)
	quit(1 if failures else 0)
