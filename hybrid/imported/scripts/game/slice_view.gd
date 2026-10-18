extends Node3D
## Only a presentation of the model; none of these meshes are physics bodies.

const World = preload("res://hybrid/imported/scripts/game/puzzle_world.gd")
const SolidRenderer = preload("res://scripts/rendering/solid_hull_renderer.gd")
const Hull = preload("res://scripts/core/geometry/convex_hull_3d.gd")
const CYAN := Color("65e4d5")
const GOLD := Color("ffce7a")
const AXIS_COLORS := [Color("ff8c89"), Color("8de5aa"), Color("79b8ff"), Color("c3a0ff")]

var geometry := Node3D.new()
var player: MeshInstance3D
var player_label: Label3D
var camera := Camera3D.new()
var view_center := Vector3.ZERO
var yaw := -0.95
var pitch := 0.35
var zoom := 9.8
var mode := 0
var visible_solids := 0


func _ready() -> void:
	add_child(geometry)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("0c1523")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a9c7e8")
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	add_child(environment_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -35, 0)
	light.light_color = Color("c9e5ff")
	light.light_energy = 1.5
	add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(25, 125, 0)
	fill.light_color = Color("7c9ee0")
	fill.light_energy = 0.55
	add_child(fill)
	player = make_box(Vector3.ONE * World.HALF_SIZE * 2.0, CYAN, true)
	add_child(player)
	player_label = make_label("YOU", Vector3.ZERO, CYAN, 23)
	player_label.no_depth_test = true
	add_child(player_label)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.05
	camera.far = 100.0
	add_child(camera)
	camera.make_current()
	update_camera()


func rebuild(world: RefCounted, point: Vector4, new_mode: int) -> void:
	mode = new_mode
	for child in geometry.get_children():
		geometry.remove_child(child)
		child.queue_free()
	var hidden: int = World.MODES[mode]["hidden"]
	var coordinate: float = point[hidden]
	var low := World.to_view(World.MIN_CENTER, mode)
	var high := World.to_view(World.MAX_CENTER, mode)
	view_center = (low + high) * 0.5
	visible_solids = 0
	for id in world.solid_ids:
		var points: PackedVector3Array = world.slice_points(id, mode, coordinate)
		if points.is_empty():
			continue
		visible_solids += 1
		var renderer := SolidRenderer.new()
		geometry.add_child(renderer)
		renderer.render({"visible": true, "color": Color("527b9c"), "show_edges": true}, points)
	add_wire_box(view_center, high - low, Color("344e68"))
	add_grid(low, high)
	add_axes(low, high)
	if mode != 0:
		add_region(world.slice_points(world.guide_id, mode, coordinate), CYAN, "W = 3  /  RETURN TO XYZ")
	add_region(world.slice_points(world.goal_id, mode, coordinate), GOLD, "EXIT")
	# This frame outlines the real passage only when the slice cuts its interior.
	if mode == 0 and coordinate > 2.0 and coordinate < 4.0:
		add_wire_box(Vector3.ZERO, Vector3(1.02, 2.01, 2.01), CYAN)
	set_player(point)
	update_camera()


func set_player(point: Vector4) -> void:
	player.position = World.to_view(point, mode)
	player_label.position = player.position + Vector3(0, 0.5, 0)


func add_region(points: PackedVector3Array, color: Color, caption: String) -> void:
	if points.is_empty():
		return
	var hull := Hull.build(points)
	var lines: Array[Vector3] = []
	var low := points[0]
	var high := low
	for point in points:
		low = low.min(point)
		high = high.max(point)
	for edge in hull.edges:
		lines.append(hull.vertices[edge[0]])
		lines.append(hull.vertices[edge[1]])
	if not lines.is_empty():
		add_lines(lines, color)
	var center := (low + high) * 0.5
	var size := high - low
	# Labels and wire beacons are instructional overlays, not solid obstacles.
	var label := make_label(caption, center + Vector3(0, size.y * 0.5 + 0.3, 0), color, 20)
	label.no_depth_test = true
	geometry.add_child(label)


func add_grid(low: Vector3, high: Vector3) -> void:
	var lines: Array[Vector3] = []
	for x in range(int(ceil(low.x)), int(floor(high.x)) + 1):
		lines.append(Vector3(x, low.y, low.z))
		lines.append(Vector3(x, low.y, high.z))
	for z in range(int(ceil(low.z)), int(floor(high.z)) + 1):
		lines.append(Vector3(low.x, low.y, z))
		lines.append(Vector3(high.x, low.y, z))
	add_lines(lines, Color("263b52"))
	geometry.add_child(make_label("SLICE REFERENCE GRID  /  1 UNIT", Vector3((low.x + high.x) * 0.5, low.y - 0.35, high.z), Color("718ba7"), 16))


func add_axes(low: Vector3, high: Vector3) -> void:
	var origin := low + Vector3(0.05, 0.05, 0.05)
	var axes: Array = World.MODES[mode]["axes"]
	for i in range(3):
		var end := origin
		end[i] = high[i] + 0.4
		add_lines([origin, end], AXIS_COLORS[axes[i]])
		geometry.add_child(make_label("+" + World.AXIS_NAMES[axes[i]], end, AXIS_COLORS[axes[i]], 25))


func orbit(relative: Vector2) -> void:
	yaw -= relative.x * 0.007
	pitch = clampf(pitch + relative.y * 0.007, -0.8, 1.2)
	update_camera()


func change_zoom(direction: float) -> void:
	zoom = clampf(zoom + direction * 0.6, 5.0, 16.0)
	update_camera()


func reset_camera() -> void:
	yaw = -0.95
	pitch = 0.35
	zoom = 9.8
	update_camera()


func update_camera() -> void:
	camera.size = zoom
	camera.position = view_center + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * 18.0
	camera.look_at(view_center, Vector3.UP)


func add_wire_box(center: Vector3, size: Vector3, color: Color) -> void:
	var vertices: Array[Vector3] = []
	for i in range(8):
		var corner := center + Vector3(1 if i & 1 else -1, 1 if i & 2 else -1, 1 if i & 4 else -1) * size * 0.5
		for axis in range(3):
			if i & (1 << axis):
				continue
			var other := corner
			other[axis] += size[axis]
			vertices.append(corner)
			vertices.append(other)
	add_lines(vertices, color)


func add_lines(vertices: Array[Vector3], color: Color) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material(color, true))
	for vertex in vertices:
		mesh.surface_add_vertex(vertex)
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	geometry.add_child(instance)


static func material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.8
	if unshaded:
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return result


static func make_box(size: Vector3, color: Color, unshaded: bool = false) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	result.mesh = box
	result.material_override = material(color, unshaded)
	return result


static func make_label(text: String, position3: Vector3, color: Color, font_size: int) -> Label3D:
	var result := Label3D.new()
	result.text = text
	result.position = position3
	result.modulate = color
	result.font_size = font_size
	result.pixel_size = 0.014
	result.outline_size = 5
	result.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	return result
