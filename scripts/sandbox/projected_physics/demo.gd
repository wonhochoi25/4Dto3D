extends Node3D
## Sandbox host for native 3D physics of projected 4D convex solids.
## Does not use or change the independent 4D collision/physics backend.
const Model = preload("res://scripts/sandbox/procedural/object_view_model.gd")
const Card = preload("res://scripts/sandbox/procedural/object_card.gd")
const Body = preload("res://scripts/sandbox/projected_physics/projected_body.gd")
const Catalog = preload("res://scripts/io/shape_catalog.gd")
const UITheme = preload("res://scripts/sandbox/procedural/procedural_theme.gd")
var graph := preload("res://scripts/core/scene/scene_4d.gd").new()
var tree_box: VBoxContainer
var entries: Array = []
var selected := -1
var time := 0.0
var running := true
var active := true
var selector: OptionButton
var editor: VBoxContainer
var status: Label
var panel: PanelContainer
var camera: Camera3D
var ground_visual: MeshInstance3D
var pending: Array[Callable] = []
var view_angles := Vector3.ZERO
var view_sliders: Array[HSlider] = []
var view_matrix := Body.Math4D.identity()
var camera_4d := preload("res://scripts/core/math/camera_projection_4d.gd").new()
var grabber := preload("res://scripts/sandbox/projected_physics/grab_controller.gd").new()
var grab_status: Label
var camera_position_fields: Array[SpinBox] = []
var camera_depth_slider: HSlider
var camera_depth_label: Label
var show_tesseract_cells := false

func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("101722")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.5
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	camera = Camera3D.new()
	camera.set_script(preload("res://scripts/sandbox/fly_camera.gd"))
	add_child(camera)
	reset_camera()
	camera.current = true
	grabber.camera = camera
	add_child(grabber)
	grabber.picked.connect(func(body):
		for i in range(entries.size()):
			if entries[i].body == body: select_shape(i))
	build_floor()
	build_ui()
	add_shape(0, Vector4(-2, 5, 0, 0))
	add_shape(3, Vector4(2, 8, 0, 1))

func reset_camera() -> void:
	camera.position = Vector3(13, 10, 18)
	camera.look_at(Vector3(0, 3, 0))

func build_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	add_child(floor_body)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	# Follow the camera horizontally; the visible edge stays beyond its far plane.
	plane.size = Vector2.ONE * camera.far * 4.0
	mesh.mesh = plane
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground_visual = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("526475")
	material.roughness = 0.9
	mesh.material_override = material
	floor_body.add_child(mesh)
	var collision := CollisionShape3D.new()
	# Infinite half-space below y=0, independent of the visual plane's extent.
	var shape := WorldBoundaryShape3D.new()
	shape.plane = Plane(Vector3.UP, 0.0)
	collision.shape = shape
	floor_body.add_child(collision)

func button(parent: Node, text: String, action: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.pressed.connect(action)
	parent.add_child(result)
	return result

func build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	panel = PanelContainer.new()
	panel.theme = UITheme.create()
	layer.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 20
	panel.offset_right = 640
	panel.offset_top = 16
	panel.offset_bottom = -16
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var title := Label.new()
	title.text = "Projected world · 3D physics"
	title.add_theme_font_size_override("font_size", 23)
	box.add_child(title)
	var help := Label.new()
	help.text = "4D fields author the shape; Godot simulates its 3D pose.\nExpressions use t (seconds); rotations use degrees.\nRMB look · WASD fly · Q/E down/up · Shift faster"
	help.add_theme_font_size_override("font_size", 14)
	box.add_child(help)
	var controls := HBoxContainer.new()
	box.add_child(controls)
	var pause := button(controls, "Pause", func():
		running = not running
		update_suspension())
	pause.pressed.connect(func(): pause.text = "Pause" if running else "Run")
	button(controls, "Reset simulation", func(): pending.append(reset_simulation))
	button(controls, "Reset camera", reset_camera)
	build_grab_controls(box)
	build_view_controls(box)
	build_camera_4d_controls(box)
	var cells_toggle := CheckBox.new()
	cells_toggle.text = "Show projected tesseract boundary cells (visual test)"
	cells_toggle.toggled.connect(func(enabled):
		show_tesseract_cells = enabled
		for entry in entries:
			entry.body.show_boundary_cells = enabled
			entry.body.boundary_cells.set_enabled(enabled))
	box.add_child(cells_toggle)
	var add_row := HBoxContainer.new()
	box.add_child(add_row)
	var catalog := OptionButton.new()
	for entry in Catalog.ENTRIES: catalog.add_item(entry.name)
	catalog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(catalog)
	button(add_row, "Add shape", func(): pending.append(func(): add_shape(catalog.selected, Vector4(0, 6, 0, 0))))
	selector = OptionButton.new()
	selector.item_selected.connect(select_shape)
	# Keep the selector API for callers; the visible selector is now a hierarchy.
	selector.hide()
	box.add_child(selector)
	var hierarchy_hint := Label.new()
	hierarchy_hint.text = "4D hierarchy · drag onto a shape to parent, onto World to unparent.\nReparenting resets affected assemblies to authored poses."
	hierarchy_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hierarchy_hint)
	tree_box = VBoxContainer.new()
	box.add_child(tree_box)
	editor = VBoxContainer.new()
	box.add_child(editor)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	var collapse := button(layer, "◀", func(): panel.visible = not panel.visible)
	collapse.position = Vector2(0, 160)
	collapse.theme = UITheme.create()
	collapse.pressed.connect(func(): collapse.text = "◀" if panel.visible else "▶")

