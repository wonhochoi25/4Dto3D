extends PanelContainer
## Optional two-object query. Never changes transforms, physics or recording.
signal highlighted(ids: Array, color: Color)
var session
var toggle: Button
var body: VBoxContainer
var first: OptionButton
var second: OptionButton
var report: Label
var interval_view
var last_result: Dictionary = {}
func _ready():
	add_theme_stylebox_override("panel",preload("res://scripts/sandbox/procedural/procedural_theme.gd").box("192333",12,8,"40516a"))
	var box := VBoxContainer.new()
	add_child(box)
	toggle = Button.new()
	toggle.text = "▶ Collision inspector (4D GJK)"
	toggle.toggle_mode = true
	box.add_child(toggle)
	body = VBoxContainer.new()
	box.add_child(body)
	body.hide()
	toggle.toggled.connect(func(enabled):
		body.visible = enabled
		toggle.text = ("▼" if enabled else "▶")+" Collision inspector (4D GJK)"
		update_query())
	var note := Label.new()
	note.text = "Convex hulls of vertices · detection only · no response"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)
	for i in range(2):
		var picker := OptionButton.new()
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.item_selected.connect(func(_index): update_query())
		body.add_child(picker)
		if i == 0: first = picker
		else: second = picker
	report = Label.new()
	report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(report)
	interval_view = preload("res://scripts/sandbox/procedural/collision_intervals.gd").new()
	body.add_child(interval_view)

func set_objects(names: Dictionary):
	var a := first.get_selected_id()
	var b := second.get_selected_id()
	first.clear()
	second.clear()
	for id in names:
		first.add_item("A: "+names[id],id)
		second.add_item("B: "+names[id],id)
	if names.has(a): first.select(first.get_item_index(a))
	if names.has(b): second.select(second.get_item_index(b))
	elif second.item_count > 1: second.select(1)
	update_query()

func update_query():
	if not is_instance_valid(report): return
	interval_view.show_intervals([])
	interval_view.hide()
	if not toggle.button_pressed:
		highlighted.emit([],Color.TRANSPARENT)
		return
	if first.item_count < 2:
		report.text = "Add two shapes to compare."
		highlighted.emit([],Color.TRANSPARENT)
		return
	var a := first.get_selected_id()
	var b := second.get_selected_id()
	last_result = session.query_collision(a,b)
	var result := last_result
	var color := Color("ffcf83")
	var title := "Indeterminate"
	if result.status == "separated":
		color = Color("6ee7ae")
		title = "Separated"
	elif result.status == "intersecting":
		color = Color("ff8298")
		title = "Intersecting / within tolerance"
	report.add_theme_color_override("font_color",color)
	report.text = "%s · %d iterations\n%s" % [title,result.iterations,result.reason]
	if result.status == "separated":
		report.text += "\nDistance bounds: %.6f – %.6f" % [result.distance_lower,result.distance]
		if result.direction != null:
			var n = result.direction
			report.text += "\nAxis XYZW: (%.3f, %.3f, %.3f, %.3f)" % [n[0],n[1],n[2],n[3]]
			report.text += "\nA [%.5f, %.5f]   B [%.5f, %.5f]\nGap: %.6f · intervals relative to A center" % [result.intervals[0].x,result.intervals[0].y,result.intervals[1].x,result.intervals[1].y,result.gap]
			interval_view.show_intervals(result.intervals)
			interval_view.show()
	report.tooltip_text = "Cyan interval: A. Purple interval: B. These are 1D projections along a 4D separating axis."
	highlighted.emit([a,b] if a != b else [],color)
