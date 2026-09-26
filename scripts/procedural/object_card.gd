extends PanelContainer
## Expression form is a draft until Apply; a failed apply leaves running programs intact.
signal apply_requested(card)
signal remove_requested(card)
signal style_changed(card)
var object
var renderer
var fields: Dictionary = {}
var errors: Dictionary = {}
var body: VBoxContainer
var message: Label
var runtime_error := false
var heading: Label
var anchor_keep_toggle: CheckBox

func setup(model, mesh_renderer) -> void:
	add_theme_stylebox_override("panel", preload("res://scripts/procedural/procedural_theme.gd").box("192333", 12, 8, "40516a"))
	object = model
	renderer = mesh_renderer
	var box := VBoxContainer.new()
	add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	heading = Label.new()
	heading.text = object.node_name
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	var remove := Button.new()
	remove.text = "Remove shape"
	remove.pressed.connect(func(): remove_requested.emit(self))
	header.add_child(remove)
	body = VBoxContainer.new()
	box.add_child(body)
	var appearance := HBoxContainer.new()
	body.add_child(appearance)
	var visible_toggle := CheckBox.new()
	visible_toggle.text = "Visible"
	visible_toggle.button_pressed = true
	visible_toggle.toggled.connect(func(value: bool): object.visible = value; style_changed.emit(self))
	appearance.add_child(visible_toggle)
	var edge_toggle := CheckBox.new()
	edge_toggle.text = "Edges"
	edge_toggle.button_pressed = object.show_edges
	edge_toggle.toggled.connect(func(value: bool): object.show_edges = value; style_changed.emit(self))
	appearance.add_child(edge_toggle)
	var color := ColorPickerButton.new()
	color.color = object.color
	color.edit_alpha = false
	color.custom_minimum_size = Vector2(48, 28)
	color.color_changed.connect(func(value: Color): object.color = Color(value.r, value.g, value.b, object.color.a); style_changed.emit(self))
	appearance.add_child(color)
	var opacity_label := Label.new()
	opacity_label.text = "Opacity"
	appearance.add_child(opacity_label)
	var opacity := HSlider.new()
	opacity.min_value = 0.01
	opacity.max_value = 1
	opacity.step = 0.01
	opacity.value = object.color.a
	opacity.custom_minimum_size.x = 100
	opacity.value_changed.connect(func(value: float): object.color.a = value; style_changed.emit(self))
	appearance.add_child(opacity)
	appearance.visible = not object.is_group
	var tabs := TabContainer.new()
	tabs.use_hidden_tabs_for_min_size = false
	body.add_child(tabs)
	for component in ["position", "angles", "scale", "anchor", "projection"]:
		if object.is_group and component == "projection": continue
		var section := VBoxContainer.new()
		section.name = "Rotation" if component == "angles" else component.capitalize()
		tabs.add_child(section)
		if component == "anchor":
			anchor_keep_toggle = CheckBox.new()
			anchor_keep_toggle.text = "Keep subtree in place when editing anchor" if object.is_group else "Keep shape in place when editing anchor"
			anchor_keep_toggle.button_pressed = object.keep_anchor_in_place
			anchor_keep_toggle.tooltip_text = "On Apply, compensate Position at the current time. Anchor animation still runs normally."
			anchor_keep_toggle.toggled.connect(func(enabled: bool): object.keep_anchor_in_place = enabled)
			section.add_child(anchor_keep_toggle)
			var note := Label.new()
			note.text = "Adjusts Position expressions at the current t on Apply."
			note.add_theme_font_size_override("font_size", 13)
			section.add_child(note)
		var names := ["X", "Y", "Z", "W"]
		if object.is_group and component == "scale": names = ["All"]
		if component == "angles": names = ["XY", "XZ", "XW", "YZ", "YW", "ZW"]
		if component == "projection":
			build_projection_matrix(section)
			continue
		for i in range(names.size()):
			var row := HBoxContainer.new()
			section.add_child(row)
			var title := Label.new()
			title.text = names[i]
			title.custom_minimum_size.x = 55
			row.add_child(title)
			var field := LineEdit.new()
			var key := "%s.%d" % [component, i]
			field.text = object.sources[key]
			field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			field.placeholder_text = "Expression in t"
			row.add_child(field)
			fields[key] = field
			var error_label := Label.new()
			error_label.add_theme_color_override("font_color", Color("ff9a9a"))
			error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			error_label.hide()
			section.add_child(error_label)
			errors[key] = error_label
	var apply := Button.new()
	apply.text = "Apply expressions"
	apply.pressed.connect(func(): apply_requested.emit(self))
	body.add_child(apply)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(message)
	message.hide()

func draft() -> Dictionary:
	var result: Dictionary = object.sources.duplicate()
	for key in fields: result[key] = fields[key].text
	return result

func show_error(field: String, text: String, during_playback: bool = false) -> void:
	clear_errors()
	runtime_error = during_playback
	message.show()
	message.text = text if field.is_empty() else "Error in " + field + ": " + text
	if errors.has(field):
		errors[field].text = text
		errors[field].show()
		fields[field].add_theme_color_override("font_color", Color("ff9a9a"))

func clear_errors() -> void:
	runtime_error = false
	for key in errors:
		errors[key].hide()
		fields[key].remove_theme_color_override("font_color")
	message.text = ""
	message.hide()

## Row-major 3×4 matrix: columns are 4D inputs, rows are 3D outputs.
## Keep expression keys unchanged so saved drafts and evaluation use the same mapping.
func build_projection_matrix(section: VBoxContainer) -> void:
	var hint := Label.new()
	hint.text = "Columns: 4D input · Rows: 3D output"
	section.add_child(hint)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	section.add_child(grid)
	for name in ["", "X", "Y", "Z", "W"]:
		var heading := Label.new()
		heading.text = name
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(heading)
	for row in range(3):
		var heading := Label.new()
		heading.text = ["X", "Y", "Z"][row]
		grid.add_child(heading)
		for column in range(4):
			var key := "projection.%d" % (row * 4 + column)
			var cell := VBoxContainer.new()
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(cell)
			var field := LineEdit.new()
			field.text = object.sources[key]
			field.custom_minimum_size.x = 90
			field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			field.tooltip_text = "Output %s ← input %s · expression in t" % [["X", "Y", "Z"][row], ["X", "Y", "Z", "W"][column]]
			cell.add_child(field)
			fields[key] = field
			var error_label := Label.new()
			error_label.add_theme_color_override("font_color", Color("ff9a9a"))
			error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			error_label.hide()
			cell.add_child(error_label)
			errors[key] = error_label
