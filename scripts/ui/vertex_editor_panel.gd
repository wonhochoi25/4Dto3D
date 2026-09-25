extends "res://scripts/ui/collapsible_panel.gd"
## Paged table: at most 16 vertices / 64 fields exist even for the 120-cell.
## Signals express edits; GeometryEditor owns mutation and history.
signal coordinate_changed(value: float, vertex: int, axis: int)
signal vertex_selected(index: int)
signal reset_requested(all_vertices: bool)
signal undo_requested
signal redo_requested
const Settings = preload("res://scripts/ui/ui_settings.gd")
const PAGE_SIZE := 16
var shape
var selected := 0
var page := 0
var grid: GridContainer
var fields: Array[SpinBox] = []
var ids: Array[int] = []
var selectors: Array[Button] = []
var selection_label: Label
var page_label: Label
var previous: Button
var next: Button
var undo_button: Button
var redo_button: Button

func _ready() -> void:
	setup(true)
	add_label(box, "4D vertex editor", 23)
	add_label(box, "Enter or leave a field to commit.\nEdges keep their vertex connections.", 14)
	selection_label = add_label(box, "", 14)
	var navigation := HBoxContainer.new()
	box.add_child(navigation)
	previous = button(navigation, "‹ Previous", func(): change_page(page - 1))
	page_label = add_label(navigation, "", 14)
	next = button(navigation, "Next ›", func(): change_page(page + 1))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	box.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	button(actions, "Reset selected", func(): reset_requested.emit(false))
	button(actions, "Reset all", func(): reset_requested.emit(true))
	var history_actions := HBoxContainer.new()
	box.add_child(history_actions)
	undo_button = button(history_actions, "Undo", func(): undo_requested.emit())
	redo_button = button(history_actions, "Redo", func(): redo_requested.emit())
	add_label(box, "Gold = selected vertex and connected edges.\nEdits along discarded axes may be invisible.", 14)

func show_shape(model) -> void:
	shape = model
	selected = 0
	page = 0
	rebuild_page()
	select_vertex(0)

func change_page(index: int) -> void:
	page = clampi(index, 0, (shape.vertices.size() - 1) / PAGE_SIZE)
	rebuild_page()

func rebuild_page() -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	fields.clear()
	ids.clear()
	selectors.clear()
	for title in ["ID", "X", "Y", "Z", "W"]:
		add_label(grid, title, 14)
	var group := ButtonGroup.new()
	for vertex in range(page * PAGE_SIZE, mini((page + 1) * PAGE_SIZE, shape.vertices.size())):
		ids.append(vertex)
		var selector := button(grid, "V%d" % vertex, select_vertex.bind(vertex))
		selector.toggle_mode = true
		selector.button_group = group
		selector.set_pressed_no_signal(vertex == selected)
		selectors.append(selector)
		for axis in range(4):
			var field := SpinBox.new()
			field.allow_greater = true
			field.allow_lesser = true
			field.step = Settings.FIELD_STEP
			field.custom_minimum_size.x = 76
			field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			field.value = shape.vertices[vertex][axis]
			field.tooltip_text = "V%d · %s" % [vertex, ["X", "Y", "Z", "W"][axis]]
			field.value_changed.connect(on_coordinate_changed.bind(vertex, axis))
			field.get_line_edit().focus_entered.connect(select_vertex.bind(vertex))
			grid.add_child(field)
			fields.append(field)
	var pages := ceili(float(shape.vertices.size()) / PAGE_SIZE)
	page_label.text = "%d / %d" % [page + 1, pages]
	previous.disabled = page == 0
	next.disabled = page == pages - 1

func on_coordinate_changed(value: float, vertex: int, axis: int) -> void:
	if is_finite(value):
		coordinate_changed.emit(value, vertex, axis)
	else:
		sync_fields()

func select_vertex(index: int) -> void:
	selected = index
	selection_label.text = "Selected: V%d · X, Y, Z, W" % index
	for i in range(ids.size()):
		selectors[i].set_pressed_no_signal(ids[i] == index)
	vertex_selected.emit(index)

## Refresh visible fields without emitting changes or quantizing model coordinates.
func sync_fields() -> void:
	for i in range(ids.size()):
		for axis in range(4):
			var field := fields[i * 4 + axis]
			field.set_value_no_signal(shape.vertices[ids[i]][axis])
			field.get_line_edit().text = str(shape.vertices[ids[i]][axis])

func show_history(can_undo: bool, can_redo: bool) -> void:
	undo_button.disabled = not can_undo
	redo_button.disabled = not can_redo
