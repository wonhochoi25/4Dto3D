extends VBoxContainer
## Parameter editor. Emits intent; Main updates the active Transform4D instance.
signal parameter_changed(component: String, axis: int, value: float)
signal option_changed(option: String, enabled: bool)
signal reset_requested
const Settings = preload("res://scripts/ui/ui_settings.gd")
var controls: Dictionary = {}
var rotation_sliders: Array[HSlider] = []
var scale_sliders: Array[HSlider] = []
var scale_min_field: SpinBox
var scale_max_field: SpinBox
var scale_range_message: Label
var scale_min := -3.0
var scale_max := 3.0
var displayed_scale := Vector4.ONE
var keep: CheckBox
var uniform: CheckBox
var readout: Label

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	label("4D Transform · PRSA", 21)
	label("Position is where the anchor goes. Commit to update.")
	vector_controls("Position", "position")
	vector_controls("Anchor", "anchor")
	keep = CheckBox.new()
	keep.text = "Keep shape in place when changing anchor"
	keep.button_pressed = true
	keep.toggled.connect(func(enabled: bool): option_changed.emit("keep_in_place", enabled))
	add_child(keep)
	build_scale_controls()
	uniform = CheckBox.new()
	uniform.text = "Uniform scale (next edit sets all four axes)"
	uniform.toggled.connect(func(enabled: bool): option_changed.emit("uniform_scale", enabled))
	add_child(uniform)
	label("Rotation (degrees) · applied in the order below")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	add_child(grid)
	var names := ["XY", "XZ", "XW", "YZ", "YW", "ZW"]
	var fields: Array[SpinBox] = []
	for axis in range(6):
		var title := Label.new()
		title.text = names[axis]
		grid.add_child(title)
		var slider := HSlider.new()
		slider.min_value = -180
		slider.max_value = 180
		slider.step = Settings.FIELD_STEP
		slider.custom_minimum_size.x = 220
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.tooltip_text = names[axis] + " rotation in degrees"
		slider.value_changed.connect(func(value: float): parameter_changed.emit("angles", axis, value))
		grid.add_child(slider)
		rotation_sliders.append(slider)
		fields.append(numeric_field(grid, "angles", axis))
	controls["angles"] = fields
	var reset := Button.new()
	reset.text = "Reset transform"
	reset.pressed.connect(func(): reset_requested.emit())
	add_child(reset)
	readout = label("")
	readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	readout.custom_minimum_size.x = 460
	label("Base vertices stay unchanged. Vertex Undo excludes transforms.")

func label(text: String, size: int = 14) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	add_child(result)
	return result

func numeric_field(parent: Node, component: String, axis: int) -> SpinBox:
	var field := SpinBox.new()
	field.allow_greater = true
	field.allow_lesser = true
	field.step = Settings.FIELD_STEP
	field.custom_minimum_size.x = 82
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.value_changed.connect(func(value: float): parameter_changed.emit(component, axis, value))
	parent.add_child(field)
	return field

func vector_controls(title: String, component: String) -> void:
	label(title, 16)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 5)
	add_child(grid)
	var fields: Array[SpinBox] = []
	for axis in range(4):
		var name_label := Label.new()
		name_label.text = ["X", "Y", "Z", "W"][axis]
		grid.add_child(name_label)
		fields.append(numeric_field(grid, component, axis))
	controls[component] = fields

## Suppressed signals prevent compensation or field refresh from becoming another edit.
func show_transform(model) -> void:
	for component in controls:
		var values = model.get(component)
		for axis in range(controls[component].size()):
			var field: SpinBox = controls[component][axis]
			field.set_value_no_signal(values[axis])
			field.get_line_edit().text = str(values[axis])
	# Keep typed multi-turn angles intact; expand the slider range when necessary.
	for axis in range(rotation_sliders.size()):
		var slider := rotation_sliders[axis]
		var angle: float = model.angles[axis]
		var extent := maxf(180.0, ceilf(absf(angle) / 180.0) * 180.0)
		slider.set_block_signals(true)
		slider.min_value = -extent
		slider.max_value = extent
		slider.set_value_no_signal(angle)
		slider.set_block_signals(false)
	displayed_scale = model.scale
	sync_scale_sliders()
	keep.set_pressed_no_signal(model.keep_in_place)
	uniform.set_pressed_no_signal(model.uniform_scale)

