extends SceneTree
## Run: godot --headless --path . --script res://tests/verify.gd
const Registry = preload("res://scripts/shapes/shape_registry.gd")
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("verify")
func verify() -> void:
	root.size = Vector2i(1440, 900)
	var expected := [[16, 32, 4], [80, 208, 0], [5, 10, 4], [8, 24, 6], [24, 96, 8], [600, 1200, 4], [120, 720, 12]]
	for index in range(Registry.ENTRIES.size()):
		var shape = Registry.create(index)
		check(shape.vertices.size() == expected[index][0], shape.display_name + " vertex count")
		check(shape.edges.size() == expected[index][1], shape.display_name + " edge count")
		var degrees := []
		degrees.resize(shape.vertices.size())
		degrees.fill(0)
		var seen := {}
		var center := Vector4.ZERO
		for point in shape.vertices:
			check(not seen.has(point), "Duplicate vertex")
			seen[point] = true
			check(is_equal_approx(point.length_squared(), 4.0), "Circumradius")
			center += point
		check(center.length() < 0.001, "Centered geometry")
		seen.clear()
		var length := -1.0
		var adjacency := {}
		for edge in shape.edges:
			check(edge.x >= 0 and edge.y < shape.vertices.size() and edge.x < edge.y, "Valid edge indices")
			check(not seen.has(edge), "Unique edges")
			seen[edge] = true
			degrees[edge.x] += 1
			degrees[edge.y] += 1
			if not adjacency.has(edge.x): adjacency[edge.x] = []
			if not adjacency.has(edge.y): adjacency[edge.y] = []
			adjacency[edge.x].append(edge.y)
			adjacency[edge.y].append(edge.x)
			var distance: float = shape.vertices[edge.x].distance_to(shape.vertices[edge.y])
			if length < 0: length = distance
			if index != 1: check(absf(distance - length) < 0.0001, "Equal edges")
		if index != 1:
			for degree in degrees: check(degree == expected[index][2], "Vertex degree")
		var reached := {0: true}
		var queue := [0]
		while not queue.is_empty():
			for neighbor in adjacency.get(queue.pop_back(), []):
				if not reached.has(neighbor):
					reached[neighbor] = true
					queue.append(neighbor)
		check(reached.size() == shape.vertices.size(), "Connected graph")
		print(shape.display_name, ": ", shape.vertices.size(), " vertices, ", shape.edges.size(), " edges")
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	check(scene.projection_panel.selector.item_count == 7, "Dropdown entries")
	var matrix = scene.projection.rows.duplicate()
	scene.editor.edit_coordinate(3.25, 0, 0)
	scene.editor.undo()
	check(scene.editor.shape.vertices[0].x == -1, "Undo")
	scene.editor.redo()
	check(scene.editor.shape.vertices[0].x == 3.25, "Redo")
	scene.vertex_panel.tab.pressed.emit()
	check(not scene.vertex_panel.panel.visible, "Right collapse")
	scene.projection_panel.tab.pressed.emit()
	check(not scene.projection_panel.panel.visible, "Left collapse")
	for index in range(7):
		scene.select_shape(index)
		check(scene.vertex_panel.fields.size() <= 64, "Bounded editor fields")
		check(scene.projection.rows == matrix, "Preserved matrix")
		check(not scene.vertex_panel.panel.visible, "Preserved collapsed state")
		check(not scene.editor.history.has_undo(), "History cleared on switch")
		var last: int = scene.editor.shape.vertices.size() - 1
		scene.vertex_panel.change_page(last / 16)
		scene.vertex_panel.select_vertex(last)
		check(scene.selected == last, "Selection signal")
		var original: Vector4 = scene.editor.shape.vertices[last]
		var field: SpinBox = scene.vertex_panel.fields[(last % 16) * 4]
		field.get_line_edit().text = "4.375"
		field.apply()
		check(is_equal_approx(scene.editor.shape.vertices[last].x, 4.375), "Page edit signal")
		scene.editor.reset_vertices(false, last)
		check(scene.editor.shape.vertices[last] == original, "Reset generated coordinates")
		scene.editor.undo()
		check(is_equal_approx(scene.editor.shape.vertices[last].x, 4.375), "Undo reset")
		scene.editor.reset_vertices(true, last)
		check(scene.editor.shape.vertices == scene.editor.shape.original_vertices, "Reset all")
		await process_frame
	scene.select_shape(0)
	# Tesseract was explicitly reset in the loop; test cache persistence independently.
	scene.editor.edit_coordinate(6, 0, 3)
	scene.select_shape(1)
	scene.select_shape(0)
	check(scene.editor.shape.vertices[0].w == 6, "Cached model edits")
	var before = scene.projection.project(scene.editor.shape.vertices)
	scene.editor.edit_coordinate(9, 0, 3)
	check(scene.projection.project(scene.editor.shape.vertices) == before, "Discarded axis")
	scene.projection_panel.fields[3].get_line_edit().text = "1"
	scene.projection_panel.apply_matrix()
	check(scene.projection.rows[0].w == 1, "Matrix apply signal")
	check(scene.projection.project(scene.editor.shape.vertices)[0].x == 8, "Mixed projection")
	scene.projection_panel.reset_matrix()
	check(scene.projection.rows == matrix, "Reset matrix")
	scene.vertex_panel.tab.pressed.emit()
	scene.projection_panel.tab.pressed.emit()
	await process_frame
	await process_frame
	check(scene.vertex_panel.panel.get_global_rect().end.x <= root.get_visible_rect().end.x, "Right panel bounds")
	check(scene.vertex_panel.panel.get_global_rect().end.y <= root.get_visible_rect().end.y, "Vertical panel bounds")
	print("Validation failures: ", failures)
	quit(1 if failures else 0)
