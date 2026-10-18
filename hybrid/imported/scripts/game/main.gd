extends Control

const World = preload("res://hybrid/imported/scripts/game/puzzle_world.gd")
const SliceView = preload("res://hybrid/imported/scripts/game/slice_view.gd")
const CYAN := Color("65e4d5")
const MUTED := Color("94a8c1")
const WHITE := Color("e8f1fb")
const SPEED := 2.0

var world := World.new()
var player_position: Vector4:
	get: return world.player_position
	set(value): world.set_player(value)
var mode := 0
var won := false
var switches := 0
var elapsed := 0.0
var bump_timer := 0.0
var orbiting := false
var view: Node3D
var viewport_container: SubViewportContainer
var slice_viewport: SubViewport
var mode_buttons: Array[Button] = []
var coordinate_labels: Array[Label] = []
var coordinate_bars: Array[ProgressBar] = []
var mode_label: Label
var frozen_label: Label
var hint_label: Label
var controls_label: Label
var status_label: Label
var goal_label: Label
var stats_label: Label
var hint_heading: Label


func _ready() -> void:
	setup_input()
	build_ui()
	set_mode(0, false)


func setup_input() -> void:
	var actions := {
		"move_left": KEY_A, "move_right": KEY_D,
		"move_forward": KEY_W, "move_back": KEY_S,
		"move_down": KEY_Q, "move_up": KEY_E,
		"move_slow": KEY_SHIFT,
	}
	for action in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = actions[action]
			InputMap.action_add_event(action, event)


func _physics_process(delta: float) -> void:
	if not get_window().has_focus():
		orbiting = false
		return
	if not won:
		elapsed += delta
	bump_timer = maxf(0.0, bump_timer - delta)
	var direction := Vector3(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_down", "move_up"),
		Input.get_axis("move_forward", "move_back")
	)
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	var speed := SPEED * (0.3 if Input.is_action_pressed("move_slow") else 1.0)
	move_player(direction * speed * delta)
	update_hud()


func move_player(delta: Vector3) -> void:
	var desired := player_position + World.to_world_delta(delta, mode)
	player_position = world.move_player(player_position, delta, mode)
	if (desired - player_position).length() > 0.0005:
		bump_timer = 0.35
	if world.reached_goal(player_position):
		won = true
	view.set_player(player_position)


func set_mode(new_mode: int, count_switch: bool = true) -> void:
	if new_mode < 0 or new_mode >= World.MODES.size():
		return
	if mode != new_mode and count_switch:
		switches += 1
	mode = new_mode
	# Crucially: player_position is never reassigned by a view switch.
	view.rebuild(world, player_position, mode)
	update_hud()