## Three continuous viewing rotations; zero keeps each existing projection unchanged.
## For default XYZ, XW=90 maps W to display X, YW=90 maps W to Y, etc.
func build_view_controls(box: VBoxContainer) -> void:
	var section := VBoxContainer.new()
	box.add_child(section)
	var label := Label.new()
	label.text = "Shared 4D view · mix XYZ with W"
	section.add_child(label)
	for axis in range(3):
		var row := HBoxContainer.new()
		section.add_child(row)
		var name_label := Label.new()
		name_label.text = ["X ↔ W", "Y ↔ W", "Z ↔ W"][axis]
		name_label.custom_minimum_size.x = 70
		row.add_child(name_label)
		var slider := HSlider.new()
		slider.min_value = -180
		slider.max_value = 180
		slider.step = 0.5
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slider)
		var value_label := Label.new()
		value_label.custom_minimum_size.x = 65
		value_label.text = "0°"
		row.add_child(value_label)
		slider.value_changed.connect(func(value):
			view_angles[axis] = value
			value_label.text = "%.1f°" % value
			update_view_matrix())
		view_sliders.append(slider)
	button(section, "Reset view to XYZ", func():
		for slider in view_sliders: slider.value = 0)

func update_view_matrix() -> void:
	grabber.cancel()
	var rotation := Body.Math4D.new()
	rotation.angles[2] = -view_angles.x
	rotation.angles[4] = -view_angles.y
	rotation.angles[5] = -view_angles.z
	view_matrix = rotation.rotation_matrix()
	# Geometry mutation waits until the physics tick, including when paused.
	for entry in entries: entry.body.view_rotation = view_matrix
	sync_camera_position_controls()

