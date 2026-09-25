extends SceneTree
const Transform4D = preload("res://scripts/geometry/transform_4d.gd")
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func close(a: Vector4, b: Vector4) -> bool:
	return a.distance_to(b) < 0.0001
func _initialize() -> void:
	call_deferred("verify")
func verify() -> void:
	var model := Transform4D.new()
	var point := Vector4(1, 2, -3, 4)
	check(close(Transform4D.apply(model.matrix(), point), point), "Identity")
	model.position = Vector4(2, -1, 3, 7)
	check(close(Transform4D.apply(model.matrix(), point), point + model.position), "4D translation")
	for plane_index in range(6):
		model.reset()
		model.angles[plane_index] = 90
		var plane: Vector2i = Transform4D.PLANES[plane_index]
		var expected := point
		expected[plane.x] = -point[plane.y]
		expected[plane.y] = point[plane.x]
		check(close(Transform4D.apply(model.matrix(), point), expected), "90-degree plane rotation")
	model.reset()
	model.position = Vector4(3, 0, 0, 0)
	model.anchor = Vector4(1, 0, 0, 0)
	model.scale = Vector4.ONE * 2
	model.angles[2] = 90
	check(close(Transform4D.apply(model.matrix(), Vector4.ONE), Vector4(1, 2, 2, 0)), "Worked PRSA example")
	model.position = Vector4(3, -2, 5, 1)
	model.anchor = Vector4(1, 2, -1, 0.5)
	model.scale = Vector4(2, -3, 0.5, 4)
	model.angles = PackedFloat64Array([20, -30, 45, 10, 60, -15])
	# Independent sequential arithmetic checks matrix order and signs.
	var expected := (point - model.anchor) * model.scale
	for i in range(6):
		var plane: Vector2i = Transform4D.PLANES[i]
		var a := expected[plane.x]
		var b := expected[plane.y]
		var angle := deg_to_rad(model.angles[i])
		expected[plane.x] = cos(angle) * a - sin(angle) * b
		expected[plane.y] = sin(angle) * a + cos(angle) * b
	expected += model.position
	check(close(Transform4D.apply(model.matrix(), point), expected), "Combined matrix equals sequential PRSA")
	var vertices: Array[Vector4] = [point, Vector4.ONE, Vector4(-2, 4, 0, 1), Vector4.ZERO]
	var before := model.transform_vertices(vertices)
	model.set_anchor(Vector4(-7, 0.5, 2, 8))
	var after := model.transform_vertices(vertices)
	for i in range(vertices.size()): check(close(before[i], after[i]), "Compensated anchor preserves geometry")
	check(close(Transform4D.apply(model.matrix(), model.anchor), model.position), "Anchor maps to position")
	model.keep_in_place = false
	var old_position := model.position
	model.set_anchor(Vector4.ZERO)
	check(model.position == old_position, "Uncompensated anchor leaves position alone")
	check(not close(Transform4D.apply(model.matrix(), point), before[0]), "Uncompensated anchor changes geometry")
	model.scale = Vector4.ONE
	var rotated := model.transform_vertices(vertices)
	check(absf(rotated[0].distance_to(rotated[1]) - vertices[0].distance_to(vertices[1])) < 0.0001, "Rotations preserve 4D distance")
	root.size = Vector2i(1440, 900)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var panel = scene.projection_panel.transform_panel
	scene.projection_panel.tabs.current_tab = 1
	check(panel.rotation_sliders.size() == 6, "Six rotation sliders")
	for axis in range(6):
		panel.rotation_sliders[axis].value = 30 + axis
		check(scene.model_transform.angles[axis] == 30 + axis, "Slider updates rotation")
		check(panel.controls["angles"][axis].value == 30 + axis, "Slider syncs numeric field")
	panel.controls["angles"][0].value = 450
	check(panel.rotation_sliders[0].value == 450, "Typed multi-turn angle syncs slider")
	scene.reset_transform()
	for slider in panel.rotation_sliders:
		check(slider.value == 0 and slider.max_value == 180, "Reset slider")
	check(panel.scale_sliders.size() == 4, "Four scale sliders")
	panel.scale_sliders[0].value = -2
	check(scene.model_transform.scale == Vector4(-2, 1, 1, 1), "Independent negative scale")
	panel.scale_min_field.get_line_edit().text = "0"
	panel.scale_max_field.get_line_edit().text = "0.5"
	panel.apply_scale_range()
	check(panel.scale_min == -2 and panel.scale_max == 1, "Bounds expand to current scales")
	check(scene.model_transform.scale == Vector4(-2, 1, 1, 1), "Range edit preserves scale")
	panel.scale_min_field.get_line_edit().text = "5"
	panel.scale_max_field.get_line_edit().text = "2"
	panel.apply_scale_range()
	check(panel.scale_min == -2 and panel.scale_max == 1, "Reject inverted range")
	panel.controls["scale"][2].value = 8
	check(panel.scale_max == 8 and panel.scale_sliders[2].value == 8, "Typed scale expands range")
	panel.uniform.button_pressed = true
	panel.scale_sliders[3].value = 0
	check(scene.model_transform.scale == Vector4.ZERO, "Uniform zero scale")
	for slider in panel.scale_sliders: check(slider.value == 0, "Uniform slider sync")
	panel.uniform.button_pressed = false
	scene.reset_transform()
	for slider in panel.scale_sliders: check(slider.value == 1, "Scale slider reset")
	var originals = scene.editor.shape.vertices.duplicate()
	panel.controls["position"][0].get_line_edit().text = "3"
	panel.controls["position"][0].apply()
	check(scene.model_transform.position.x == 3, "Position field signal")
	panel.uniform.button_pressed = true
	panel.controls["scale"][1].value = 2
	check(scene.model_transform.scale == Vector4.ONE * 2, "Uniform scale")
	panel.controls["angles"][2].value = 90
	var projected_before = scene.model_transform.transform_vertices(scene.editor.shape.vertices)
	panel.controls["anchor"][0].value = 1
	var projected_after = scene.model_transform.transform_vertices(scene.editor.shape.vertices)
	for i in range(projected_before.size()): check(close(projected_before[i], projected_after[i]), "Panel anchor compensation")
	check(panel.controls["position"][3].value == 2, "Compensated position field refresh")
	check(scene.editor.shape.vertices == originals, "Transforms preserve editable base")
	check(panel.readout.text.contains("Transformed 4D"), "Readout")
	scene.select_shape(1)
	check(scene.model_transform.position == Vector4.ZERO, "New shape identity")
	scene.select_shape(0)
	check(scene.model_transform.position.x == 3 and scene.model_transform.position.w == 2, "Cached transform")
	scene.select_vertex(5)
	check(panel.readout.text.begins_with("V5"), "Readout follows selection")
	scene.reset_transform()
	check(scene.model_transform.transform_vertices(originals) == originals, "Reset identity")
	await process_frame
	await process_frame
	check(scene.projection_panel.panel.get_global_rect().end.y <= root.get_visible_rect().end.y, "Transform panel height")
	check(scene.projection_panel.panel.get_global_rect().end.x < scene.vertex_panel.panel.position.x, "Panels do not overlap")
	print("Transform validation failures: ", failures)
	quit(1 if failures else 0)
