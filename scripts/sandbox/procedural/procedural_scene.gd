extends Node3D
## One isolated experiment. Stage all objects at t before displaying any of them.
const ProceduralTheme = preload("res://scripts/sandbox/procedural/procedural_theme.gd")
const ObjectModel = preload("res://scripts/sandbox/procedural/object_view_model.gd")
const FaceRenderer = preload("res://scripts/rendering/face_renderer.gd")
const Card = preload("res://scripts/sandbox/procedural/object_card.gd")
const Timeline = preload("res://scripts/sandbox/procedural/timeline.gd")
const Registry = preload("res://scripts/io/shape_catalog.gd")
var cards: Array = []
var list: VBoxContainer
var timeline := Timeline.new()
var count_label: Label
var panel: PanelContainer
var camera: Camera3D
var selected_card = null
const HierarchyRow = preload("res://scripts/sandbox/procedural/hierarchy_row.gd")
var session := preload("res://scripts/core/session_4d.gd").new()
var graph:
	get: return session.scene
var recording:
	get: return session.recording
var pending_seek: Variant:
	get: return session.pending_seek
var by_id: Dictionary = {}
var folded: Dictionary = {}
# Visible entries are automatic group/geometry pairs. Cards lists geometry only.
var pairs: Dictionary = {}
var tree_message: Label
var editor_parking: Control
var tree_rebuild_pending := false
var next_shape_id := 1
var sidebar_scroll: ScrollContainer
var sidebar_box: VBoxContainer

func _ready() -> void:
	timeline.playback = session.playback
	session.state_changed.connect(display_time)
	camera = Camera3D.new()
	camera.set_script(preload("res://scripts/sandbox/fly_camera.gd"))
	camera.far = 10000
	camera.near = 0.01
	add_child(camera)
	camera.current = true
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("101722")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.55
	environment.environment = settings
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -25, 0)
	add_child(light)
	var layer := CanvasLayer.new()
	add_child(layer)
	var ui_theme := ProceduralTheme.create()
	panel = PanelContainer.new()
	panel.theme = ui_theme
	layer.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 32
	panel.offset_right = 650
	panel.offset_top = 20
	panel.offset_bottom = 20
	sidebar_scroll = ScrollContainer.new()
	sidebar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sidebar_scroll.follow_focus = true
	panel.add_child(sidebar_scroll)
	var box := VBoxContainer.new()
	sidebar_box = box
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar_scroll.add_child(box)
	box.minimum_size_changed.connect(func(): fit_sidebar.call_deferred())
	get_viewport().size_changed.connect(func(): fit_sidebar.call_deferred())
	var title := Label.new()
	title.text = "Procedural experiment"
	title.add_theme_font_size_override("font_size", 23)
	box.add_child(title)
	var help := Label.new()
	help.text = "Expressions: t in seconds; rotations in degrees.\nTry rotation XW = 30*t.\nProjection is independent per shape. Apply to commit."
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_color", Color("b7c6d9"))
	box.add_child(help)
	var toolbar := HBoxContainer.new()
	box.add_child(toolbar)
	var selector := OptionButton.new()
	for entry in Registry.ENTRIES: selector.add_item(entry["name"])
	toolbar.add_child(selector)
	var add := Button.new()
	add.text = "Add shape"
	add.pressed.connect(func(): add_shape(selector.selected))
	toolbar.add_child(add)
	var reset_camera := Button.new()
	reset_camera.text = "Reset camera"
	reset_camera.pressed.connect(camera.reset_view)
	toolbar.add_child(reset_camera)
	count_label = Label.new()
	count_label.text = "No shapes yet. Add one to begin."
	box.add_child(count_label)
	var tree_help := Label.new()
	tree_help.text = "Drag onto a shape to parent; onto World to unparent."
	tree_help.add_theme_font_size_override("font_size", 13)
	box.add_child(tree_help)
	tree_message = Label.new()
	tree_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tree_message.add_theme_color_override("font_color", Color("ffcf83"))
	tree_message.hide()
	box.add_child(tree_message)
	editor_parking = Control.new()
	editor_parking.hide()
	layer.add_child(editor_parking)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(list)
	var bottom := PanelContainer.new()
	bottom.theme = ui_theme
	layer.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 16
	bottom.offset_right = -16
	bottom.offset_top = -166
	bottom.offset_bottom = -12
	bottom.add_child(timeline)
	timeline.time_requested.connect(request_time)
	timeline.range_requested.connect(func(from: float, to: float): session.set_range(from, to))
	rebuild_tree.call_deferred()
	var collapse := Button.new()
	collapse.text = "◀"
	layer.add_child(collapse)
	collapse.theme = ui_theme
	collapse.focus_mode = Control.FOCUS_NONE
	collapse.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	collapse.offset_left = 0
	collapse.offset_right = 28
	collapse.offset_top = -45
	collapse.offset_bottom = 45
	collapse.pressed.connect(func(): panel.visible = not panel.visible; collapse.text = "◀" if panel.visible else "▶")

