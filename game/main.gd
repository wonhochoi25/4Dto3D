extends Node3D
const World = preload("res://game/world.gd")
const View = preload("res://game/view.gd")
const Frame = preload("res://game/frame.gd")
const Sprint = preload("res://game/sprint.gd")
var sprint := Sprint.new()
var manual_gravity := false
var gravity_button: Button
var world: RefCounted
var view: Node3D
var room := 0
var unlocked := 0
var paused := true
var hint := -1
var elapsed := 0.0
var jump_requested := false
var hud: CanvasLayer
var title: Label
var section: Label
var objective: Label
var prompt: Label
var status: Label
var hint_label: Label
var crosshair: Label
var menu: PanelContainer
var menu_title: Label
var menu_body: Label
var resume_button: Button
var next_button: Button
var chapter_buttons: Array[Button] = []
var flash: ColorRect
var last_revision := -1

func _ready() -> void:
	var save := ConfigFile.new()
	if save.load("user://seam_basis_progress.cfg") == OK: unlocked = clampi(int(save.get_value("campaign", "unlocked", 0)), 0, 2)
	build_ui()
	var args := OS.get_cmdline_user_args()
	var at := args.find("--room")
	var start := 0
	if at >= 0 and at + 1 < args.size(): start = clampi(int(args[at + 1]) - 1, 0, 2)
	load_room(start)

func label(parent: Node, text: String, size: int, color: Color = Color("e9f0f7")) -> Label:
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", size); l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE; parent.add_child(l)
	return l

func button(parent: Node, text: String, action: Callable) -> Button:
	var b := Button.new(); b.focus_mode = Control.FOCUS_NONE; b.text = text; b.custom_minimum_size = Vector2(0, 43)
	b.add_theme_font_size_override("font_size", 18); b.pressed.connect(action); parent.add_child(b)
	return b

func build_ui() -> void:
	hud = CanvasLayer.new(); add_child(hud)
	var root := Control.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); hud.add_child(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := PanelContainer.new(); root.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE); top.offset_left = 24; top.offset_top = 20; top.offset_right = -24
	var style := StyleBoxFlat.new(); style.bg_color = Color(0.035, 0.065, 0.10, 0.94)
	style.content_margin_left = 20; style.content_margin_right = 20; style.content_margin_top = 13; style.content_margin_bottom = 13
	style.corner_radius_bottom_left = 8; style.corner_radius_bottom_right = 8
	top.add_theme_stylebox_override("panel", style)
	var columns := HBoxContainer.new(); top.add_child(columns)
	var left := VBoxContainer.new(); left.size_flags_horizontal = Control.SIZE_EXPAND_FILL; columns.add_child(left)
	title = label(left, "", 23)
	objective = label(left, "", 16, Color("b9c9d8"))
	section = label(columns, "", 20, Color("63c7ed")); section.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var bottom := VBoxContainer.new(); root.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 30; bottom.offset_right = -30; bottom.offset_top = -125; bottom.offset_bottom = -16
	status = label(bottom, "", 17)
	hint_label = label(bottom, "", 17, Color("f7ce85")); hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label(bottom, "WASD  Walk   DOUBLE W  Run   SPACE  Jump   E  Carry / use   1 XYZ / 2 XZW / 3 XYW / 4 YZW", 16, Color("b7c8d7"))
	label(bottom, "TAB  Switch at station   G  Choose gravity   F  Survey   H  Hint   B  Recover   T  Recall cells   R  Restart   ESC  Pause", 15, Color("8dabc0"))
	prompt = label(root, "", 20, Color("fff0c9")); prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER); prompt.offset_left = -350; prompt.offset_right = 350; prompt.offset_top = 38; prompt.offset_bottom = 100
	crosshair = label(root, "+", 25); crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER); crosshair.position -= Vector2(7, 18)
	flash = ColorRect.new(); root.add_child(flash); flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE; flash.color = Color(0.4, 0.7, 1, 0)
	var shade := ColorRect.new(); root.add_child(shade); shade.name = "Shade"
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); shade.color = Color(0.02, 0.04, 0.07, 0.78)
	menu = PanelContainer.new(); root.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu.offset_left = -375; menu.offset_right = 375; menu.offset_top = -345; menu.offset_bottom = 345
	var ms := style.duplicate(); ms.content_margin_left = 32; ms.content_margin_right = 32; ms.content_margin_top = 28; ms.content_margin_bottom = 28
	menu.add_theme_stylebox_override("panel", ms)
	var list := VBoxContainer.new(); list.add_theme_constant_override("separation", 12); menu.add_child(list)
	label(list, "S E A M   /   COORDINATE RESEARCH", 16, Color("63c7ed"))
	menu_title = label(list, "", 28)
	menu_body = label(list, "", 18); menu_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	resume_button = button(list, "Enter chamber", resume)
	next_button = button(list, "Continue", next_room)
	gravity_button = button(list, "", toggle_gravity_policy)
	button(list, "Restart this chamber", func(): load_room(room); resume())
	label(list, "CHAMBER SELECT", 14, Color("8dabc0"))
	for i in range(3):
		var index := i
		chapter_buttons.append(button(list, ["01  The Wall Is a Floor", "02  A Different Depth", "03  Above and Beside"][i], func(): load_room(index)))
	label(list, "No timer pressure. H reveals optional hints.\nProgress saves when you complete a chamber.", 15, Color("8dabc0"))

