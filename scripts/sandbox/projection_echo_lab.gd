extends Node3D
## Isolated visual sandbox: compare a live 4D→3D projection with a preview echo.
const Tesseract = preload("res://scripts/shapes/tesseract.gd")
const Hull = preload("res://scripts/rendering/projected_hull_3d.gd")
const UITheme = preload("res://scripts/sandbox/procedural/procedural_theme.gd")
const Transform4D = preload("res://scripts/core/math/transform_4d.gd")

var shape = Tesseract.new()
var base_rows: Array[Vector4] = [Vector4(1,0,0,0), Vector4(0,1,0,0), Vector4(0,0,1,0)]
var angles := Vector3.ZERO
var preview_delta := 0.35
var preview_rotation_delta := 20.0
var preview_axis := 0
var current_mesh: MeshInstance3D
var echo_mesh: MeshInstance3D
var camera: Camera3D
var matrix_fields: Array[SpinBox] = []
var angle_sliders: Array[HSlider] = []
var status: Label
var material_mode := 0
var left_panel: PanelContainer
var right_panel: PanelContainer
var left_controls: ScrollContainer
var right_controls: ScrollContainer
var material_mode_picker: OptionButton
var blend_row: HBoxContainer
var custom_material_controls: VBoxContainer
var custom_axis_row: HBoxContainer
var show_preview := true
var material_blend := 1.0
var custom_pattern := 0
var custom_coordinates := 1
var custom_axis := 0
var custom_scale := 6.0
var custom_phase := 0.0
var custom_contrast := 0.22
var custom_color_a := Color("18334a")
var custom_color_b := Color("e5b65c")
var custom_roughness := 0.45
var custom_metallic := 0.0
var custom_opacity := 1.0
var custom_emission := 0.0
var shadow_mesh: MeshInstance3D
var preview_shadow_mesh: MeshInstance3D
var material_shader: ShaderMaterial
var custom_transparent_shader: ShaderMaterial

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("101722")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 0.65
	env.environment = e
	add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45,-30,0)
	add_child(light)
	camera = Camera3D.new()
	camera.set_script(preload("res://scripts/sandbox/fly_camera.gd"))
	camera.position = Vector3(8,6,10)
	camera.look_at(Vector3.ZERO)
	add_child(camera)
	camera.current = true
	current_mesh = MeshInstance3D.new()
	echo_mesh = MeshInstance3D.new()
	shadow_mesh = MeshInstance3D.new()
	preview_shadow_mesh = MeshInstance3D.new()
	add_child(current_mesh)
	add_child(echo_mesh)
	add_child(shadow_mesh)
	add_child(preview_shadow_mesh)
	add_floor()
	build_ui()
	refresh()

func add_floor() -> void:
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200,200)
	floor.mesh = plane
	floor.position.y = -2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("354b5d")
	mat.roughness = 0.9
	floor.material_override = mat
	add_child(floor)

