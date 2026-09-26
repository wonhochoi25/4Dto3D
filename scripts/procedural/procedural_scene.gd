extends Node3D
## One isolated experiment. Stage all objects at t before displaying any of them.
const ProceduralTheme = preload("res://scripts/procedural/procedural_theme.gd")
const ObjectModel = preload("res://scripts/procedural/procedural_object.gd")
const FaceRenderer = preload("res://scripts/procedural/face_renderer.gd")
const Card = preload("res://scripts/procedural/object_card.gd")
const Timeline = preload("res://scripts/procedural/timeline.gd")
const Registry = preload("res://scripts/shapes/shape_registry.gd")
var cards: Array = []
var list: VBoxContainer
var timeline := Timeline.new()
var count_label: Label
var panel: PanelContainer
var camera: Camera3D
var selected_card = null
var shape_picker: OptionButton
var next_shape_id := 1
var sidebar_scroll: ScrollContainer
var sidebar_box: VBoxContainer

func _ready() -> void:
	camera = Camera3D.new()
	camera.set_script(preload("res://scripts/fly_camera.gd"))
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
	sidebar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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
	shape_picker = OptionButton.new()
	shape_picker.tooltip_text = "Select the shape whose expressions you want to edit"
	shape_picker.item_selected.connect(func(index: int): select_card(cards[index]))
	box.add_child(shape_picker)
	shape_picker.hide()
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
	timeline.time_requested.connect(evaluate_time)
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

func add_shape(index: int):
	var model := ObjectModel.new(index)
	model.color = Color.from_hsv(fmod(cards.size() * 0.19 + 0.55, 1.0), 0.65, 0.95, 0.22)
	var renderer := FaceRenderer.new()
	add_child(renderer)
	var card := Card.new()
	list.add_child(card)
	card.setup(model, renderer)
	card.apply_requested.connect(apply_card)
	card.remove_requested.connect(remove_card)
	card.style_changed.connect(func(changed): changed.renderer.update_style(changed.object))
	card.set_meta("instance_label", "%s #%d" % [model.shape.display_name, next_shape_id])
	next_shape_id += 1
	cards.append(card)
	refresh_shape_picker()
	select_card(card)
	count_label.text = "%d independent shapes" % cards.size()
	evaluate_time(timeline.time)
	return card

func remove_card(card) -> void:
	var removed_index := cards.find(card)
	var was_selected: bool = selected_card == card
	cards.erase(card)
	card.renderer.queue_free()
	list.remove_child(card)
	card.queue_free()
	refresh_shape_picker()
	if was_selected:
		select_card(cards[mini(removed_index, cards.size() - 1)] if not cards.is_empty() else null)
	elif selected_card != null:
		shape_picker.select(cards.find(selected_card))
	count_label.text = "%d independent shapes" % cards.size()

func apply_card(card) -> void:
	if card.object.apply_sources(card.draft(), timeline.time):
		card.clear_errors()
		for key in card.fields: card.fields[key].text = card.object.sources[key]
		evaluate_time(timeline.time)
	else:
		card.show_error(card.object.error_field, card.object.error)

func evaluate_time(value: float) -> bool:
	var staged := []
	for card in cards:
		var points = card.object.evaluate(value)
		if points == null:
			timeline.pause()
			timeline.accept(timeline.time)
			timeline.message.text = "Paused: %s · %s" % [card.object.shape.display_name, card.object.error]
			card.show_error(card.object.error_field, card.object.error, true)
			return false
		staged.append(points)
	for i in range(cards.size()):
		if cards[i].runtime_error: cards[i].clear_errors()
		cards[i].object.last_points = staged[i]
		cards[i].renderer.render(cards[i].object, staged[i])
	timeline.accept(value)
	return true

func deactivate() -> void:
	timeline.pause()

## Selection changes only the visible editor; all objects keep rendering and animating.
func select_card(card) -> void:
	selected_card = card
	for item in cards: item.visible = item == card
	if card != null: shape_picker.select(cards.find(card))
	fit_sidebar.call_deferred()

func refresh_shape_picker() -> void:
	shape_picker.clear()
	for card in cards: shape_picker.add_item(card.get_meta("instance_label"))
	shape_picker.visible = not cards.is_empty()

## Hug the visible content, scrolling only when it exceeds the available height.
func fit_sidebar() -> void:
	if not is_instance_valid(sidebar_box): return
	var available := maxf(100.0, get_viewport().get_visible_rect().size.y - 218.0)
	sidebar_scroll.custom_minimum_size.y = minf(sidebar_box.get_combined_minimum_size().y, available)
	panel.size.y = panel.get_combined_minimum_size().y
