extends RefCounted
## Local procedural styling matched to Playground; does not change the project theme.
static func box(color: String, padding: int = 8, radius: int = 6, border: String = "") -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	if not border.is_empty():
		style.set_border_width_all(1)
		style.border_color = Color(border)
	return style

static func create() -> Theme:
	var result := Theme.new()
	result.default_font_size = 16
	result.set_stylebox("panel", "PanelContainer", box("202b3b", 16, 12))
	for type in ["Button", "OptionButton"]:
		result.set_stylebox("normal", type, box("2c3a4f", 8, 6, "40516a"))
		result.set_stylebox("hover", type, box("374a64", 8, 6, "6b8bb0"))
		result.set_stylebox("pressed", type, box("365d7e", 8, 6, "74b7df"))
		result.set_stylebox("focus", type, box("365d7e00", 8, 6, "74b7df"))
	result.set_stylebox("normal", "LineEdit", box("141e2b", 8, 5, "40516a"))
	result.set_stylebox("focus", "LineEdit", box("141e2b", 8, 5, "74b7df"))
	result.set_stylebox("panel", "TabContainer", box("192333", 10, 6))
	result.set_stylebox("tab_selected", "TabContainer", box("344960", 8, 6))
	result.set_stylebox("tab_unselected", "TabContainer", box("202b3b", 8, 6))
	result.set_stylebox("tab_hovered", "TabContainer", box("2c3a4f", 8, 6))
	result.set_constant("separation", "VBoxContainer", 10)
	result.set_constant("separation", "HBoxContainer", 8)
	return result
