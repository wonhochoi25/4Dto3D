extends "res://hybrid/imported/scripts/game/main.gd"
## A separate campaign client. The original demo scripts/scenes remain untouched.
const LevelWorld = preload("res://hybrid/object_world.gd")
const LevelView = preload("res://hybrid/view.gd")
var level_index := 0
var detailed_hint := false
var completed := [false, false, false, false]
var level_buttons: Array[Button] = []
var next_button: Button
var help_button: Button
var shell_button: Button
var title_label: Label
var subtitle_label: Label
var chapter_label: Label
var camera_button: Button
var camera_rotation_enabled := false
var orbit_button := MOUSE_BUTTON_NONE

func _ready() -> void:
	world = LevelWorld.new(0)
	setup_input()
	build_ui()
	load_level(0)

func build_ui() -> void:
	super.build_ui()
	for item in find_children("*", "Label", true, false):
		if item.text.begins_with("Right-drag"):
			item.text = "Enable camera rotation to drag\nScroll  Zoom   ·   C  Reset camera"
			camera_button = make_button("Camera rotation: OFF")
			camera_button.toggle_mode = true
			camera_button.tooltip_text = "Enable, then left- or right-drag the scene. Disable to keep this viewing angle."
			camera_button.toggled.connect(set_camera_rotation)
			item.get_parent().add_child(camera_button)
			item.get_parent().move_child(camera_button, item.get_index())
		if item.text == "FOURTH ROOM": title_label = item
		if item.text.begins_with("A four-dimensional world."): subtitle_label = item
		if item.text.begins_with("EXPERIMENT 01"): chapter_label = item
	var old_view := view
	slice_viewport.remove_child(old_view)
	old_view.queue_free()
	view = LevelView.new()
	slice_viewport.add_child(view)
	var column := viewport_container.get_parent()
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 8)
	column.add_child(navigation)
	column.move_child(navigation, 0)
	for i in range(LevelWorld.LEVELS.size()):
		var button := make_button("CHAMBER %02d" % (i + 1))
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(load_level.bind(i))
		navigation.add_child(button)
		level_buttons.append(button)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	column.add_child(actions)
	help_button = make_button("H  Show hint")
	help_button.pressed.connect(toggle_hint)
	actions.add_child(help_button)
	shell_button = make_button("V  X-ray walls")
	shell_button.pressed.connect(toggle_shell)
	actions.add_child(shell_button)
	next_button = make_button("Reach the exit")
	next_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_button.pressed.connect(advance_level)
	actions.add_child(next_button)
	hint_label.custom_minimum_size.y = 64

func load_level(index: int) -> void:
	level_index = clampi(index, 0, LevelWorld.LEVELS.size() - 1)
	world = LevelWorld.new(level_index)
	mode = 0
	won = false
	switches = 0
	elapsed = 0.0
	bump_timer = 0.0
	set_camera_rotation(false)
	detailed_hint = false
	view.xray = world.definition.shell
	view.show_route = false
	for i in range(4):
		coordinate_bars[i].min_value = world.definition.low[i]
		coordinate_bars[i].max_value = world.definition.high[i]
	view.reset_camera()
	view.zoom = 9.0
	set_mode(0, false)

func restart() -> void:
	load_level(level_index)

func set_mode(new_mode: int, count_switch: bool = true) -> void:
	if not new_mode in world.definition.modes: return
	super.set_mode(new_mode, count_switch)

func move_player(delta: Vector3) -> void:
	if won: return
	var previous_stage: int = world.stage
	super.move_player(delta)
	if world.stage != previous_stage:
		detailed_hint = false
		view.show_route = false
		view.rebuild(world, player_position, mode)
	if won: completed[level_index] = true

func set_camera_rotation(enabled: bool) -> void:
	camera_rotation_enabled = enabled
	orbiting = false
	orbit_button = MOUSE_BUTTON_NONE
	camera_button.set_pressed_no_signal(enabled)
	camera_button.text = "Camera rotation: ON" if enabled else "Camera rotation: OFF"
	viewport_container.mouse_default_cursor_shape = Control.CURSOR_DRAG if enabled else Control.CURSOR_ARROW

