extends Node3D
## Draw the current constant-hidden-coordinate section, oriented with gravity down.
const World = preload("res://game/world.gd")
const Frame = preload("res://game/frame.gd")
const COLORS := [Color("63c7ed"), Color("f7bd64"), Color("b39af7"), Color("78ddb6")]
var geometry := Node3D.new()
var objects := Node3D.new()
var camera := Camera3D.new()
var player_marker: MeshInstance3D
var cell_meshes: Dictionary = {}
var yaw := PI
var pitch := 0.0
var survey := false
var built_revision := -1
var built_frame: Array = []
var built_hidden := INF
var roll := 0.0
var last_axes: Array = []
var built_survey := false

func _ready() -> void:
	add_child(geometry); add_child(objects); add_child(camera)
	camera.fov = 78; camera.near = 0.06; camera.far = 150
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR; env.background_color = Color("111c2b")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c5d9f0"); env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env; add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-65, -30, 0); light.light_energy = 1.15
	add_child(light)
	player_marker = mesh_box(objects, Vector3.ZERO, Vector3(0.5, 1.7, 0.5), Color.WHITE)

func material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color; m.roughness = 0.85
	if glow: m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func mesh_box(parent: Node3D, center: Vector3, size: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new(); mesh.size = size
	node.mesh = mesh; node.material_override = material(color, glow)
	node.position = center; parent.add_child(node)
	return node

func box4(world: RefCounted, low: Vector4, high: Vector4, color: Color, glow: bool = false) -> void:
	if not world.visible_box(low, high): return
	var a: Vector3 = world.frame.to_view(low)
	var b: Vector3 = world.frame.to_view(high)
	mesh_box(geometry, (a + b) * 0.5, b - a, color, glow)

func sign_text(text: String, p: Vector3, color: Color, size: int = 30) -> void:
	var label := Label3D.new()
	label.text = text; label.position = p; label.font_size = size
	label.pixel_size = 0.005; label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 5; label.outline_modulate = Color("111c2b")
	geometry.add_child(label)

func line(a: Vector3, b: Vector3, color: Color, width: float = 0.06) -> void:
	var delta := b - a
	var node := mesh_box(geometry, (a + b) * 0.5, Vector3(width, 0.018, delta.length()), color, true)
	if delta.length() > 0.001: node.rotation.y = atan2(delta.x, delta.z)

func rebuild(world: RefCounted) -> void:
	for child in geometry.get_children():
		geometry.remove_child(child); child.queue_free()
	built_revision = world.revision; built_frame = world.frame.axes()
	built_hidden = world.player[world.frame.hidden()]; built_survey = survey
	var accent: Color = COLORS[world.frame.mode]
	for body in world.solids:
		var s: Dictionary = body.source
		if not world.visible_box(s.low, s.high): continue
		if survey and s.role == "shell":
			var upper_face := false
			for axis in range(4):
				if s.low[axis] == world.definition.bounds_high[axis]: upper_face = true
			if upper_face: continue
		var low: Vector3 = world.frame.to_view(s.low)
		var high: Vector3 = world.frame.to_view(s.high)
		var color := Color("c7d2dd")
		if s.role == "shell":
			for axis in range(4):
				if s.high[axis] == world.definition.bounds_low[axis]: color = COLORS[axis].darkened(0.52)
		if s.role == "barrier": color = Color("ad6861")
		if s.role == "steps": color = Color("cba75c")
		mesh_box(geometry, (low + high) * 0.5, high - low, color)
		if s.role == "shell":
			# Every physical lower face has its own axis color. This trim follows
			# the surface when a wall becomes a floor instead of changing its identity.
			var normal_axis := -1
			for axis in range(4):
				if s.high[axis] == world.definition.bounds_low[axis]: normal_axis = axis
			if normal_axis >= 0 and normal_axis != world.frame.gravity:
				var trim_low := low; var trim_high := high
				trim_low.y = world.definition.bounds_low[world.frame.gravity] + 0.08
				trim_high.y = trim_low.y + 0.08
				trim_high.x += 0.018; trim_high.z += 0.018; trim_low.x -= 0.018; trim_low.z -= 0.018
				mesh_box(geometry, (trim_low + trim_high) * 0.5, trim_high - trim_low, COLORS[normal_axis], true)
	var view_low: Vector3 = world.frame.to_view(world.definition.bounds_low)
	var view_high: Vector3 = world.frame.to_view(world.definition.bounds_high)
	for x in range(ceili(view_low.x), floori(view_high.x) + 1):
		for z in range(ceili(view_low.z), floori(view_high.z) + 1):
			mesh_box(geometry, Vector3(x, view_low.y + 0.007, z), Vector3(0.035, 0.008, 0.12), Color("617b8c"))
	for pad in world.definition.pads:
		if not world.frame.mode in pad.modes or not world.visible_box(pad.p - Vector4.ONE * 1.35, pad.p + Vector4.ONE * 1.35): continue
		var p: Vector3 = world.frame.to_view(pad.p) - Vector3.UP * 0.84
		mesh_box(geometry, p, Vector3(2.5, 0.018, 2.5), Color("172938"))
		for side in [-1, 1]:
			line(p + Vector3(side * 1.25, 0.03, -1.25), p + Vector3(side * 1.25, 0.03, 1.25), accent, 0.08)
			line(p + Vector3(-1.25, 0.03, side * 1.25), p + Vector3(1.25, 0.03, side * 1.25), accent, 0.08)
		sign_text("STATION " + pad.id + "\n" + world.mode_names(pad.modes), p + Vector3(0, 2.5, 0), accent)
	for s in world.definition.sockets:
		if not world.visible_box(s.p - Vector4.ONE * 0.65, s.p + Vector4.ONE * 0.65): continue
		var on: bool = world.powered.has(s.id)
		var color := Color("73e4b0") if on else Color("f6ba60")
		var up := Vector4.ZERO; up[s.gravity] = 1.0
		var half := Vector4.ONE * 0.6; half[s.gravity] = 0.35
		box4(world, s.p - up * 0.35 - half, s.p - up * 0.35 + half, Color("1a2936"))
		half = Vector4.ONE * 0.65; half[s.gravity] = 0.03
		box4(world, s.p - half, s.p + half, color, true)
		var label_p: Vector4 = s.p + up * 1.4
		if world.visible_box(label_p - Vector4.ONE * 0.6, label_p + Vector4.ONE * 0.6):
			sign_text(s.label + (" / ONLINE" if on else " / CELL REQUIRED"), world.frame.to_view(label_p), color)
	var goal: Vector4 = world.definition.exit
	var open: bool = world.definition.goal_circuit.is_empty() or world.powered.has(world.definition.goal_circuit)
	var goal_color := Color("73e4b0") if open else Color("b85351")
	# The exit arch is an authored XYZ fixture; it rotates/slices with the world.
	var floor_p := goal - Vector4(0, 0, 0.85, 0)
	for side in [-1, 1]:
		var center := floor_p + Vector4(side * 0.65, 0, 1.5, 0)
		var half := Vector4(0.07, 0.13, 1.5, 0.6)
		box4(world, center - half, center + half, goal_color, true)
	var header := floor_p + Vector4(0, 0, 3, 0)
	box4(world, header - Vector4(0.72, 0.13, 0.07, 0.6), header + Vector4(0.72, 0.13, 0.07, 0.6), goal_color, true)
	var label_p := floor_p + Vector4(0, 0, 3.5, 0)
	if world.visible_box(label_p - Vector4.ONE * 0.6, label_p + Vector4.ONE * 0.6):
		sign_text("EXIT / XYZ", world.frame.to_view(label_p), goal_color)
	for s in world.definition.signs:
		if world.visible_box(s.p - Vector4.ONE * 0.6, s.p + Vector4.ONE * 0.6):
			sign_text(s.text, world.frame.to_view(s.p), accent, 25)
	for c in world.cells:
		if not cell_meshes.has(c.id):
			var root := Node3D.new(); objects.add_child(root)
			mesh_box(root, Vector3.ZERO, Vector3.ONE * 0.68, Color("eea24c"))
			for axis in range(3):
				var size := Vector3.ONE * 0.71; size[axis] = 0.12
				mesh_box(root, Vector3.ZERO, size, Color("fff0c9"), true)
			cell_meshes[c.id] = root

func sync(world: RefCounted) -> void:
	var axes: Array = world.frame.axes()
	if not last_axes.is_empty() and axes != last_axes:
		# Preserve the horizontal component of the old physical look direction.
		var old_forward := forward()
		var physical := Vector4.ZERO
		for i in range(3): physical[last_axes[i]] = old_forward[i]
		var new_forward: Vector3 = world.frame.to_view(physical)
		if Vector2(new_forward.x, new_forward.z).length() > 0.1: yaw = atan2(-new_forward.x, -new_forward.z)
		pitch = 0.0
		if axes[1] != last_axes[1]: roll = 0.22
	last_axes = axes.duplicate()
	if built_revision != world.revision or built_frame != axes or built_hidden != world.player[world.frame.hidden()] or built_survey != survey: rebuild(world)
	for c in world.cells:
		var node: Node3D = cell_meshes[c.id]
		node.visible = world.visible_box(c.p - World.CELL_HALF, c.p + World.CELL_HALF)
		node.position = world.frame.to_view(c.p)
	player_marker.visible = survey
	player_marker.position = world.frame.to_view(world.player)
	if survey:
		var center: Vector3 = (world.frame.to_view(world.definition.bounds_low) + world.frame.to_view(world.definition.bounds_high)) * 0.5
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 27
		camera.position = center + Vector3(0, 28, 12); camera.look_at(center)
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.position = world.frame.to_view(world.player) + Vector3(0, 0.64, 0)
		camera.rotation = Vector3(pitch, yaw, roll)

func _process(dt: float) -> void:
	roll = move_toward(roll, 0, dt * 0.75)

func forward() -> Vector3:
	return Basis.from_euler(Vector3(pitch, yaw, 0)) * Vector3.FORWARD

func movement(local: Vector3) -> Vector3:
	return Basis(Vector3.UP, yaw) * local

func look(relative: Vector2) -> void:
	yaw = wrapf(yaw - relative.x * 0.0022, -PI, PI)
	pitch = clampf(pitch - relative.y * 0.0022, -1.45, 1.45)
