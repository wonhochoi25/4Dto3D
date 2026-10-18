extends "res://hybrid/imported/scripts/campaign/controller.gd"
## First-person execution + third-person inspection share one 4D world.
var inspecting := false
var inspection_xray := true
var perspective_button: Button
var camera_help: Label
var crosshair: Label

func build_ui() -> void:
	super.build_ui()
	perspective_button = make_button("F  Inspect in third person")
	perspective_button.pressed.connect(toggle_perspective)
	var side := camera_button.get_parent()
	side.add_child(perspective_button)
	side.move_child(perspective_button, camera_button.get_index())
	for item in find_children("*", "Label", true, false):
		if item.text.begins_with("Enable camera rotation"):
			camera_help = item
	crosshair = label("+", 24, CYAN)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-7, -17)
	# Overlay is a sibling so SubViewportContainer does not scale its input/text.
	viewport_container.add_child(crosshair)

func load_level(index: int) -> void:
	inspecting = false
	inspection_xray = true
	super.load_level(index)
	view.first_person = true
	view.xray = false
	view.reset_look()
	view.rebuild(world, player_position, mode)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	update_hud()

func toggle_perspective() -> void:
	inspecting = not inspecting
	orbiting = false
	view.first_person = not inspecting
	view.xray = inspecting and inspection_xray
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if inspecting else Input.MOUSE_MODE_CAPTURED
	view.rebuild(world, player_position, mode)
	update_hud()

func toggle_shell() -> void:
	if not inspecting: return
	inspection_xray = not inspection_xray
	view.xray = inspection_xray
	view.rebuild(world, player_position, mode)
	update_hud()

func move_player(delta: Vector3) -> void:
	if inspecting: return
	super.move_player(delta)

func step_movement(local: Vector3, seconds: float, precision: bool = false) -> void:
	if inspecting or won: return
	move_player(view.movement(local.limit_length(1.0)) * SPEED * (0.3 if precision else 1.0) * seconds)

func _physics_process(delta: float) -> void:
	if not get_window().has_focus():
		orbiting = false
		return
	bump_timer = maxf(0.0, bump_timer - delta)
	if not inspecting and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if not won: elapsed += delta
		step_movement(Vector3(Input.get_axis("move_left", "move_right"), Input.get_axis("move_down", "move_up"), Input.get_axis("move_forward", "move_back")), delta, Input.is_action_pressed("move_slow"))
	update_hud()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F: toggle_perspective(); return
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				orbiting = false
				update_hud()
				return
			KEY_C:
				if inspecting: view.reset_camera()
				else: view.reset_look()
				return
	if not inspecting:
		if event is InputEventMouseMotion:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED: view.look(event.relative)
			return
		if event is InputEventMouseButton:
			if event.pressed and event.button_index == MOUSE_BUTTON_LEFT and viewport_container.get_global_rect().has_point(event.position):
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				update_hud()
			return
	super._input(event)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		orbiting = false

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func update_hud() -> void:
	super.update_hud()
	if perspective_button == null: return
	perspective_button.text = "F  Return to first person" if inspecting else "F  Inspect in third person"
	camera_button.disabled = not inspecting
	shell_button.disabled = not inspecting
	crosshair.visible = not inspecting
	if inspecting:
		controls_label.text = "INSPECTION · movement paused\n1 / 2 / 3   Change slice\nH   Hint   ·   V   X-ray\nF   Return to first person"
		camera_help.text = "Enable rotation, then drag\nScroll  Zoom   ·   C  Reset camera"
		status_label.text = "INSPECTION · Your 4D position is frozen. F returns to first person."
	else:
		controls_label.text = "WASD   Move relative to look\nQ / E    Down / Up\nMouse  Look   ·   Shift  Precision\nF  Inspect   ·   Esc  Free cursor"
		camera_help.text = "Click scene to look and move\nEsc  Free cursor   ·   C  Reset look"
		status_label.text = "FIRST PERSON · Click inside the scene to look and move. F opens inspection." if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED else "FIRST PERSON · Mouse looks; WASD moves. F inspects; Esc releases the cursor."
	if detailed_hint and not won:
		var target: Vector4 = world.definition.route[world.stage]
		var suggested: int = world.definition.route_modes[world.stage]
		hint_label.text = "Use %s (key %d). In FIRST PERSON move toward X %.1f, Y %.1f, Z %.1f, W %.1f. WASD follows your look; F switches between walking and inspection." % [World.MODES[suggested].name, suggested + 1, target.x, target.y, target.z, target.w]
	if not inspecting:
		var forward: Vector3 = view.movement(Vector3.FORWARD)
		var axes: Array = World.MODES[mode].axes
		mode_label.text += "  ·  LOOK: %s %.2f / %s %.2f" % [World.AXIS_NAMES[axes[0]], forward.x, World.AXIS_NAMES[axes[2]], forward.z]

	if bump_timer > 0: status_label.text += "  BLOCKED by a 4D solid or room boundary."