func load_room(index: int) -> void:
	room = index; hint = -1; elapsed = 0; jump_requested = false; sprint.reset()
	if is_instance_valid(view):
		remove_child(view); view.queue_free()
	world = World.new(room, manual_gravity); view = View.new(); add_child(view)
	last_revision = world.revision; view.sync(world)
	paused = true; update_menu(true); update_hud()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func update_menu(intro: bool = false) -> void:
	menu.visible = paused
	menu.get_parent().get_node("Shade").visible = paused
	menu_title.text = "CHAMBER COMPLETE" if world.won else world.definition.title
	if world.won:
		menu_body.text = world.definition.subtitle + "\n\n%d:%02d   /   %d section changes   /   %d recoveries" % [int(elapsed) / 60, int(elapsed) % 60, world.shifts, world.falls]
		if room == 2: menu_body.text += "\n\nResearch complete. All three chambers are available for replay."
	else:
		menu_body.text = world.definition.brief + "\n\n" + ("Switch systems at stations; walk to change coordinates. Double-tap and hold W to run. G cycles gravity in selectable mode. The gravity button restarts this room for a fair comparison." if intro else "Paused. Resume to keep experimenting.")
	resume_button.visible = not world.won
	resume_button.text = "Enter chamber" if intro else "Resume"
	next_button.visible = world.won and room < 2
	for i in range(3): chapter_buttons[i].disabled = i > unlocked
	gravity_button.text = "Gravity: SELECTABLE / switch to priority (restarts)" if manual_gravity else "Gravity: Z > X > Y > W / try selectable (restarts)"

func toggle_gravity_policy() -> void:
	manual_gravity = not manual_gravity
	load_room(room)

func resume() -> void:
	sprint.reset()
	paused = false; view.survey = false; update_menu()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func next_room() -> void:
	load_room(mini(room + 1, 2))

func save_progress() -> void:
	unlocked = maxi(unlocked, mini(room + 1, 2))
	var save := ConfigFile.new(); save.set_value("campaign", "unlocked", unlocked)
	save.save("user://seam_basis_progress.cfg")

func _physics_process(dt: float) -> void:
	if world == null: return
	if view.last_axes != world.frame.axes():
		view.sync(world); sprint.reset(); jump_requested = false
	if not paused and not view.survey and get_window().has_focus():
		elapsed += dt
		var local := Vector3(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), 0, float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		if not Input.is_physical_key_pressed(KEY_W): sprint.release()
		world.step(view.movement(local), jump_requested, dt, view.forward(), sprint.active)
		jump_requested = false
		if world.won:
			save_progress(); paused = true; sprint.reset(); Input.mouse_mode = Input.MOUSE_MODE_VISIBLE; update_menu()
	if world.revision != last_revision:
		last_revision = world.revision; flash.color = Color(View.COLORS[world.frame.mode], 0.2); sprint.reset()
	flash.color.a = move_toward(flash.color.a, 0, dt * 0.7)
	view.sync(world); update_hud()

func update_hud() -> void:
	title.text = world.definition.title
	var p: Vector4 = world.player
	objective.text = "X %.2f   Y %.2f   Z %.2f   W %.2f   /   %s" % [p.x, p.y, p.z, p.w, "RUNNING" if world.running else ("CELL CARRIED" if not world.held.is_empty() else "WALKING")]
	section.text = world.frame.description()
	section.add_theme_color_override("font_color", View.COLORS[world.frame.mode])
	status.text = world.message
	hint_label.text = "Hint %d/3: " % (hint + 1) + world.definition.hints[hint] if hint >= 0 else ""
	crosshair.visible = not paused and not view.survey
	prompt.visible = not paused
	if view.survey:
		prompt.offset_top = 200; prompt.offset_bottom = 260
		prompt.text = "SURVEY / movement paused\nF  Return to first person"
	else:
		prompt.offset_top = 38; prompt.offset_bottom = 100
		var target: Dictionary = world.focus(view.forward())
		if not target.is_empty(): prompt.text = target.text
		elif not world.nearby_pad().is_empty(): prompt.text = "STATION " + world.nearby_pad().id + " / " + world.mode_names(world.nearby_pad().modes) + "\nTAB / number keys  Switch" + ("   G  Choose down" if manual_gravity else "")
		elif not world.held.is_empty():
			prompt.text = "E  Release cell"
		else: prompt.text = ""

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode == KEY_W and not event.echo:
		if event.pressed and not paused and not view.survey: sprint.press(Time.get_ticks_msec())
		elif not event.pressed: sprint.release()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			if world.won: return
			if paused: resume()
			else:
				paused = true; sprint.reset(); Input.mouse_mode = Input.MOUSE_MODE_VISIBLE; update_menu()
			return
		if paused:
			if event.physical_keycode == KEY_ENTER:
				if world.won and room < 2: next_room()
				elif not world.won: resume()
			return
		match event.physical_keycode:
			KEY_F:
				view.survey = not view.survey; jump_requested = false; sprint.reset()
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if view.survey else Input.MOUSE_MODE_CAPTURED
			KEY_H: hint = mini(hint + 1, 2)
			KEY_R: load_room(room)
			KEY_T: world.recall_cells()
			KEY_B:
				world.respawn(); sprint.reset()
			KEY_G:
				if not view.survey: world.choose_gravity()
			KEY_SPACE:
				if not view.survey: jump_requested = true
			KEY_TAB:
				if not view.survey: world.switch_mode()
			KEY_E:
				if not view.survey: world.interact(view.forward())
			KEY_1, KEY_2, KEY_3, KEY_4:
				if not view.survey: world.switch_mode(event.physical_keycode - KEY_1)
	if event is InputEventMouseMotion and not paused and not view.survey and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		view.look(event.relative)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and world != null and not world.won:
		paused = true; jump_requested = false; sprint.reset(); Input.mouse_mode = Input.MOUSE_MODE_VISIBLE; update_menu()

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