func build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	left_panel = PanelContainer.new()
	left_panel.theme = UITheme.create()
	layer.add_child(left_panel)
	left_panel.anchor_left = 0
	left_panel.anchor_right = 0
	left_panel.anchor_top = 0
	left_panel.anchor_bottom = 1
	left_panel.offset_left = 16
	left_panel.offset_right = 600
	left_panel.offset_top = 16
	left_panel.offset_bottom = -16
	var left_column := VBoxContainer.new()
	left_panel.add_child(left_column)
	var left_header := HBoxContainer.new()
	left_column.add_child(left_header)
	var left_title := Label.new()
	left_title.text = "Projection controls"
	left_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_header.add_child(left_title)
	var left_toggle := Button.new()
	left_toggle.text = "◀"
	left_toggle.tooltip_text = "Collapse projection controls"
	left_header.add_child(left_toggle)
	left_controls = ScrollContainer.new()
	left_controls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_column.add_child(left_controls)
	left_toggle.pressed.connect(func():
		var collapsed := left_controls.visible
		left_controls.visible = not collapsed
		left_panel.offset_right = 88 if collapsed else 600
		left_title.visible = not collapsed
		left_toggle.text = "▶" if collapsed else "◀"
		left_toggle.tooltip_text = "Expand projection controls" if collapsed else "Collapse projection controls")
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_controls.add_child(box)
	var help := Label.new()
	help.text = "Cyan = active form · outline + floor trace = preview.\nRMB look · WASD fly · Q/E down/up · Shift faster"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help)
	var row := HBoxContainer.new()
	box.add_child(row)
	var reset := Button.new()
	reset.text = "Reset camera"
	reset.pressed.connect(func():
		camera.position = Vector3(8,6,10)
		camera.look_at(Vector3.ZERO))
	row.add_child(reset)
	var preset := Button.new()
	preset.text = "Reset projection"
	preset.pressed.connect(reset_projection)
	row.add_child(preset)
	var matrix_title := Label.new()
	matrix_title.text = "Active 3×4 projection matrix"
	box.add_child(matrix_title)
	for r in range(3):
		var matrix_row := HBoxContainer.new()
		box.add_child(matrix_row)
		for c in range(4):
			var field := SpinBox.new()
			field.min_value = -5
			field.max_value = 5
			field.step = 0.1
			field.value = base_rows[r][c]
			field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			field.value_changed.connect(func(v):
				base_rows[r][c] = v
				refresh())
			matrix_row.add_child(field)
			matrix_fields.append(field)
	var axis_title := Label.new()
	axis_title.text = "Rotate the 4D object (degrees)"
	box.add_child(axis_title)
	for i in range(3):
		var axis_row := HBoxContainer.new()
		box.add_child(axis_row)
		var label := Label.new()
		label.text = ["X↔W", "Y↔W", "Z↔W"][i]
		label.custom_minimum_size.x = 55
		axis_row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = -180
		slider.max_value = 180
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(func(v): angles[i] = v; refresh())
		axis_row.add_child(slider)
		angle_sliders.append(slider)
	var preview_axis_row := HBoxContainer.new()
	box.add_child(preview_axis_row)
	var preview_axis_label := Label.new()
	preview_axis_label.text = "Preview axis pair"
	preview_axis_row.add_child(preview_axis_label)
	var preview_axis_picker := OptionButton.new()
	preview_axis_picker.add_item("X ↔ W")
	preview_axis_picker.add_item("Y ↔ W")
	preview_axis_picker.add_item("Z ↔ W")
	preview_axis_picker.item_selected.connect(func(index): preview_axis = index; refresh())
	preview_axis_row.add_child(preview_axis_picker)
	var preview_toggle := CheckBox.new()
	preview_toggle.text = "Show proposed projection and floor footprint"
	preview_toggle.button_pressed = show_preview
	preview_toggle.toggled.connect(func(value): show_preview = value; refresh())
	box.add_child(preview_toggle)
	add_slider(box, "Preview W projection contribution", -1.5, 1.5, preview_delta, func(v): preview_delta = v; refresh())
	add_slider(box, "Preview extra rotation (degrees)", -90, 90, preview_rotation_delta, func(v): preview_rotation_delta = v; refresh())
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	build_material_ui(layer)

