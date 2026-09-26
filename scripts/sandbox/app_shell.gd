extends Control
## Browser-style workspace: each tab owns a SubViewport and separate World3D.
## Playground's existing scene/scripts are instantiated unchanged.
const Playground = preload("res://scenes/main.tscn")
const Procedural = preload("res://scripts/sandbox/procedural/procedural_scene.gd")
var pages: Array = []
var active := -1
var serial := 0
var tabs: HBoxContainer
var content: Control
var add_tab_button: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 0)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)
	var strip := PanelContainer.new()
	var background := StyleBoxFlat.new()
	background.bg_color = Color("101722")
	background.content_margin_left = 12
	background.content_margin_top = 8
	background.content_margin_bottom = 4
	strip.add_theme_stylebox_override("panel", background)
	layout.add_child(strip)
	var bar := HBoxContainer.new()
	strip.add_child(bar)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bar.add_child(scroll)
	tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	scroll.add_child(tabs)
	var add := Button.new()
	add_tab_button = add
	add.text = "+"
	add.tooltip_text = "New procedural experiment"
	add.custom_minimum_size = Vector2(44, 38)
	add.pressed.connect(new_procedural)
	style_tab_button(add)
	add.add_theme_font_size_override("font_size", 24)
	tabs.add_child(add)
	content = Control.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(content)
	content.resized.connect(sync_tab_resolution)
	get_viewport().size_changed.connect(sync_tab_resolution)
	add_page(Playground.instantiate(), "Playground", false)

## Visible tab surfaces distinguish the active workspace from inactive tabs.
func style_tab_button(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var selected: bool = state in ["pressed", "hover_pressed"]
		var style := StyleBoxFlat.new()
		style.bg_color = Color("304b65") if selected else Color("202c3c")
		if state == "hover": style.bg_color = Color("2b3b50")
		style.border_color = Color("79c8ef") if selected else Color("465a72")
		style.set_border_width_all(1)
		style.border_width_bottom = 3 if selected else 1
		style.corner_radius_top_left = 9
		style.corner_radius_top_right = 9
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color("c3cedd"))
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_font_size_override("font_size", 16)

func new_procedural() -> void:
	serial += 1
	add_page(Procedural.new(), "Procedural %d" % serial, true)

func add_page(scene: Node, title: String, closable: bool) -> void:
	var host := SubViewportContainer.new()
	host.stretch = true
	host.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	content.add_child(host)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.handle_input_locally = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.size_2d_override_stretch = true
	host.add_child(viewport)
	configure_tab_resolution(host, viewport)
	viewport.add_child(scene)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 0)
	tabs.add_child(header)
	tabs.move_child(header, add_tab_button.get_index())
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(160, 42)
	style_tab_button(button)
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	header.add_child(button)
	var page := {"host": host, "viewport": viewport, "scene": scene, "header": header, "button": button, "closable": closable}
	pages.append(page)
	button.pressed.connect(func(): activate(pages.find(page)))
	if closable:
		var close := Button.new()
		close.text = "×"
		close.custom_minimum_size = Vector2(32, 42)
		style_tab_button(close)
		close.tooltip_text = "Close " + title
		close.focus_mode = Control.FOCUS_NONE
		header.add_child(close)
		close.pressed.connect(func(): close_page(pages.find(page)))
	activate(pages.size() - 1)

func activate(index: int) -> void:
	if index < 0 or index >= pages.size(): return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in range(pages.size()):
		var page: Dictionary = pages[i]
		var enabled := i == index
		if not enabled and page["scene"].has_method("deactivate"): page["scene"].deactivate()
		page["host"].visible = enabled
		page["host"].process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
		page["viewport"].gui_disable_input = not enabled
		page["viewport"].render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED
		page["button"].set_pressed_no_signal(enabled)
	active = index

func close_page(index: int) -> void:
	if index < 0 or index >= pages.size() or not pages[index]["closable"]: return
	var previous = pages[active]
	var page = pages[index]
	pages.remove_at(index)
	page["host"].process_mode = Node.PROCESS_MODE_DISABLED
	content.remove_child(page["host"])
	tabs.remove_child(page["header"])
	page["host"].queue_free()
	page["header"].queue_free()
	activate(pages.find(previous) if pages.has(previous) else maxi(0, index - 1))

## Render at actual output pixels, not the root canvas's lower logical resolution.
## Counter-scale the container and override the child canvas so UI/input stay logical.
func configure_tab_resolution(host: SubViewportContainer, viewport: SubViewport) -> void:
	var logical := content.size.max(Vector2(2, 2))
	var output_scale := get_viewport().get_final_transform().get_scale().abs()
	var pixels := (logical * output_scale).round().max(Vector2(2, 2))
	host.scale = logical / pixels
	host.size = pixels
	viewport.size_2d_override = Vector2i(logical.round())

func sync_tab_resolution() -> void:
	for page in pages:
		configure_tab_resolution(page["host"], page["viewport"])
