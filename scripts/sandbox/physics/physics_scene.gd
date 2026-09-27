extends "res://scripts/sandbox/procedural/procedural_scene.gd"
## Translation-only body sandbox. The core owns body settings and recorded motion.
var motion_label: Label
var body_editors := {}
func _init() -> void:
	numeric_mode = true

func _ready() -> void:
	super._ready()
	session.set_range(0,60)
	var controls := HBoxContainer.new()
	sidebar_box.add_child(controls)
	sidebar_box.move_child(controls,2)
	for title in ["Run","Pause","Reset"]:
		var button := Button.new()
		button.text=title
		controls.add_child(button)
		if title=="Run": button.pressed.connect(run_motion)
		elif title=="Pause": button.pressed.connect(session.pause)
		else: button.pressed.connect(reset_motion)
	motion_label=Label.new()
	motion_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	sidebar_box.add_child(motion_label)
	sidebar_box.move_child(motion_label,3)
	var help: Label = sidebar_box.get_child(1)
	help.text="Static stays fixed · Kinematic follows prescribed velocity.\nDynamic integrates velocity. No forces or collision response.\nWorld-parented bodies only. Edits restart the 60-second run."

func add_shape(index: int):
	if session.playback.direction!=0 or session.pending_seek!=null:
		show_tree_error("Pause before adding shapes.")
		return null
	var card = super.add_shape(index)
	if card != null:
		var id: int = card.get_meta("group_id")
		session.configure_body(id,"static",Vector4.ZERO)
	return card

func build_node_actions(card, contents: VBoxContainer) -> void:
	super.build_node_actions(card,contents)
	var id: int = card.get_meta("group_id")
	var config: Dictionary = session.motion_settings.get(id,{"type":"static","velocity":Vector4.ZERO})
	var panel := VBoxContainer.new()
	contents.add_child(panel)
	var title := Label.new()
	title.text="Body motion · starting settings"
	panel.add_child(title)
	var picker := OptionButton.new()
	for value in ["Static","Kinematic","Dynamic"]: picker.add_item(value)
	picker.select(["static","kinematic","dynamic"].find(config.type))
	panel.add_child(picker)
	var fields := []
	var grid := GridContainer.new()
	grid.columns=4
	panel.add_child(grid)
	for axis in ["X","Y","Z","W"]:
		var label := Label.new()
		label.text="Velocity "+axis
		grid.add_child(label)
	for axis in range(4):
		var field := LineEdit.new()
		field.text=str(config.velocity[axis])
		field.custom_minimum_size.x=100
		field.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		grid.add_child(field)
		fields.append(field)
	var update_enabled := func(_index=0):
		for field in fields: field.editable=picker.selected!=0
	picker.item_selected.connect(update_enabled)
	update_enabled.call()
	var apply := Button.new()
	apply.text="Apply body settings (reset run)"
	panel.add_child(apply)
	apply.pressed.connect(func(): apply_body(id,picker,fields))
	body_editors[id]={"picker":picker,"fields":fields}

func apply_body(id: int, picker: OptionButton, fields: Array) -> void:
	if not can_edit(): return
	var velocity := Vector4.ZERO
	for i in range(4):
		var text: String=fields[i].text.strip_edges()
		if not text.is_valid_float() or not is_finite(text.to_float()):
			show_tree_error("Initial velocity must contain four finite numbers.")
			return
		velocity[i]=text.to_float()
	if not session.configure_body(id,["static","kinematic","dynamic"][picker.selected],velocity):
		show_tree_error(session.error)
	else: tree_message.hide()

func can_edit() -> bool:
	if session.playback.direction!=0 or session.pending_seek!=null:
		show_tree_error("Pause before editing body settings or starting transforms.")
		return false
	return true

func apply_card(card) -> void:
	if can_edit(): super.apply_card(card)

func reparent_node(id: int,parent: int) -> bool:
	if not can_edit(): return false
	return super.reparent_node(id,parent)

func remove_card(card) -> void:
	if not can_edit(): return
	var id: int=card.get_meta("node_id") if card.object.is_group else card.get_meta("group_id")
	super.remove_card(card)
	body_editors.erase(id)

func run_motion() -> void:
	# Never silently ignore pending fields, including a draft body type/velocity.
	for pair in pairs.values():
		for card in [pair.card,pair.group_card]:
			for key in card.fields:
				if card.fields[key].text!=str(card.object.sources[key]):
					show_tree_error("Apply pending transform edits before Run.")
					return
	for id in body_editors:
		var editor: Dictionary=body_editors[id]
		if not is_instance_valid(editor.picker): continue
		var config: Dictionary=session.motion_settings[id]
		if ["static","kinematic","dynamic"][editor.picker.selected]!=config.type:
			show_tree_error("Apply pending body settings before Run.")
			return
		for axis in range(4):
			var text: String=editor.fields[axis].text
			if not text.is_valid_float() or not is_equal_approx(text.to_float(),config.velocity[axis]):
				show_tree_error("Apply pending velocity before Run.")
				return
	if not session.start_body_motion(): show_tree_error(session.error)
	else: tree_message.hide()

func reset_motion() -> void:
	session.invalidate()

func _process(delta: float) -> void:
	session.advance(delta)
	if is_instance_valid(motion_label):
		motion_label.text="%s · t = %.3f / 60 s" % ["Running" if session.playback.direction!=0 else "Paused",session.playback.time]
	if not session.error.is_empty(): show_tree_error(session.error)