func build_material_ui(layer: CanvasLayer) -> void:
	right_panel = PanelContainer.new()
	right_panel.theme = UITheme.create()
	layer.add_child(right_panel)
	right_panel.anchor_left = 1
	right_panel.anchor_right = 1
	right_panel.anchor_top = 0
	right_panel.anchor_bottom = 1
	right_panel.offset_left = -420
	right_panel.offset_right = -16
	right_panel.offset_top = 16
	right_panel.offset_bottom = -16
	var column := VBoxContainer.new()
	right_panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "Material lab"
	title.add_theme_font_size_override("font_size",20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var toggle := Button.new()
	toggle.text = "▶"
	toggle.tooltip_text = "Collapse material lab"
	header.add_child(toggle)
	right_controls = ScrollContainer.new()
	right_controls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(right_controls)
	toggle.pressed.connect(func():
		var collapsed := right_controls.visible
		right_controls.visible = not collapsed
		right_panel.offset_left = -80 if collapsed else -420
		title.visible = not collapsed
		toggle.text = "◀" if collapsed else "▶"
		toggle.tooltip_text = "Expand material lab" if collapsed else "Collapse material lab")
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_controls.add_child(body)
	var mode_label := Label.new()
	mode_label.text = "Preview mode"
	body.add_child(mode_label)
	material_mode_picker = OptionButton.new()
	material_mode_picker.add_item("Procedural stone")
	material_mode_picker.add_item("4D stone / crystal blend")
	material_mode_picker.add_item("Procedural crystal")
	material_mode_picker.add_item("4D fiber density")
	material_mode_picker.add_item("Custom procedural material")
	material_mode_picker.select(material_mode)
	material_mode_picker.item_selected.connect(func(index):
		material_mode = index
		update_material_controls()
		refresh())
	body.add_child(material_mode_picker)
	blend_row = HBoxContainer.new()
	body.add_child(blend_row)
	var blend_label := Label.new()
	blend_label.text = "Stone ↔ crystal"
	blend_row.add_child(blend_label)
	var blend_slider := HSlider.new()
	blend_slider.min_value = 0
	blend_slider.max_value = 1
	blend_slider.step = 0.01
	blend_slider.value = material_blend
	blend_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blend_slider.value_changed.connect(func(value): material_blend=value; apply_custom_material_parameters())
	blend_row.add_child(blend_slider)
	custom_material_controls = VBoxContainer.new()
	body.add_child(custom_material_controls)
	var custom_help := Label.new()
	custom_help.text = "Build a pattern by choosing its coordinates, shape, colors, and surface response."
	custom_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	custom_material_controls.add_child(custom_help)
	var coordinates := OptionButton.new()
	coordinates.add_item("Projected 3D coordinates")
	coordinates.add_item("Carried 4D coordinates")
	coordinates.select(custom_coordinates)
	coordinates.item_selected.connect(func(index): custom_coordinates=index; apply_custom_material_parameters())
	add_labeled_control(custom_material_controls,"Pattern coordinates",coordinates)
	var pattern := OptionButton.new()
	pattern.add_item("Noise")
	pattern.add_item("Stripes")
	pattern.add_item("Checker")
	pattern.add_item("Rings")
	pattern.select(custom_pattern)
	pattern.item_selected.connect(func(index):
		custom_pattern=index
		custom_axis_row.visible = index == 1
		apply_custom_material_parameters())
	add_labeled_control(custom_material_controls,"Pattern",pattern)
	custom_axis_row = HBoxContainer.new()
	custom_material_controls.add_child(custom_axis_row)
	var axis_picker := OptionButton.new()
	axis_picker.add_item("X")
	axis_picker.add_item("Y")
	axis_picker.add_item("Z")
	axis_picker.add_item("W")
	axis_picker.select(custom_axis)
	axis_picker.item_selected.connect(func(index): custom_axis=index; apply_custom_material_parameters())
	add_labeled_control(custom_axis_row,"Stripe axis",axis_picker)
	custom_axis_row.visible = custom_pattern == 1
	add_slider(custom_material_controls,"Pattern scale",0.1,24.0,custom_scale,func(value): custom_scale=value; apply_custom_material_parameters())
	add_slider(custom_material_controls,"Pattern phase / offset",-10.0,10.0,custom_phase,func(value): custom_phase=value; apply_custom_material_parameters())
	add_slider(custom_material_controls,"Pattern contrast",0.02,0.49,custom_contrast,func(value): custom_contrast=value; apply_custom_material_parameters())
	add_color_control(custom_material_controls,"Color A",custom_color_a,func(value): custom_color_a=value; apply_custom_material_parameters())
	add_color_control(custom_material_controls,"Color B",custom_color_b,func(value): custom_color_b=value; apply_custom_material_parameters())
	add_slider(custom_material_controls,"Roughness",0.0,1.0,custom_roughness,func(value): custom_roughness=value; apply_custom_material_parameters())
	add_slider(custom_material_controls,"Metallic",0.0,1.0,custom_metallic,func(value): custom_metallic=value; apply_custom_material_parameters())
	add_slider(custom_material_controls,"Opacity",0.05,1.0,custom_opacity,func(value): custom_opacity=value; apply_custom_material_parameters())
	add_slider(custom_material_controls,"Emission",0.0,2.0,custom_emission,func(value): custom_emission=value; apply_custom_material_parameters())
	update_material_controls()

func add_labeled_control(parent: Control, label_text: String, control: Control) -> void:
	var group := VBoxContainer.new()
	parent.add_child(group)
	var label := Label.new()
	label.text = label_text
	group.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_child(control)

func add_color_control(parent: Control, label_text: String, initial: Color, changed: Callable) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var picker := ColorPickerButton.new()
	picker.color = initial
	picker.custom_minimum_size = Vector2(96,36)
	picker.color_changed.connect(changed)
	row.add_child(picker)

func update_material_controls() -> void:
	if is_instance_valid(blend_row): blend_row.visible = material_mode == 1
	if is_instance_valid(custom_material_controls): custom_material_controls.visible = material_mode == 4

func apply_custom_material_parameters() -> void:
	if material_shader == null: return
	material_shader.set_shader_parameter("material_mode",material_mode)
	material_shader.set_shader_parameter("material_blend",material_blend)
	material_shader.set_shader_parameter("custom_pattern",custom_pattern)
	material_shader.set_shader_parameter("custom_coordinates",custom_coordinates)
	material_shader.set_shader_parameter("custom_axis",custom_axis)
	material_shader.set_shader_parameter("custom_scale",custom_scale)
	material_shader.set_shader_parameter("custom_phase",custom_phase)
	material_shader.set_shader_parameter("custom_contrast",custom_contrast)
	material_shader.set_shader_parameter("custom_color_a",custom_color_a)
	material_shader.set_shader_parameter("custom_color_b",custom_color_b)
	material_shader.set_shader_parameter("custom_roughness",custom_roughness)
	material_shader.set_shader_parameter("custom_metallic",custom_metallic)
	material_shader.set_shader_parameter("custom_opacity",custom_opacity)
	material_shader.set_shader_parameter("custom_emission",custom_emission)
	if custom_transparent_shader != null:
		custom_transparent_shader.set_shader_parameter("material_mode",material_mode)
		custom_transparent_shader.set_shader_parameter("material_blend",material_blend)
		custom_transparent_shader.set_shader_parameter("custom_pattern",custom_pattern)
		custom_transparent_shader.set_shader_parameter("custom_coordinates",custom_coordinates)
		custom_transparent_shader.set_shader_parameter("custom_axis",custom_axis)
		custom_transparent_shader.set_shader_parameter("custom_scale",custom_scale)
		custom_transparent_shader.set_shader_parameter("custom_phase",custom_phase)
		custom_transparent_shader.set_shader_parameter("custom_contrast",custom_contrast)
		custom_transparent_shader.set_shader_parameter("custom_color_a",custom_color_a)
		custom_transparent_shader.set_shader_parameter("custom_color_b",custom_color_b)
		custom_transparent_shader.set_shader_parameter("custom_roughness",custom_roughness)
		custom_transparent_shader.set_shader_parameter("custom_metallic",custom_metallic)
		custom_transparent_shader.set_shader_parameter("custom_opacity",custom_opacity)
		custom_transparent_shader.set_shader_parameter("custom_emission",custom_emission)
	if is_instance_valid(current_mesh) and material_shader != null:
		current_mesh.material_override = get_active_material_shader()

func get_active_material_shader() -> ShaderMaterial:
	if material_mode == 4 and custom_opacity < 0.999 and custom_transparent_shader != null:
		return custom_transparent_shader
	return material_shader

func add_slider(parent: Node, label_text: String, min_value: float, max_value: float, initial: float, changed: Callable) -> HSlider:
	var row := VBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = 0.01
	slider.value = initial
	row.add_child(slider)
	slider.value_changed.connect(changed)
	return slider

func reset_projection() -> void:
	base_rows = [Vector4(1,0,0,0), Vector4(0,1,0,0), Vector4(0,0,1,0)]
	angles = Vector3.ZERO
	for i in range(12): matrix_fields[i].value = base_rows[i / 4][i % 4]
	for slider in angle_sliders: slider.value = 0
	refresh()

func rotation4(extra_degrees: float = 0.0, extra_axis: int = 0) -> PackedFloat64Array:
	var transform = Transform4D.new()
	transform.angles[2] = -angles.x
	transform.angles[4] = -angles.y
	transform.angles[5] = -angles.z
	transform.angles[[2,4,5][extra_axis]] -= extra_degrees
	return transform.rotation_matrix()

func project_points(offset: float, extra_degrees: float = 0.0, extra_axis: int = 0) -> PackedVector3Array:
	var rot: PackedFloat64Array = rotation4(extra_degrees, extra_axis)
	var result := PackedVector3Array()
	for p: Vector4 in shape.vertices:
		var q: Vector4 = Transform4D.apply(rot, p, 0.0)
		var projected := Vector3(base_rows[0].dot(q), base_rows[1].dot(q), base_rows[2].dot(q))
		projected[extra_axis] += offset * q.w
		result.append(projected)
	return result

func transformed_vertices(extra_degrees: float = 0.0, extra_axis: int = 0) -> Array[Vector4]:
	var rotation := rotation4(extra_degrees, extra_axis)
	var result: Array[Vector4] = []
	for p: Vector4 in shape.vertices: result.append(Transform4D.apply(rotation, p, 0.0))
	return result

## Effective linear map from original tesseract coordinates to projected XYZ.
func effective_projection_rows() -> Array:
	var rotation := rotation4()
	var rows: Array = []
	for output_axis in range(3):
		var row := Vector4.ZERO
		for source_axis in range(4):
			for rotated_axis in range(4):
				row[source_axis] += base_rows[output_axis][rotated_axis] * rotation[rotated_axis * 5 + source_axis]
		rows.append(row)
	return rows

func determinant3(m: Array) -> float:
	var first := float(m[0][0]) * (float(m[1][1])*float(m[2][2])-float(m[1][2])*float(m[2][1]))
	var second := float(m[0][1]) * (float(m[1][0])*float(m[2][2])-float(m[1][2])*float(m[2][0]))
	var third := float(m[0][2]) * (float(m[1][0])*float(m[2][1])-float(m[1][1])*float(m[2][0]))
	return first - second + third

func solve3(m: Array, rhs: Vector3) -> Vector3:
	var aug := [[float(m[0][0]),float(m[0][1]),float(m[0][2]),rhs.x], [float(m[1][0]),float(m[1][1]),float(m[1][2]),rhs.y], [float(m[2][0]),float(m[2][1]),float(m[2][2]),rhs.z]]
	for col in range(3):
		var pivot := col
		for row in range(col+1,3):
			if absf(aug[row][col]) > absf(aug[pivot][col]): pivot = row
		if absf(aug[pivot][col]) < 1e-9: return Vector3.ZERO
		if pivot != col:
			var temp: Array = aug[col]
			aug[col] = aug[pivot]
			aug[pivot] = temp
		var divisor: float = aug[col][col]
		for j in range(col,4): aug[col][j] /= divisor
		for row in range(3):
			if row == col: continue
			var factor: float = aug[row][col]
			for j in range(col,4): aug[row][j] -= factor * aug[col][j]
	return Vector3(aug[0][3],aug[1][3],aug[2][3])

## Estimate the projected volume density by sampling the fiber line inside the tesseract.
func fiber_density(q: Vector3, rows: Array) -> float:
	var free_axis := -1
	var best_matrix: Array = []
	var best_det := 0.0
	for candidate_free in range(4):
		var cols: Array[int] = []
		for axis in range(4):
			if axis != candidate_free: cols.append(axis)
		var candidate: Array = []
		for r in range(3): candidate.append([rows[r][cols[0]],rows[r][cols[1]],rows[r][cols[2]]])
		var det := absf(determinant3(candidate))
		if det > best_det: best_det=det; free_axis=candidate_free; best_matrix=candidate
	if free_axis < 0 or best_det < 1e-9: return 0.0
	var columns: Array[int] = []
	for axis in range(4):
		if axis != free_axis: columns.append(axis)
	var free_column := Vector3(rows[0][free_axis],rows[1][free_axis],rows[2][free_axis])
	var base_solution := solve3(best_matrix,q)
	var kernel_solution := solve3(best_matrix,-free_column)
	var p0 := Vector4.ZERO
	var kernel := Vector4.ZERO
	kernel[free_axis] = 1.0
	for i in range(3): p0[columns[i]]=base_solution[i]; kernel[columns[i]]=kernel_solution[i]
	var t_min := -INF
	var t_max := INF
	for axis in range(4):
		if absf(kernel[axis]) < 1e-9:
			if absf(p0[axis]) > 1.0: return 0.0
			continue
		var a := (-1.0-p0[axis])/kernel[axis]
		var b := (1.0-p0[axis])/kernel[axis]
		t_min=maxf(t_min,minf(a,b)); t_max=minf(t_max,maxf(a,b))
	if t_max <= t_min: return 0.0
	const SAMPLE_COUNT := 64
	# The free coordinate is the line parameter, so the tesseract bounds its
	# complete possible range to [-1, 1]. Sample that whole fiber interval.
	var step := 2.0/SAMPLE_COUNT
	var inside := 0
	for sample_index in range(SAMPLE_COUNT):
		var p := p0 + kernel*(-1.0+(float(sample_index)+0.5)*step)
		if absf(p.x)<=1.0 and absf(p.y)<=1.0 and absf(p.z)<=1.0 and absf(p.w)<=1.0: inside += 1
	return clampf(float(inside)*step*kernel.length()/4.0,0.0,1.0)

func projected_point(q: Vector4, offset: float = 0.0) -> Vector3:
	return Vector3(base_rows[0].dot(q) + offset * q.w, base_rows[1].dot(q), base_rows[2].dot(q))

func create_surface_shader() -> ShaderMaterial:
	var shader_code := """
shader_type spatial;
render_mode cull_disabled;
uniform int material_mode = 0;
uniform float material_blend = 1.0;
uniform int custom_pattern = 0;
uniform int custom_coordinates = 1;
uniform int custom_axis = 0;
uniform float custom_scale = 6.0;
uniform float custom_phase = 0.0;
uniform float custom_contrast = 0.22;
uniform vec4 custom_color_a = vec4(0.09,0.20,0.29,1.0);
uniform vec4 custom_color_b = vec4(0.90,0.71,0.36,1.0);
uniform float custom_roughness = 0.45;
uniform float custom_metallic = 0.0;
uniform float custom_opacity = 1.0;
uniform float custom_emission = 0.0;
varying vec3 local_pos;
varying vec4 source4;
varying vec2 density_roughness;
float hash3(vec3 p) { p = fract(p * 0.1031); p += dot(p, p.yxz + 33.33); return fract((p.x + p.y) * p.z); }
float noise3(vec3 p) {
 vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(mix(hash3(i),hash3(i+vec3(1,0,0)),f.x),mix(hash3(i+vec3(0,1,0)),hash3(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash3(i+vec3(0,0,1)),hash3(i+vec3(1,0,1)),f.x),mix(hash3(i+vec3(0,1,1)),hash3(i+vec3(1,1,1)),f.x),f.y),f.z);
}
float hash4(vec4 p) { return fract(sin(dot(p,vec4(127.1,311.7,74.7,269.5)))*43758.5453); }
float noise4(vec4 p) {
 vec4 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f); float n=0.0;
 for(int a=0;a<2;a++) for(int b=0;b<2;b++) for(int c=0;c<2;c++) for(int d=0;d<2;d++) {
  vec4 o=vec4(float(a),float(b),float(c),float(d));
  vec4 wt=mix(1.0-f,f,o);
  n+=hash4(i+o)*wt.x*wt.y*wt.z*wt.w;
 }
 return n;
}
void vertex() { local_pos=VERTEX; source4=COLOR*2.0-1.0; density_roughness=UV2; }
void fragment() {
 vec3 stone=vec3(0.28,0.31,0.32); float n=noise3(local_pos*9.0); float fine=noise3(local_pos*38.0);
 if (material_mode==0) {
   float grain=clamp(n*0.65+fine*0.35,0.0,1.0); ALBEDO=mix(stone*0.62,stone*1.35,grain); ROUGHNESS=0.84; METALLIC=0.02;
 } else if (material_mode==1) {
   float broad=noise4(source4*5.0); float grain4=noise4(source4*24.0);
   float stonegrain=clamp(broad*0.7+grain4*0.3,0.0,1.0);
   vec3 stone_albedo=mix(vec3(0.16,0.19,0.20),vec3(0.52,0.54,0.53),stonegrain);
   float facets=noise4(source4*11.0+vec4(4.1,8.2,1.7,3.6));
   float crystalgrain=noise4(source4*31.0+vec4(2.0,5.0,7.0,11.0));
   vec3 crystal_albedo=mix(vec3(0.08,0.34,0.43),vec3(0.52,0.88,0.94),smoothstep(0.22,0.78,facets*0.72+crystalgrain*0.28));
   float through_w=smoothstep(-0.28,0.38,source4.w);
   float blend=through_w*material_blend;
   ALBEDO=mix(stone_albedo,crystal_albedo,blend);
   ROUGHNESS=mix(0.86,0.24,blend); METALLIC=mix(0.02,0.16,blend);
 } else if (material_mode==2) {
   float facets=noise4(source4*10.0+vec4(4.1,8.2,1.7,3.6));
   float veins=noise4(source4*27.0+vec4(2.0,5.0,7.0,11.0));
   float crystal=clamp(facets*0.68+veins*0.32,0.0,1.0);
   ALBEDO=mix(vec3(0.035,0.18,0.24),vec3(0.48,0.88,0.96),smoothstep(0.20,0.76,crystal));
   ROUGHNESS=mix(0.30,0.12,smoothstep(0.35,0.85,crystal)); METALLIC=0.18;
 } else if (material_mode==3) {
   float d=clamp(density_roughness.x,0.0,1.0);
   ALBEDO=mix(vec3(0.08,0.30,0.65),vec3(1.0,0.52,0.12),d); ROUGHNESS=0.55; METALLIC=0.0;
 } else {
   vec4 coords=custom_coordinates==0 ? vec4(local_pos,0.0) : source4;
   float pattern_value=0.0;
   if (custom_pattern==0) {
     pattern_value=custom_coordinates==0 ? noise3(local_pos*custom_scale+vec3(custom_phase)) : noise4(source4*custom_scale+vec4(custom_phase));
   } else if (custom_pattern==1) {
     pattern_value=0.5+0.5*sin(coords[custom_axis]*custom_scale+custom_phase);
   } else if (custom_pattern==2) {
     float cells=floor(coords.x*custom_scale)+floor(coords.y*custom_scale)+floor(coords.z*custom_scale)+floor(coords.w*custom_scale);
     pattern_value=mod(abs(cells),2.0);
   } else {
     pattern_value=0.5+0.5*sin(length(coords)*custom_scale+custom_phase);
   }
   float mask=smoothstep(0.5-custom_contrast,0.5+custom_contrast,pattern_value);
   ALBEDO=mix(custom_color_a.rgb,custom_color_b.rgb,mask);
   ROUGHNESS=custom_roughness; METALLIC=custom_metallic;
   // CUSTOM_ALPHA_OUTPUT
   EMISSION=ALBEDO*custom_emission;
 }
}
"""
	var shader := Shader.new()
	shader.code = shader_code.replace("// CUSTOM_ALPHA_OUTPUT","")
	material_shader = ShaderMaterial.new()
	material_shader.shader = shader
	var transparent_shader := Shader.new()
	transparent_shader.code = shader_code.replace("// CUSTOM_ALPHA_OUTPUT","ALPHA=custom_opacity;")
	custom_transparent_shader = ShaderMaterial.new()
	custom_transparent_shader.shader = transparent_shader
	return material_shader

func render_hull(target: MeshInstance3D, points: PackedVector3Array, color: Color, with_material_data := false) -> void:
	var h: Dictionary = Hull.build(points)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uv2 := PackedVector2Array()
	var colors := PackedColorArray()
	var source4 := transformed_vertices() if with_material_data else []
	var projection_rows := effective_projection_rows() if with_material_data else []
	var density_cache := {}
	for tri in h.triangles:
		for index in [tri[0], tri[2], tri[1]]:
			var v: Vector3 = h.vertices[index]
			verts.append(v)
			var a: Vector3 = h.vertices[tri[0]]
			var b: Vector3 = h.vertices[tri[1]]
			var c: Vector3 = h.vertices[tri[2]]
			norms.append((b-a).cross(c-a).normalized())
			if with_material_data:
				var source_sum := Vector4.ZERO
				var contributor_count := 0
				var nearest := 0
				for j in range(points.size()):
					var dist2 := points[j].distance_squared_to(v)
					if dist2 < points[nearest].distance_squared_to(v): nearest = j
					# Exact projected coincidences preserve all discrete source samples.
					if dist2 < 0.000001:
						source_sum += source4[j]
						contributor_count += 1
				var source_point: Vector4 = source4[nearest] if contributor_count == 0 else source_sum / float(contributor_count)
				colors.append(Color((source_point.x+1.0)*0.5,(source_point.y+1.0)*0.5,(source_point.z+1.0)*0.5,(source_point.w+1.0)*0.5))
				if not density_cache.has(index): density_cache[index] = fiber_density(v, projection_rows)
				uv2.append(Vector2(density_cache[index],0.65))
	var mesh := ArrayMesh.new()
	if not verts.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		if with_material_data:
			arrays[Mesh.ARRAY_COLOR] = colors
			arrays[Mesh.ARRAY_TEX_UV2] = uv2
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	target.mesh = mesh
	if with_material_data:
		if material_shader == null: create_surface_shader()
		apply_custom_material_parameters()
		target.material_override = get_active_material_shader()
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.48
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		if color.a < 1.0:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		target.material_override = mat

func refresh() -> void:
	if not is_instance_valid(current_mesh) or not current_mesh.is_inside_tree(): return
	var points := project_points(0.0)
	if material_mode == 3:
		render_density_hull(current_mesh, points)
	else:
		render_hull(current_mesh, points, Color.WHITE, true)
	apply_custom_material_parameters()
	var proposed := project_points(preview_delta, preview_rotation_delta, preview_axis)
	if show_preview:
		draw_hull_outline(echo_mesh, proposed, Color(0.96,0.48,0.85,0.95), null)
		draw_floor_outline(shadow_mesh, points, Color(0.35,0.82,0.98,0.95))
		draw_floor_outline(preview_shadow_mesh, proposed, Color(0.96,0.48,0.85,0.95))
	else:
		echo_mesh.visible = false
		shadow_mesh.visible = false
		preview_shadow_mesh.visible = false
	var descriptions := ["3D procedural stone · material stays attached to the visible hull.", "4D stone/crystal blend · mix is evaluated from carried 4D coordinates.", "Standalone procedural crystal material.", "Tesseract fiber density · blue marks shorter 4D chords; orange marks longer chords.", "Custom pattern · evaluated from projected 3D or carried 4D coordinates."]
	var axis_names := ["X↔W", "Y↔W", "Z↔W"]
	status.text = descriptions[material_mode] + " Pink outline and floor trace preview %s: Δprojection %.2f, Δrotation %.1f°." % [axis_names[preview_axis], preview_delta, preview_rotation_delta]

## Tessellate the projected hull and interpolate sampled fiber density over its solid surface.
func render_density_hull(target: MeshInstance3D, points: PackedVector3Array) -> void:
	var hull: Dictionary = Hull.build(points)
	var center := Vector3.ZERO
	for point in hull.vertices: center += point
	if not hull.vertices.is_empty(): center /= float(hull.vertices.size())
	var rows := effective_projection_rows()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv2 := PackedVector2Array()
	const SUBDIVISIONS := 8
	for tri in hull.triangles:
		var a: Vector3 = hull.vertices[tri[0]]
		var b: Vector3 = hull.vertices[tri[1]]
		var c: Vector3 = hull.vertices[tri[2]]
		for i in range(SUBDIVISIONS):
			for j in range(SUBDIVISIONS-i):
				var ab := b-a
				var ac := c-a
				var p00 := a+ab*(float(i)/SUBDIVISIONS)+ac*(float(j)/SUBDIVISIONS)
				var p10 := a+ab*(float(i+1)/SUBDIVISIONS)+ac*(float(j)/SUBDIVISIONS)
				var p01 := a+ab*(float(i)/SUBDIVISIONS)+ac*(float(j+1)/SUBDIVISIONS)
				append_density_triangle(vertices,normals,uv2,p00,p10,p01,center,rows)
				if j < SUBDIVISIONS-i-1:
					var p11 := a+ab*(float(i+1)/SUBDIVISIONS)+ac*(float(j+1)/SUBDIVISIONS)
					append_density_triangle(vertices,normals,uv2,p10,p11,p01,center,rows)
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	target.mesh = mesh
	if material_shader == null: create_surface_shader()
	apply_custom_material_parameters()
	target.material_override = get_active_material_shader()
	target.visible = not vertices.is_empty()

func append_density_triangle(vertices: PackedVector3Array, normals: PackedVector3Array, uv2: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3, center: Vector3, rows: Array) -> void:
	var points := [a,b,c]
	var normal := (b-a).cross(c-a).normalized()
	if normal.dot((a+b+c)/3.0-center) < 0.0:
		points = [a,c,b]
		normal = -normal
	for point: Vector3 in points:
		vertices.append(point)
		normals.append(normal)
		# Boundary fibers vanish at the exact hull, so sample slightly into the solid.
		var density := fiber_density(point.lerp(center,0.12),rows)
		uv2.append(Vector2(density,0.65))

func draw_hull_outline(target: MeshInstance3D, points: PackedVector3Array, color: Color, floor_y: Variant) -> void:
	var h: Dictionary = Hull.build(points)
	var lines := PackedVector3Array()
	for edge in h.edges:
		var a: Vector3 = h.vertices[edge[0]]
		var b: Vector3 = h.vertices[edge[1]]
		if floor_y != null:
			a.y = floor_y
			b.y = floor_y
		lines.append_array(PackedVector3Array([a,b]))
	set_line_mesh(target, lines, color)

func draw_floor_outline(target: MeshInstance3D, points: PackedVector3Array, color: Color) -> void:
	var footprint := PackedVector3Array()
	for point in points: footprint.append(Vector3(point.x, -1.975, point.z))
	draw_hull_outline(target, footprint, color, null)

func set_line_mesh(target: MeshInstance3D, points: PackedVector3Array, color: Color) -> void:
	var mesh := ArrayMesh.new()
	if not points.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = points
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	target.mesh = mesh
	target.visible = not points.is_empty()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	target.material_override = material

func deactivate() -> void:
	pass

func activate() -> void:
	pass