func show_vertex(index: int, original: Vector4, transformed: Vector4, projected: Vector3) -> void:
	readout.text = "V%d\\nOriginal 4D: %s\\nTransformed 4D: %s\\nProjected 3D: (%.3f, %.3f, %.3f)".replace("\\n", "\n") % [index, format_point(original), format_point(transformed), projected.x, projected.y, projected.z]

func format_point(point: Vector4) -> String:
	return "(%.3f, %.3f, %.3f, %.3f)" % [point.x, point.y, point.z, point.w]

## Slider bounds are view settings, shared across shapes, and never modify geometry.
func build_scale_controls() -> void:
	label("Scale", 16)
	var bounds := HBoxContainer.new()
	add_child(bounds)
	for title in ["Min", "Max"]:
		var text := Label.new()
		text.text = title
		bounds.add_child(text)
		var field := SpinBox.new()
		field.allow_greater = true
		field.allow_lesser = true
		field.step = Settings.FIELD_STEP
		field.custom_minimum_size.x = 100
		field.value = scale_min if title == "Min" else scale_max
		bounds.add_child(field)
		if title == "Min": scale_min_field = field
		else: scale_max_field = field
	var apply := Button.new()
	apply.text = "Apply range"
	apply.pressed.connect(apply_scale_range)
	bounds.add_child(apply)
	scale_range_message = label("Shared range for X, Y, Z, W. Zero collapses; negatives reflect.")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	add_child(grid)
	var fields: Array[SpinBox] = []
	for axis in range(4):
		var title := Label.new()
		title.text = ["X", "Y", "Z", "W"][axis]
		grid.add_child(title)
		var slider := HSlider.new()
		slider.min_value = scale_min
		slider.max_value = scale_max
		slider.step = Settings.FIELD_STEP
		slider.custom_minimum_size.x = 220
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(func(value: float): parameter_changed.emit("scale", axis, value))
		grid.add_child(slider)
		scale_sliders.append(slider)
		fields.append(numeric_field(grid, "scale", axis))
	controls["scale"] = fields

## Apply both bounds together, allowing ranges entirely above or below the old range.
func apply_scale_range() -> void:
	scale_min_field.apply()
	scale_max_field.apply()
	var lower := scale_min_field.value
	var upper := scale_max_field.value
	if not is_finite(lower) or not is_finite(upper) or lower >= upper:
		scale_range_message.text = "Enter finite bounds with Min less than Max."
		return
	scale_min = lower
	scale_max = upper
	sync_scale_sliders()
	scale_range_message.text = "Range applied; expanded if needed to include current scales."

## Suppress Range signals while setting bounds: Godot may clamp intermediate values.
func sync_scale_sliders() -> void:
	for axis in range(4):
		scale_min = minf(scale_min, displayed_scale[axis])
		scale_max = maxf(scale_max, displayed_scale[axis])
	for axis in range(4):
		var slider := scale_sliders[axis]
		slider.set_block_signals(true)
		# Expand first so setting a new minimum cannot push the maximum unexpectedly.
		slider.max_value = maxf(slider.max_value, scale_max)
		slider.min_value = scale_min
		slider.max_value = scale_max
		slider.set_value_no_signal(displayed_scale[axis])
		slider.set_block_signals(false)
	scale_min_field.set_value_no_signal(scale_min)
	scale_max_field.set_value_no_signal(scale_max)
	scale_min_field.get_line_edit().text = str(scale_min)
	scale_max_field.get_line_edit().text = str(scale_max)
