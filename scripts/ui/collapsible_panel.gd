extends CanvasLayer
## Persistent screen-edge tab plus content panel; collapsing never destroys data.
var panel: PanelContainer
var box: VBoxContainer
var tab: Button

func setup(right: bool) -> void:
	panel = PanelContainer.new()
	add_child(panel)
	if right:
		panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		panel.offset_left = -482
		panel.offset_right = -32
		panel.offset_top = 20
		panel.offset_bottom = -20
	else:
		panel.position = Vector2(32, 20)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("202b3b")
	style.set_corner_radius_all(12)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	tab = Button.new()
	add_child(tab)
	tab.focus_mode = Control.FOCUS_NONE
	tab.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT if right else Control.PRESET_CENTER_LEFT)
	tab.offset_left = -28 if right else 0
	tab.offset_right = 0 if right else 28
	tab.offset_top = -45
	tab.offset_bottom = 45
	tab.pressed.connect(func():
		panel.visible = not panel.visible
		get_viewport().gui_release_focus()
		update_tab(right))
	update_tab(right)

func update_tab(right: bool) -> void:
	tab.text = (">" if right else "<") if panel.visible else ("<" if right else ">")
	tab.tooltip_text = ("Collapse " if panel.visible else "Show ") + ("vertex editor" if right else "projection controls")

func button(parent: Node, text: String, action: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.pressed.connect(action)
	parent.add_child(result)
	return result

func add_label(parent: Node, text: String, size: int = 16) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label