## Every visible shape owns an editable group and a separate geometry leaf.
func add_shape(index: int):
	var model := ObjectModel.new(index)
	model.node_name = "%s #%d" % [model.shape.display_name, next_shape_id]
	next_shape_id += 1
	model.color = Color.from_hsv(fmod(cards.size() * 0.19 + 0.55, 1.0), 0.65, 0.95, 0.22)
	var group_model := ObjectModel.new(-1)
	group_model.node_name = "Group · affects this shape and descendants"
	# Compile before adding nodes so invalid defaults cannot leave half a pair.
	if not model.initialize_defaults(model.defaults.get("geometry", {}), timeline.time):
		show_tree_error("Geometry " + model.error_field + ": " + model.error)
		return null
	if not group_model.initialize_defaults(model.defaults.get("group", {}), timeline.time):
		show_tree_error("Group " + group_model.error_field + ": " + group_model.error)
		return null
	tree_message.hide()
	var group_id := session.add_geometry(model.shape, model.defaults.get("geometry", {}), model.defaults.get("group", {}))
	if group_id == 0:
		show_tree_error(session.error)
		return null
	var id: int = graph.objects[group_id].leaf_id
	model.shape = graph.objects[group_id].geometry
	model.track = graph.objects[group_id].track
	group_model.track = graph.objects[group_id].group
	var renderer := FaceRenderer.new()
	add_child(renderer)
	var editor := TabContainer.new()
	editor.use_hidden_tabs_for_min_size = false
	editor_parking.add_child(editor)
	var card = create_card(model, renderer, id, editor)
	card.name = "Geometry"
	var group_card = create_card(group_model, null, group_id, editor)
	group_card.name = "Group"
	card.set_meta("group_id", group_id)
	pairs[group_id] = {"card": card, "group_card": group_card, "editor": editor}
	cards.append(card)
	select_card(card)
	display_time(timeline.time)
	return card

func create_card(model, renderer, id: int, editor: TabContainer):
	var card := Card.new()
	editor.add_child(card)
	card.setup(model, renderer)
	card.set_meta("node_id", id)
	card.apply_requested.connect(apply_card)
	card.remove_requested.connect(remove_card)
	card.style_changed.connect(func(changed):
		if changed.renderer != null: changed.renderer.update_style(changed.object))
	by_id[id] = card
	return card

func remove_card(card) -> void:
	timeline.pause()
	var group_id: int = card.get_meta("node_id") if card.object.is_group else card.get_meta("group_id")
	var pair: Dictionary = pairs[group_id]
	var geometry = pair.card
	# Promote child pairs with keep-world offsets, then discard this pair's leaf.
	if not session.remove_object(group_id):
		show_tree_error(graph.error)
		return
	var index := cards.find(geometry)
	cards.erase(geometry)
	by_id.erase(group_id)
	by_id.erase(geometry.get_meta("node_id"))
	pairs.erase(group_id)
	folded.erase(group_id)
	geometry.renderer.queue_free()
	pair.editor.get_parent().remove_child(pair.editor)
	pair.editor.queue_free()
	if selected_card == geometry: selected_card = cards[mini(index, cards.size() - 1)] if not cards.is_empty() else null
	queue_tree_rebuild()
	display_time(timeline.time)