func add_shape(index: int, start: Vector4) -> void:
	var model := Model.new(index)
	model.color = Color.from_hsv(fmod(entries.size() * 0.23 + 0.53, 1.0), 0.6, 0.9)
	# Explicit demo defaults: custom geometry loads, its procedural presets do not.
	var id := graph.add_geometry(model.shape, {"position": {"X": start.x, "Y": start.y, "Z": start.z, "W": start.w}}, {}, time)
	model.track = graph.objects[id].track
	model.shape = graph.objects[id].geometry
	var group_model := Model.new(-1)
	group_model.track = graph.objects[id].group
	group_model.node_name = model.node_name + " · Group"
	var body := Body.new()
	body.model = model
	body.graph = graph
	body.node_id = id
	body.view_rotation = view_matrix
	body.show_boundary_cells = show_tesseract_cells
	body.camera_4d = camera_4d
	add_child(body)
	body.update_geometry(time, true)
	var tabs := TabContainer.new()
	editor.add_child(tabs)
	var card := Card.new()
	card.name = "Geometry"
	tabs.add_child(card)
	card.setup(model, body.renderer, true)
	card.set_projection_editable(true)
	card.apply_requested.connect(func(current): pending.append(func(): apply_card(current, body)))
	card.style_changed.connect(func(_current): refresh_styles())
	card.remove_requested.connect(func(_current): pending.append(func(): remove_shape(body)))
	var fixed := CheckBox.new()
	fixed.text = "Fixed assembly in 3D (root setting)"
	fixed.toggled.connect(func(value): pending.append(func(): body.fixed = value; body.refresh_freeze()))
	card.body.add_child(fixed)
	var mass_row := HBoxContainer.new()
	card.body.add_child(mass_row)
	var mass_label := Label.new()
	mass_label.text = "Base mass (kg at size ×1)"
	mass_row.add_child(mass_label)
	var mass_field := SpinBox.new()
	mass_field.min_value = 0.01
	mass_field.max_value = 1000
	mass_field.step = 0.1
	mass_field.value = body.base_mass
	mass_field.value_changed.connect(func(value): pending.append(func():
		if is_instance_valid(body): body.base_mass = value))
	mass_row.add_child(mass_field)
	var group_card := Card.new()
	group_card.name = "Group"
	tabs.add_child(group_card)
	group_card.setup(group_model, body.renderer, true)
	group_card.apply_requested.connect(func(current): pending.append(func(): apply_card(current, body, group_model)))
	group_card.remove_requested.connect(func(_current): pending.append(func(): remove_shape(body)))
	entries.append({"id": id, "body": body, "card": card, "group_card": group_card, "group_model": group_model, "tabs": tabs, "fixed": fixed})
	update_assemblies()
	refresh_selector(entries.size() - 1)
	update_suspension()

func apply_card(card, body, edit_model = null) -> void:
	grabber.cancel()
	if not is_instance_valid(body): return
	if edit_model == null: edit_model = body.model
	if not edit_model.apply_sources(card.draft(), time):
		card.show_error(edit_model.error_field, edit_model.error)
		return
	card.clear_errors()
	for key in card.fields:
		card.fields[key].text = edit_model.sources[key]
	# Applying explicitly places the shape at its authored pose, even if unchanged.
	update_assemblies([root_id(body.node_id)])

func remove_shape(body) -> void:
	grabber.cancel()
	var old_root := root_id(body.node_id)
	if not graph.remove_object(body.node_id, time):
		status.text = graph.error
		return
	for i in range(entries.size()):
		if entries[i].body != body: continue
		entries[i].tabs.queue_free()
		body.set_absorbed(true)
		body.queue_free()
		entries.remove_at(i)
		# Promoted children may now be independent roots.
		update_assemblies([old_root])
		refresh_selector(mini(i, entries.size() - 1))
		return

func root_id(id: int) -> int:
	while graph.entries[id].parent != 0: id = graph.entries[id].parent
	return id

## Composition is wholly 4D. Native rigid bodies only exist at assembly roots.
func update_assemblies(reset_roots: Array = []) -> void:
	for entry in entries:
		entry.body.set_absorbed(root_id(entry.id) != entry.id)
	for entry in entries:
		if entry.body.absorbed: continue
		var members: Array = [entry.body]
		for child in entries:
			if child.id != entry.id and root_id(child.id) == entry.id: members.append(child.body)
		var changed: bool = members != entry.body.members
		entry.body.members = members
		if not entry.body.held:
			entry.body.update_geometry(time, changed or entry.id in reset_roots)
	refresh_styles()

func refresh_styles() -> void:
	var source = entries[selected].body if selected >= 0 and selected < entries.size() else null
	for entry in entries:
		if entry.body.absorbed: continue
		for part in entry.body.parts: part.renderer.update_style(part.source.model)
		entry.body.select_part(source)

func reparent_node(id: int, parent: int) -> void:
	pending.append(func():
		if not graph.can_parent(id, parent): return
		grabber.cancel()
		var old_root := root_id(id)
		if not graph.reparent(id, parent, time):
			status.text = graph.error
			return
		update_assemblies([old_root, root_id(id)])
		refresh_selector(selected))

func refresh_selector(index: int) -> void:
	selector.clear()
	for i in range(entries.size()): selector.add_item("%s #%d" % [entries[i].body.model.node_name, entries[i].id])
	select_shape(index)

func rebuild_tree() -> void:
	for child in tree_box.get_children():
		tree_box.remove_child(child)
		child.queue_free()
	add_tree_row(0, -1, 0)
	add_tree_children(0, 1)

