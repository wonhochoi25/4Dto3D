extends Control

const TestWorld = preload("res://hybrid/perspective_test/test_room_world.gd")
const Grab = TestWorld.Grab
const SliceView = preload("res://hybrid/imported/scripts/game/slice_view.gd")
const WallGrid = preload("res://hybrid/wall_grid.gdshader")
const HOLD_NAMES := ["Released", "Resize pickup", "Fixed-size carry"]

var world := TestWorld.new()
var view := SliceView.new()
var artifact := SliceView.SolidRenderer.new()
var hud: Label
var hint: Label
var crosshair: Label
var mode := 0
var yaw := -PI / 2.0
var pitch := 0.0
var rendered_coordinate := INF
var rendered_mode := -1
var rendered_placement := false

func _ready() -> void:
	add_child(view)
	view.player.hide()
	view.player_label.hide()
	view.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	view.camera.fov = 80.0
	view.camera.near = 0.025
	view.add_child(artifact)
	build_hud()
	update_view()

func build_hud() -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(20, 20)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.035, 0.065, 0.11, 0.91)
	background.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", background)
	add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	panel.add_child(layout)
	var title := Label.new()
	title.text = "Perspective resize test room"
	title.add_theme_font_size_override("font_size", 24)
	layout.add_child(title)
	var controls := Label.new()
	controls.text = "WASD move  ·  Q/E vertical  ·  Shift precision  ·  Esc free mouse\nG resize pickup/release  ·  T fixed-size pickup/release\n1 XYZ  ·  2 YZW  ·  R reset"
	layout.add_child(controls)
	hud = Label.new()
	layout.add_child(hud)
	hint = Label.new()
	hint.add_theme_color_override("font_color", Color("ffce7a"))
	layout.add_child(hint)
	crosshair = Label.new()
	crosshair.text = "+"
	crosshair.add_theme_font_size_override("font_size", 26)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(crosshair)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _physics_process(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var local := Vector3(
		key_value(KEY_D) - key_value(KEY_A),
		key_value(KEY_E) - key_value(KEY_Q),
		key_value(KEY_S) - key_value(KEY_W))
	var speed := 0.75 if Input.is_physical_key_pressed(KEY_SHIFT) else 2.5
	step(local.limit_length(1.0) * speed * delta, delta)

func step(local_motion: Vector3, delta: float = 1.0 / 60.0) -> void:
	if not local_motion.is_zero_approx():
		world.move_in_slice(Basis(Vector3.UP, yaw) * local_motion, mode)
	world.update_grab(mode, aim(), delta)
	update_view()

static func key_value(key: Key) -> float:
	return float(Input.is_physical_key_pressed(key))

func aim() -> Vector3:
	return -Basis.from_euler(Vector3(pitch, yaw, 0.0)).z

func switch_slice(next_mode: int) -> void:
	if next_mode == mode:
		return
	if world.try_switch_slice(next_mode, aim()):
		mode = next_mode

func reset() -> void:
	world.reset()
	mode = 0
	yaw = -PI / 2.0
	pitch = 0.0
	update_view()

func _input(event: InputEvent) -> void:
	# Handle gameplay before the full-window Control can consume the click.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw = wrapf(yaw - event.relative.x * 0.0025, -PI, PI)
		pitch = clampf(pitch - event.relative.y * 0.0025, -1.5, 1.5)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_1: switch_slice(0)
			KEY_2: switch_slice(1)
			KEY_G: world.interact(Grab.Hold.RESIZE, mode, aim())
			KEY_T: world.interact(Grab.Hold.CARRY, mode, aim())
			KEY_R: reset()
			_: return
	else:
		return
	get_viewport().set_input_as_handled()
	update_view()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if is_node_ready():
			update_hint()

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func update_view() -> void:
	var player := world.player_position
	var hidden: int = TestWorld.MODES[mode].hidden
	var coordinate := player[hidden]
	view.camera.position = TestWorld.to_view(player, mode)
	view.camera.rotation = Vector3(pitch, yaw, 0.0)
	if mode != rendered_mode or coordinate != rendered_coordinate or world.placed != rendered_placement:
		rebuild_room(coordinate)
	var points := world.slice_points(world.object_id, mode, coordinate)
	artifact.visible = points.size() >= 4 and world.object_in_slice(mode)
	if artifact.visible:
		artifact.render({"visible": true, "show_edges": true, "color": Color("ffb75e")}, points)
	var center := world.object_position
	var depth := (TestWorld.to_view(center, mode) - view.camera.position).dot(aim())
	var view_name: String = TestWorld.MODES[mode].name
	var state_name: String = HOLD_NAMES[world.hold]
	if world.hold == Grab.Hold.CARRY and not artifact.visible:
		state_name += " · other slice"
	var depth_readout := " · center depth %.2f" % depth if artifact.visible and depth > 0.0 else ""
	hud.text = "%s · %s = %.2f · %s\nPlayer    X %.2f  Y %.2f  Z %.2f  W %.2f\nArtifact  X %.2f  Y %.2f  Z %.2f  W %.2f\nSize ×%.2f%s" % [
		view_name, TestWorld.AXIS_NAMES[hidden], coordinate, state_name,
		player.x, player.y, player.z, player.w,
		center.x, center.y, center.z, center.w, world.object_scale, depth_readout]
	update_hint()

func update_hint() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		hint.text = "Click the game window to move and look."
	elif not world.message.is_empty():
		hint.text = world.message
	elif world.carry_limited and world.hold == Grab.Hold.CARRY:
		hint.text = "Artifact obstructed. Steer around the wall."
	elif world.player_blocked:
		hint.text = "Movement blocked. Try stepping sideways or backing away."
	elif world.hold == Grab.Hold.RESIZE:
		hint.text = "Aim at near and far walls. Press G to commit the size."
	elif world.hold == Grab.Hold.CARRY and mode == 1:
		hint.text = "Walk to player W = 2.6, then press 1 for XYZ."
	elif world.hold == Grab.Hold.CARRY and absf(world.player_position.w - TestWorld.TARGET.w) > TestWorld.TARGET_HALF.w:
		hint.text = "Press 2 to carry the artifact along W to the placement zone."
	elif world.hold == Grab.Hold.CARRY:
		hint.text = "Guide the artifact's center into the zone and press T to release."
	else:
		hint.text = "Aim at the artifact. G resizes it, T carries it at its current size."

func rebuild_room(coordinate: float) -> void:
	rendered_mode = mode
	rendered_coordinate = coordinate
	rendered_placement = world.placed
	for child in view.geometry.get_children():
		view.geometry.remove_child(child)
		child.queue_free()
	for id in world.solid_ids:
		var points := world.slice_points(id, mode, coordinate)
		if points.is_empty():
			continue
		var renderer := SliceView.SolidRenderer.new()
		view.geometry.add_child(renderer)
		renderer.render({"visible": true, "show_edges": false, "color": Color.WHITE}, points)
		var material := ShaderMaterial.new()
		material.shader = WallGrid
		match world.scene.objects[id].name:
			"Near wall": material.set_shader_parameter("wall_color", Color("4f786a"))
			"Alcove lip": material.set_shader_parameter("wall_color", Color("466284"))
			"W lip": material.set_shader_parameter("wall_color", Color("745589"))
		renderer.surface.material_override = material
	var color := Color("65e4a5") if world.placed else Color("bf93f2")
	view.add_region(world.slice_points(world.goal_id, mode, coordinate), color,
		"PLACED" if world.placed else "PLACEMENT ZONE")
