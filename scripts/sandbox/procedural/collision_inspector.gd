extends PanelContainer
## Optional two-object query. Never changes transforms, physics or recording.
signal highlighted(ids: Array, color: Color)
var session
var toggle: Button
var body: VBoxContainer
var first: OptionButton
var second: OptionButton
var penetration_toggle: CheckBox
var report: Label
var interval_view
var last_result: Dictionary = {}
func _ready():
	add_theme_stylebox_override("panel",preload("res://scripts/sandbox/procedural/procedural_theme.gd").box("192333",12,8,"40516a"))
	var box := VBoxContainer.new()
	add_child(box)
	toggle = Button.new()
	toggle.text = "▶ Collision inspector (4D)"
	toggle.toggle_mode = true
	box.add_child(toggle)
	body = VBoxContainer.new()
	box.add_child(body)
	body.hide()
	toggle.toggled.connect(func(enabled):
		body.visible = enabled
		toggle.text = ("▼" if enabled else "▶")+" Collision inspector (4D)"
		update_query())
	var note := Label.new()
	note.text = "Read-only collision query · no physical response"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)
	for i in range(2):
		var picker := OptionButton.new()
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.item_selected.connect(func(_index): update_query())
		body.add_child(picker)
		if i == 0: first = picker
		else: second = picker
	penetration_toggle = CheckBox.new()
	penetration_toggle.text = "Estimate penetration"
	penetration_toggle.tooltip_text = "Read-only; no objects move. Additional work for overlapping pairs."
	penetration_toggle.toggled.connect(func(_enabled): update_query())
	body.add_child(penetration_toggle)
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
	last_result = session.query_collision(a,b,penetration_toggle.button_pressed)
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
	report.text = "%s\n%s" % [title,result.reason]
	var diagnostics: Dictionary = result.get("diagnostics",{})
	if diagnostics.has("backend"): report.text += "\nBackend: " + str(diagnostics.backend)
	for key in ["detection_iterations","penetration_iterations"]:
		if diagnostics.has(key): report.text += "\n%s: %s" % [key.replace("_"," "),diagnostics[key]]
	if result.status == "separated":
		if result.has("distance"):
			if result.has("distance_lower"):
				report.text += "\nDistance bounds: %.6f – %.6f" % [result.distance_lower,result.distance]
			else: report.text += "\nDistance estimate: %.6f" % result.distance
		if result.has("direction"):
			report.text += "\nAxis XYZW: " + vector_text(result.direction)
		if result.has("intervals"):
			report.text += "\nA [%.5f, %.5f]   B [%.5f, %.5f]" % [result.intervals[0].x,result.intervals[0].y,result.intervals[1].x,result.intervals[1].y]
			if result.has("gap"): report.text += "\nGap: %.6f" % result.gap
			if result.has("interval_origin"): report.text += "\nInterval reference XYZW: " + vector_text(result.interval_origin)
			interval_view.show_intervals(result.intervals)
			interval_view.show()
	if result.has("penetration"):
		var p: Dictionary = result.penetration
		report.text += "\nPenetration: %s\n%s" % [p.status,p.reason]
		if p.get("converged",false):
			if p.has("depth_lower") and p.has("depth_upper"):
				report.text += "\nPenetration depth bounds: %.6f – %.6f" % [p.depth_lower,p.depth_upper]
			elif p.has("depth"): report.text += "\nPenetration depth: %.6f" % p.depth
			if p.has("direction"): report.text += "\nDirection for B, XYZW: " + vector_text(p.direction)
			if p.has("translation_b"):
				report.text += "\nTranslation for B: " + vector_text(p.translation_b)
				report.text += "\nEstimated translation to contact with A fixed. No movement applied."
		else: report.text += "\nDetection result is unchanged; penetration estimate unavailable."
	elif penetration_toggle.button_pressed and result.status == "intersecting":
		report.text += "\nPenetration estimate unavailable from this backend."
	report.tooltip_text = "Cyan interval: A. Purple interval: B. These are 1D projections along a 4D separating axis."
	highlighted.emit([a,b] if a != b else [],color)

func vector_text(v) -> String:
	return "(%.6f, %.6f, %.6f, %.6f)" % [v[0],v[1],v[2],v[3]]