func apply_card(card) -> void:
	var trial = card.object.ProjectionTrack.new()
	if not trial.apply_sources(card.draft(), timeline.time):
		card.show_error(trial.error_field, trial.error)
		return
	var id: int = card.get_meta("node_id") if card.object.is_group else card.get_meta("group_id")
	if not session.set_expressions(id, card.object.is_group, card.draft(), card.object.keep_anchor_in_place):
		card.show_error(card.object.track.error_field, session.error)
		return
	card.object.projection_track = trial
	card.clear_errors()
	for key in card.fields: card.fields[key].text = card.object.sources[key]
	display_time(timeline.time)

func evaluate_time(value: float) -> bool:
	if not session.seek(value):
		show_runtime_error()
		return false
	return display_time(timeline.time)

func reset_recording() -> void:
	session.invalidate()

func request_time(value: float) -> void:
	session.request_seek(value)
	show_seek_status()

func _process(_delta: float) -> void:
	if session.pending_seek != null: advance_seek()

func advance_seek() -> void:
	session.advance_seek()
	show_seek_status()

func show_seek_status() -> void:
	if not session.error.is_empty(): show_runtime_error()
	elif session.pending_seek != null:
		timeline.message.text = "Simulating to %.3f s · recorded %.3f s" % [session.pending_seek, recording.time_at(recording.frames.size() - 1)]

func show_runtime_error() -> void:
	timeline.pause()
	timeline.message.text = "Paused: " + session.error
	if by_id.has(graph.error_id):
		var card = by_id[graph.error_id]
		card.show_error(card.object.track.error_field, session.error, true)

## Projection and rendering occur only for a displayed state, never simulation steps.
func display_time(value: float) -> bool:
	var state: Dictionary = session.state
	var projected := {}
	for id in by_id:
		var card = by_id[id]
		if card.object.is_group or not state.has(id): continue
		var points = card.object.project_world(state[id].world, value)
		if points == null:
			timeline.pause()
			card.show_error(card.object.error_field, card.object.error, true)
			return false
		projected[id] = points
	for id in projected:
		var card = by_id[id]
		if card.runtime_error: card.clear_errors()
		card.object.last_points = projected[id]
		card.renderer.render(card.object, projected[id])
		card.renderer.set_selected(card == selected_card)
	timeline.accept(value)
	return true

func deactivate() -> void:
	session.cancel_seek()

## Selection changes only the visible editor; all objects keep rendering and animating.
func select_card(card) -> void:
	selected_card = card
	for item in cards:
		pairs[item.get_meta("group_id")].editor.visible = item == card
		if item.renderer != null: item.renderer.set_selected(item == card)
	if card != null:
		var ancestor: int = graph.entries[card.get_meta("node_id")].parent
		while ancestor != 0:
			folded.erase(ancestor)
			ancestor = graph.entries[ancestor].parent
	queue_tree_rebuild()

func queue_tree_rebuild() -> void:
	if tree_rebuild_pending: return
	tree_rebuild_pending = true
	rebuild_tree.call_deferred()

## Preserve actual editor nodes (including unsaved drafts) while rearranging tree rows.
func rebuild_tree() -> void:
	if not is_inside_tree(): return
	tree_rebuild_pending = false
	for pair in pairs.values():
		if pair.editor.get_parent() != editor_parking: pair.editor.reparent(editor_parking)
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	var world := HierarchyRow.new()
	world.controller = self
	world.text = "World"
	world.alignment = HORIZONTAL_ALIGNMENT_LEFT
	world.pressed.connect(func(): select_card(null))
	list.add_child(world)
	append_children(0, list)
	count_label.text = "%d shapes · select a row to edit" % cards.size()
	fit_sidebar.call_deferred()