func add_tree_children(parent: int, depth: int) -> void:
	for i in range(entries.size()):
		if graph.entries[entries[i].id].parent != parent: continue
		add_tree_row(entries[i].id, i, depth)
		add_tree_children(entries[i].id, depth + 1)

func add_tree_row(id: int, index: int, depth: int) -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", depth * 20)
	tree_box.add_child(margin)
	var row := preload("res://scripts/sandbox/procedural/hierarchy_row.gd").new()
	row.controller = self
	row.node_id = id
	row.text = "World" if id == 0 else ("▼ " if selected == index else "▶ ") + "%s #%d" % [entries[index].body.model.node_name, id]
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.pressed.connect(func(): select_shape(-1 if selected == index else index))
	margin.add_child(row)

func select_shape(index: int) -> void:
	selected = index
	if index >= 0: selector.select(index)
	for i in range(entries.size()):
		entries[i].tabs.visible = i == index
		entries[i].fixed.disabled = graph.entries[entries[i].id].parent != 0
	refresh_styles()
	rebuild_tree()

func reset_simulation() -> void:
	grabber.cancel()
	time = 0.0
	var roots: Array = []
	for entry in entries:
		entry.body.size_multiplier = 1.0
		roots.append(entry.id)
	update_assemblies(roots)

func update_suspension() -> void:
	for entry in entries:
		entry.body.suspended = not running or not active
		entry.body.refresh_freeze()

func deactivate() -> void:
	grabber.cancel()
	active = false
	update_suspension()

func activate() -> void:
	active = true
	update_suspension()

func _physics_process(delta: float) -> void:
	var commands := pending.duplicate()
	pending.clear()
	for command in commands: command.call()
	if running and active: time += delta
	update_assemblies()
	grabber.physics_tick(delta)
	grab_status.text = grabber.message
	status.text = "t = %.2f s · %d shapes · gravity: −Y\nReset restores authored poses and clears 3D velocities." % [time, entries.size()]
	if selected >= 0 and selected < entries.size():
		var body = entries[selected].body
		for entry in entries:
			if entry.id == root_id(body.node_id):
				body = entry.body
				break
		status.text += "\nLive 3D position: (%.2f, %.2f, %.2f) · size ×%.2f · mass %.2f kg" % [body.position.x, body.position.y, body.position.z, body.size_multiplier, body.mass]
		if not body.error.is_empty(): status.text += "\n" + body.error