func restart() -> void:
	player_position = World.START
	won = false
	switches = 0
	elapsed = 0.0
	bump_timer = 0.0
	orbiting = false
	set_mode(0, false)
	view.reset_camera()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: set_mode(0)
			KEY_2: set_mode(1)
			KEY_3: set_mode(2)
			KEY_4: set_mode(3)
			KEY_TAB: set_mode(1 if mode == 0 else 0)
			KEY_R: restart()
			KEY_C: view.reset_camera()
	if event is InputEventMouseButton:
		var inside := viewport_container.get_global_rect().has_point(get_global_mouse_position())
		if event.button_index == MOUSE_BUTTON_RIGHT:
			orbiting = event.pressed and inside
		if inside and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				view.change_zoom(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				view.change_zoom(1)
	if event is InputEventMouseMotion and orbiting:
		view.orbit(event.relative)


func update_hud() -> void:
	var hidden: int = World.MODES[mode]["hidden"]
	var axes: Array = World.MODES[mode]["axes"]
	mode_label.text = "%s  /  ACTIVE SLICE" % World.MODES[mode]["name"]
	frozen_label.text = "%s = %.2f held fixed" % [World.AXIS_NAMES[hidden], player_position[hidden]]
	for i in range(4):
		var is_hidden := i == hidden
		coordinate_labels[i].text = "%s    %.2f%s" % [World.AXIS_NAMES[i], player_position[i], "   FIXED" if is_hidden else ""]
		coordinate_labels[i].modulate = Color("c3a0ff") if is_hidden else WHITE
		coordinate_bars[i].value = player_position[i]
		mode_buttons[i].button_pressed = i == mode
	controls_label.text = "A / D     −%s / +%s\nW / S    −%s / +%s\nQ / E     −%s / +%s\nShift      Precision movement" % [World.AXIS_NAMES[axes[0]], World.AXIS_NAMES[axes[0]], World.AXIS_NAMES[axes[2]], World.AXIS_NAMES[axes[2]], World.AXIS_NAMES[axes[1]], World.AXIS_NAMES[axes[1]]]
	stats_label.text = "%02d:%02d   /   %d switches" % [int(elapsed) / 60, int(elapsed) % 60, switches]
	if won:
		hint_heading.text = "COMPLETE  /  ROUTE FOUND"
		hint_heading.modulate = CYAN
		hint_label.text = "You crossed a 4D wall by changing slices. Keep exploring, or press R to try again."
	elif player_position.x > 0.71:
		hint_heading.text = "03  /  REACH THE EXIT"
		hint_label.text = "Move into the gold box near x = 2, y = 0, z = 0, w = 3. The exit checks all four coordinates."
	elif player_position.w > 2.25 and player_position.w < 3.75:
		hint_heading.text = "02  /  CROSS THE DOORWAY"
		hint_label.text = "Press 1 for XYZ. Keep y and z near 0, then hold D to move through the wall toward x = 2."
	elif mode == 1:
		hint_heading.text = "01  /  FIND ANOTHER SLICE"
		hint_label.text = "X is now fixed. Hold D to move along W toward 3. The cyan wire box marks the useful range."
	else:
		hint_heading.text = "01  /  A WALL IN THREE DIMENSIONS"
		hint_label.text = "At w = 0, the route is blocked. Press 2 for YZW, then move along the fourth dimension."
	if not won:
		hint_heading.modulate = WHITE
	goal_label.text = "GOLD = EXIT   ·   CYAN = YOU / GUIDE"
	if bump_timer > 0.0:
		status_label.text = "BLOCKED  /  4D collision or room boundary. Try a different slice."
		status_label.modulate = Color("ffce7a")
	elif view.visible_solids == 0:
		status_label.text = "This slice misses the wall. The wall still exists at x = 0."
		status_label.modulate = MUTED
	else:
		status_label.text = "Continuous movement  /  no gravity  /  view changes preserve your 4D position"
		status_label.modulate = MUTED
	if not world.motor.error.is_empty():
		status_label.text = world.motor.error
		status_label.modulate = Color("ffce7a")


func build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("0b1220")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 22)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 18)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	titles.add_child(label("FOURTH ROOM", 29, WHITE))
	titles.add_child(label("A four-dimensional world. One three-dimensional slice at a time.", 15, MUTED))
	var lab_button := make_button("Projection Lab  ↗")
	lab_button.tooltip_text = "Open the technical lab. Returning starts a fresh puzzle."
	lab_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/app.tscn"))
	header.add_child(lab_button)
	var tag := label("EXPERIMENT 01\nTHE HIDDEN DOORWAY", 14, CYAN)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_theme_constant_override("separation", 18)
	header.add_child(tag)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	layout.add_child(body)
	var sidebar := PanelContainer.new()
	sidebar.custom_minimum_size.x = 298
	sidebar.add_theme_stylebox_override("panel", panel(Color("142033")))
	body.add_child(sidebar)
	var side_scroll := ScrollContainer.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(side_scroll)
	var side_margin := MarginContainer.new()
	side_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for edge in ["left", "right", "top", "bottom"]:
		side_margin.add_theme_constant_override("margin_" + edge, 18)
	side_scroll.add_child(side_margin)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 7)
	side_margin.add_child(side)
	side.add_child(label("CHOOSE YOUR DIMENSIONS", 13, MUTED))
	var mode_grid := GridContainer.new()
	mode_grid.columns = 2
	mode_grid.add_theme_constant_override("h_separation", 8)
	mode_grid.add_theme_constant_override("v_separation", 8)
	side.add_child(mode_grid)
	for i in range(4):
		var button := make_button("%d   %s" % [i + 1, World.MODES[i]["name"]])
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(120, 42)
		button.pressed.connect(set_mode.bind(i))
		mode_grid.add_child(button)
		mode_buttons.append(button)
	side.add_child(label("Tab toggles XYZ / YZW", 13, MUTED))
	side.add_child(HSeparator.new())
	side.add_child(label("YOUR 4D POSITION", 13, MUTED))
	for axis in range(4):
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		side.add_child(row)
		var coordinate := label("", 17, WHITE)
		coordinate_labels.append(coordinate)
		row.add_child(coordinate)
		var bar := ProgressBar.new()
		bar.custom_minimum_size.y = 4
		bar.show_percentage = false
		bar.min_value = World.MIN_CENTER[axis]
		bar.max_value = World.MAX_CENTER[axis]
		bar.add_theme_stylebox_override("background", panel(Color("26354b"), 2))
		bar.add_theme_stylebox_override("fill", panel(SliceView.AXIS_COLORS[axis], 2))
		row.add_child(bar)
		coordinate_bars.append(bar)
	side.add_child(HSeparator.new())
	side.add_child(label("MOVE IN THE ACTIVE AXES", 13, MUTED))
	controls_label = label("", 15, WHITE)
	controls_label.add_theme_constant_override("line_spacing", 4)
	side.add_child(controls_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spacer)
	side.add_child(label("Right-drag  Orbit camera\nScroll  Zoom   ·   C  Reset camera", 13, MUTED))
	var reset_button := make_button("R   Restart puzzle")
	reset_button.pressed.connect(restart)
	side.add_child(reset_button)
	stats_label = label("", 13, MUTED)
	side.add_child(stats_label)
	var main_column := VBoxContainer.new()
	main_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_column.add_theme_constant_override("separation", 12)
	body.add_child(main_column)
	var view_header := HBoxContainer.new()
	main_column.add_child(view_header)
	mode_label = label("", 17, CYAN)
	mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_header.add_child(mode_label)
	frozen_label = label("", 15, Color("c3a0ff"))
	view_header.add_child(frozen_label)
	viewport_container = SubViewportContainer.new()
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.stretch = true
	viewport_container.custom_minimum_size = Vector2(400, 320)
	main_column.add_child(viewport_container)
	slice_viewport = SubViewport.new()
	slice_viewport.own_world_3d = true
	slice_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	slice_viewport.msaa_3d = Viewport.MSAA_4X
	viewport_container.add_child(slice_viewport)
	view = SliceView.new()
	slice_viewport.add_child(view)
	goal_label = label("", 12, MUTED)
	main_column.add_child(goal_label)
	var hint_panel := PanelContainer.new()
	hint_panel.add_theme_stylebox_override("panel", panel(Color("182a3c")))
	main_column.add_child(hint_panel)
	var hint_margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		hint_margin.add_theme_constant_override("margin_" + edge, 16)
	hint_panel.add_child(hint_margin)
	var hint_box := VBoxContainer.new()
	hint_box.add_theme_constant_override("separation", 8)
	hint_margin.add_child(hint_box)
	hint_heading = label("", 14, WHITE)
	hint_box.add_child(hint_heading)
	hint_label = label("", 16, WHITE)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.custom_minimum_size.y = 46
	hint_box.add_child(hint_label)
	status_label = label("", 13, WHITE)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(status_label)


static func label(text: String, size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	return result


static func panel(color: Color, radius: int = 8) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.set_corner_radius_all(radius)
	return result


static func make_button(text: String) -> Button:
	var result := Button.new()
	result.text = text
	result.focus_mode = Control.FOCUS_NONE
	result.custom_minimum_size.y = 38
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.add_theme_font_size_override("font_size", 16)
	result.add_theme_color_override("font_color", WHITE)
	result.add_theme_color_override("font_pressed_color", Color("092b2c"))
	result.add_theme_stylebox_override("normal", panel(Color("26354b")))
	result.add_theme_stylebox_override("hover", panel(Color("354964")))
	result.add_theme_stylebox_override("pressed", panel(CYAN))
	return result