func append_children(parent_id: int, container: VBoxContainer) -> void:
	for id in pairs:
		if graph.entries[id].parent != parent_id: continue
		var card = pairs[id].card
		var branch := HBoxContainer.new()
		container.add_child(branch)
		var guide := VSeparator.new()
		guide.custom_minimum_size.x = 12
		branch.add_child(guide)
		var contents := VBoxContainer.new()
		contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		branch.add_child(contents)
		var row := HBoxContainer.new()
		contents.add_child(row)
		var arrow := Button.new()
		arrow.text = "▶" if folded.get(id, false) else "▼"
		arrow.pressed.connect(func(): folded[id] = not folded.get(id, false); queue_tree_rebuild())
		row.add_child(arrow)
		var selector := HierarchyRow.new()
		selector.controller = self
		selector.node_id = id
		selector.text = card.object.node_name
		selector.alignment = HORIZONTAL_ALIGNMENT_LEFT
		selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		selector.toggle_mode = true
		selector.button_pressed = selected_card == card
		selector.pressed.connect(func(): select_card(null if selected_card == card else card))
		row.add_child(selector)
		if selected_card == card:
			build_node_actions(card, contents)
			pairs[id].editor.reparent(contents)
			pairs[id].editor.show()
		if not folded.get(id, false): append_children(id, contents)

func build_node_actions(card, contents: VBoxContainer) -> void:
	var id: int = card.get_meta("group_id")
	var name_field := LineEdit.new()
	name_field.text = card.object.node_name
	name_field.tooltip_text = "Rename node; press Enter to commit"
	name_field.text_submitted.connect(func(value: String):
		if not value.strip_edges().is_empty():
			card.object.node_name = value.strip_edges()
			card.heading.text = card.object.node_name
			queue_tree_rebuild())
	contents.add_child(name_field)
	var actions := HBoxContainer.new()
	contents.add_child(actions)
	var parent_picker := OptionButton.new()
	parent_picker.add_item("Parent: World", 0)
	for candidate in pairs:
		if graph.can_parent(id, candidate): parent_picker.add_item("Parent: " + pairs[candidate].card.object.node_name, candidate)
	parent_picker.select(parent_picker.get_item_index(graph.entries[id].parent))
	parent_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent_picker.item_selected.connect(func(index: int): reparent_node(id, parent_picker.get_item_id(index)))
	actions.add_child(parent_picker)

func reparent_node(id: int, parent: int) -> bool:
	timeline.pause()
	if not session.reparent(id, parent):
		show_tree_error(graph.error)
		queue_tree_rebuild()
		return false
	tree_message.hide()
	folded.erase(parent)
	select_card(pairs[id].card)
	display_time(timeline.time)
	return true

func show_tree_error(text: String) -> void:
	tree_message.text = text
	tree_message.show()

## Select the closest visible projected triangle; GUI-consumed clicks never reach here.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed): return
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED: return
	var origin := camera.project_ray_origin(event.position)
	var direction := camera.project_ray_normal(event.position)
	var closest := INF
	var picked = null
	for card in cards:
		if card.object.is_group or not card.object.visible: continue
		var points: PackedVector3Array = card.object.last_points
		for face in card.object.faces:
			for i in range(1, face.size() - 1):
				var hit = Geometry3D.ray_intersects_triangle(origin, direction, points[int(face[0])], points[int(face[i])], points[int(face[i + 1])])
				if hit != null and origin.distance_to(hit) < closest:
					closest = origin.distance_to(hit)
					picked = card
		# Wire-only custom shapes can be selected near projected edge segments.
		if card.object.faces.is_empty():
			for edge in card.object.shape.edges:
				if camera.is_position_behind(points[edge.x]) or camera.is_position_behind(points[edge.y]): continue
				var a := camera.unproject_position(points[edge.x])
				var b := camera.unproject_position(points[edge.y])
				if Geometry2D.get_closest_point_to_segment(event.position, a, b).distance_to(event.position) < 6:
					var distance := origin.distance_to((points[edge.x] + points[edge.y]) * 0.5)
					if distance < closest:
						closest = distance
						picked = card
	select_card(picked)

## Hug the visible content, scrolling only when it exceeds the available height.
func fit_sidebar() -> void:
	if not is_inside_tree() or not is_instance_valid(sidebar_box): return
	var available := maxf(100.0, get_viewport().get_visible_rect().size.y - 218.0)
	sidebar_scroll.custom_minimum_size.y = minf(sidebar_box.get_combined_minimum_size().y, available)
	panel.size.y = panel.get_combined_minimum_size().y