func build_grab_controls(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	var mode := OptionButton.new()
	mode.add_item("Drag (constant size)")
	mode.add_item("Perspective grab (resize)")
	mode.select(1)
	mode.item_selected.connect(func(index):
		grabber.cancel()
		grabber.perspective_resize = index == 1)
	row.add_child(mode)
	var automatic := CheckBox.new()
	automatic.text = "Auto distance"
	automatic.tooltip_text = "Aim at a surface; fit the entire held solid before it. Off: use wheel."
	automatic.toggled.connect(func(value): grabber.automatic_distance = value)
	row.add_child(automatic)
	var strength_row := HBoxContainer.new()
	box.add_child(strength_row)
	var strength_label := Label.new()
	strength_label.text = "Grab strength"
	strength_row.add_child(strength_label)
	var strength := HSlider.new()
	strength.min_value = 0.25
	strength.max_value = 4.0
	strength.step = 0.05
	strength.value = 1.0
	strength.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strength_row.add_child(strength)
	var strength_value := Label.new()
	strength_value.text = "1.00×"
	strength_row.add_child(strength_value)
	strength.value_changed.connect(func(value):
		grabber.grab_strength = value
		strength_value.text = "%.2f×" % value)
	grab_status = Label.new()
	grab_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	grab_status.text = grabber.message
	box.add_child(grab_status)

func build_camera_4d_controls(box: VBoxContainer) -> void:
	var mode := OptionButton.new()
	mode.add_item("Linear projection · per-shape matrix")
	mode.add_item("Matrix → 4D camera → 3D")
	mode.tooltip_text = "Optional camera views the matrix output embedded at W=0."
	box.add_child(mode)
	var controls := VBoxContainer.new()
	controls.visible = false
	box.add_child(controls)
	mode.item_selected.connect(func(index):
		grabber.cancel()
		camera_4d.enabled = index == 1
		controls.visible = camera_4d.enabled
		for entry in entries: entry.card.set_projection_editable(true))
	var hint := Label.new()
	hint.text = "Camera position in embedded space · shape lies at W=0
Shared sliders rotate the source before the matrix."
	hint.add_theme_font_size_override("font_size", 14)
	controls.add_child(hint)
	var look := CheckBox.new()
	look.text = "Look at target (on W=0)"
	look.button_pressed = true
	controls.add_child(look)
	look.toggled.connect(func(value):
		grabber.cancel()
		camera_4d.look_at_target = value
		sync_camera_position_controls())
	var target_row := HBoxContainer.new()
	controls.add_child(target_row)
	for axis in range(3):
		var label := Label.new()
		label.text = "Target " + ["X", "Y", "Z"][axis]
		target_row.add_child(label)
		var field := SpinBox.new()
		field.min_value = -100
		field.max_value = 100
		field.step = 0.1
		target_row.add_child(field)
		field.value_changed.connect(func(value):
			grabber.cancel()
			camera_4d.target[axis] = value
			sync_camera_position_controls())
	var row := HBoxContainer.new()
	controls.add_child(row)

	for axis in range(4):
		var label := Label.new()
		label.text = ["X", "Y", "Z", "W"][axis]
		row.add_child(label)
		var field := SpinBox.new()
		field.min_value = -100
		field.max_value = 100
		field.step = 0.1
		field.allow_greater = true
		field.allow_lesser = true
		field.value = camera_4d.position[axis]
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.custom_minimum_size.x = 90
		field.value_changed.connect(func(value):
			grabber.cancel()
			camera_4d.position[axis] = value
			sync_camera_position_controls())
		row.add_child(field)
		camera_position_fields.append(field)
	camera_depth_label = Label.new()
	controls.add_child(camera_depth_label)
	camera_depth_slider = HSlider.new()
	camera_depth_slider.min_value = -30
	camera_depth_slider.max_value = 30
	camera_depth_slider.step = 0.05
	camera_depth_slider.tooltip_text = "Move along the rotated fourth viewing axis, preserving lateral camera position."
	controls.add_child(camera_depth_slider)
	camera_depth_slider.value_changed.connect(func(value):
		grabber.cancel()
		camera_4d.set_viewing_depth(value, view_matrix)
		sync_camera_position_controls())
	sync_camera_position_controls()
	var settings := GridContainer.new()
	settings.columns = 4
	controls.add_child(settings)
	for property in ["focal", "near_depth", "far_depth", "fov_degrees"]:
		var label := Label.new()
		label.text = {"focal": "Focal", "near_depth": "Near", "far_depth": "Far", "fov_degrees": "FOV°"}[property]
		settings.add_child(label)
		var field := SpinBox.new()
		field.min_value = 0.1
		field.max_value = {"focal": 30, "near_depth": 50, "far_depth": 10000, "fov_degrees": 175}[property]
		field.step = 0.1
		field.value = camera_4d.get(property)
		field.value_changed.connect(func(value):
			grabber.cancel()
			camera_4d.set(property, value))
		settings.add_child(field)
	button(controls, "Reset 4D camera position", func():
		grabber.cancel()
		camera_4d.position = camera_4d.target + Vector4(0, 0, 0, -8)
		sync_camera_position_controls())

func _process(_delta: float) -> void:
	if is_instance_valid(ground_visual):
		ground_visual.position = Vector3(camera.position.x, 0, camera.position.z)

## Rotating the view updates this readout without moving the world-space camera.
func sync_camera_position_controls() -> void:
	for axis in range(camera_position_fields.size()):
		camera_position_fields[axis].set_value_no_signal(camera_4d.position[axis])
	if camera_depth_slider == null: return
	var depth: float = camera_4d.viewing_depth(view_matrix)
	camera_depth_slider.set_block_signals(true)
	camera_depth_slider.min_value = minf(-30, depth)
	camera_depth_slider.max_value = -0.05 if camera_4d.look_at_target else maxf(30, depth)
	camera_depth_slider.set_value_no_signal(depth)
	camera_depth_slider.set_block_signals(false)
	camera_depth_label.text = "Viewing depth: %.2f · back ← → forward" % depth