func _input(event: InputEvent) -> void:
	# Handle mouse events here so the inherited right-drag cannot bypass the lock.
	if event is InputEventMouseButton:
		var inside := viewport_container.get_global_rect().has_point(event.position)
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			if not event.pressed and event.button_index == orbit_button:
				orbiting = false
				orbit_button = MOUSE_BUTTON_NONE
			elif event.pressed and inside and camera_rotation_enabled:
				orbiting = true
				orbit_button = event.button_index
		elif inside and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP: view.change_zoom(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: view.change_zoom(1)
		return
	if event is InputEventMouseMotion:
		if orbiting and camera_rotation_enabled:
			var mask := MOUSE_BUTTON_MASK_LEFT if orbit_button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
			if event.button_mask & mask:
				view.orbit(event.relative)
			else:
				orbiting = false
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_H: toggle_hint(); return
			KEY_V: toggle_shell(); return
			KEY_ENTER: advance_level(); return
	super._input(event)

func toggle_hint() -> void:
	detailed_hint = not detailed_hint
	view.show_route = detailed_hint
	view.rebuild(world, player_position, mode)
	update_hud()

func toggle_shell() -> void:
	view.xray = not view.xray
	view.rebuild(world, player_position, mode)
	update_hud()

func advance_level() -> void:
	if won: load_level((level_index + 1) % LevelWorld.LEVELS.size())

func update_hud() -> void:
	# Reuse coordinate/control widgets; replace all level-specific tutorial text.
	super.update_hud()
	if title_label == null: return
	title_label.text = world.definition.title
	subtitle_label.text = world.definition.lesson
	chapter_label.text = "TRAINING %02d / 04\nFOUR SPATIAL DIMENSIONS" % (level_index + 1)
	for i in range(LevelWorld.LEVELS.size()):
		level_buttons[i].set_pressed_no_signal(i == level_index)
		level_buttons[i].text = "CHAMBER %02d%s" % [i + 1, "  ✓" if completed[i] else ""]
	for i in range(4):
		mode_buttons[i].disabled = not i in world.definition.modes
		mode_buttons[i].tooltip_text = "This training chamber introduces the highlighted views." if mode_buttons[i].disabled else "Switch views without changing position"
	var stage: int = world.stage
	hint_heading.text = world.definition.captions[stage]
	hint_label.text = world.definition.details[stage] if detailed_hint else world.definition.hints[stage]
	var target: Vector4 = world.definition.route[stage]
	goal_label.text = "NEXT %02d  ·  X %.1f   Y %.1f   Z %.1f   W %.1f   |   PURPLE = OFF-SLICE SIGNPOST" % [stage + 1, target.x, target.y, target.z, target.w]
	help_button.text = "H  Hide hint" if detailed_hint else "H  Show hint"
	shell_button.text = "V  Solid walls" if view.xray else "V  X-ray walls"
	next_button.disabled = not won
	next_button.text = ("Enter  ·  Next chamber" if level_index < LevelWorld.LEVELS.size() - 1 else "Enter  ·  Play again") if won else "Reach the gold exit"
	if won:
		hint_heading.text = "CHAMBER COMPLETE" if level_index < LevelWorld.LEVELS.size() - 1 else "TRAINING COMPLETE"
		hint_label.text = "You found a route through four dimensions. Press Enter for the next chamber." if level_index < LevelWorld.LEVELS.size() - 1 else "You solved four chambers by navigating four dimensions. Choose any chamber to explore another route."
		hint_heading.modulate = CYAN
	status_label.text = "X-RAY VIEW: walls remain solid. V toggles their appearance." if view.xray else "All obstacles are 4D solids. Switching views preserves your position."
	if bump_timer > 0:
		status_label.text = "BLOCKED  ·  Follow the numbered marker, try another view, or press H for a specific hint."
	if not world.motor.error.is_empty(): status_label.text = world.motor.error
