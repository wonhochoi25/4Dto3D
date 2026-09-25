extends "res://scripts/ui/collapsible_panel.gd"
## Emits user intent; does not own the model or renderer.
signal shape_selected(index: int)
signal matrix_applied(rows: Array[Vector4])
signal camera_reset_requested
const Registry = preload("res://scripts/shapes/shape_registry.gd")
const Settings = preload("res://scripts/ui/ui_settings.gd")
var transform_panel: VBoxContainer
var tabs: TabContainer
var fields: Array[SpinBox] = []
var selector: OptionButton
var caption: Label
var status: Label

func _ready() -> void:
	setup(false)
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 32
	panel.offset_right = 610
	panel.offset_top = 20
	panel.offset_bottom = -20
	add_label(box, "4D → 3D Projection", 24)
	caption = add_label(box, "")
	add_label(box, "Choose a shape. Edit the matrix, then Apply.", 14)
	selector = OptionButton.new()
	for entry in Registry.ENTRIES:
		selector.add_item(entry["name"])
	selector.item_selected.connect(func(index: int): shape_selected.emit(index))
	box.add_child(selector)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)
	var projection_content := VBoxContainer.new()
	projection_content.name = "Projection"
	tabs.add_child(projection_content)
	var transform_scroll := ScrollContainer.new()
	transform_scroll.name = "Transform"
	transform_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	transform_scroll.follow_focus = true
	tabs.add_child(transform_scroll)
	transform_panel = preload("res://scripts/ui/transform_panel.gd").new()
	transform_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	transform_scroll.add_child(transform_panel)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	projection_content.add_child(grid)
	for title in ["Output ↓ / Input →", "X", "Y", "Z", "W"]:
		add_label(grid, title, 14)
	for row in range(3):
		add_label(grid, ["X", "Y", "Z"][row])
		for column in range(4):
			var field := SpinBox.new()
			field.allow_greater = true
			field.allow_lesser = true
			field.step = Settings.FIELD_STEP
			field.custom_minimum_size.x = 82
			field.value = 1 if row == column else 0
			fields.append(field)
			grid.add_child(field)
	var actions := HBoxContainer.new()
	projection_content.add_child(actions)
	button(actions, "Apply matrix", apply_matrix)
	button(actions, "Reset matrix", reset_matrix)
	button(actions, "Reset camera", func(): camera_reset_requested.emit())
	status = add_label(projection_content, "", 14)
	add_label(box, "Hold right mouse in viewport to look\nWASD move · Q/E down/up · Shift faster\nRelease right mouse or press Esc to edit", 14)

func apply_matrix() -> void:
	for field in fields:
		field.apply()
		if not is_finite(field.value):
			status.text = "Enter finite numbers in every field."
			return
	var rows: Array[Vector4] = []
	for row in range(3):
		rows.append(Vector4(fields[row * 4].value, fields[row * 4 + 1].value, fields[row * 4 + 2].value, fields[row * 4 + 3].value))
	matrix_applied.emit(rows)

func reset_matrix() -> void:
	for row in range(3):
		for column in range(4):
			var field := fields[row * 4 + column]
			field.set_value_no_signal(1 if row == column else 0)
			field.get_line_edit().text = str(field.value)
	apply_matrix()

func show_shape(shape, index: int) -> void:
	selector.select(index)
	caption.text = shape.display_name + " / editable 4D vertices"
	caption.tooltip_text = shape.description

func show_counts(shape, positions: PackedVector3Array) -> void:
	var unique: Array[Vector3] = []
	for point in positions:
		var found := false
		for other in unique:
			if point.is_equal_approx(other):
				found = true
				break
		if not found:
			unique.append(point)
	status.text = "%d vertices · %d edges\n%d distinct projected positions\nOverlapping vertices and collapsed edges are expected." % [shape.vertices.size(), shape.edges.size(), unique.size()]
