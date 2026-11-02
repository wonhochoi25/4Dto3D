extends "res://hybrid/imported/scripts/campaign/level_view.gd"
## Both cameras present the same slice and player; neither owns physics.
var first_person := true
var look_yaw := -PI / 2.0
var look_pitch := 0.0
var eye := Vector3.ZERO
var key_renderer: Node3D
var key_label: Label3D

func set_player(point: Vector4) -> void:
	super.set_player(point)
	eye = World.to_view(point, mode)
	player.visible = not first_person
	player_label.visible = not first_person
	update_camera()
	update_sign_sizes()

func look(relative: Vector2) -> void:
	look_yaw = wrapf(look_yaw - relative.x * 0.0025, -PI, PI)
	look_pitch = clampf(look_pitch - relative.y * 0.0025, -1.5, 1.5)
	update_camera()

func movement(local: Vector3) -> Vector3:
	# Pitch never makes walking climb; Q/E explicitly controls elevation.
	return Basis(Vector3.UP, look_yaw) * local

func update_camera() -> void:
	if first_person:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 80.0
		camera.near = 0.025
		camera.position = eye
		camera.rotation = Vector3(look_pitch, look_yaw, 0)
	else:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		super.update_camera()

func reset_look() -> void:
	look_yaw = -PI / 2.0
	look_pitch = 0.0
	update_camera()

func rebuild(world: RefCounted, point: Vector4, new_mode: int) -> void:
	super.rebuild(world, point, new_mode)
	if first_person:
		# A procedural one-unit grid gives close walls scale and motion cues.
		# It is a material only: no new geometry, collider, or puzzle opening.
		for child in geometry.get_children():
			if child.get_script() == SolidRenderer:
				var grid := ShaderMaterial.new()
				grid.shader = preload("res://hybrid/wall_grid.gdshader")
				if child.get_meta("role", "") == "exit_gate": grid.set_shader_parameter("wall_color", Color("b75454"))
				child.surface.material_override = grid

	if world.key_id >= 0:
		var coordinate: float = point[World.MODES[mode].hidden]
		var plate_points: PackedVector3Array = world.slice_points(world.plate_id, mode, coordinate)
		var color := Color("65e4a5") if world.plate_active else Color("bf93f2")
		if not plate_points.is_empty():
			var plate_renderer := SolidRenderer.new()
			geometry.add_child(plate_renderer)
			plate_renderer.render({"visible": true, "color": color, "show_edges": true}, plate_points)
		var socket: PackedVector3Array = world.slice_points(world.socket_id, mode, coordinate)
		if not socket.is_empty(): add_region(socket, color, "PLATE ACTIVE" if world.plate_active else "DROP KEY HERE")
		else:
			var sign := make_label("PLATE / OTHER SLICE", World.to_view(world.PLATE, mode) + Vector3(0, 0.7, 0), color, 20)
			sign.no_depth_test = true
			geometry.add_child(sign)
		var exit_points: PackedVector3Array = world.slice_points(world.goal_id, mode, coordinate)
		if not exit_points.is_empty(): add_region(exit_points, GOLD, "EXIT" if world.plate_active else "EXIT / LOCKED")
	sync_objects(world, point)

func sync_objects(world: RefCounted, point: Vector4) -> void:
	if key_renderer == null:
		key_renderer = SolidRenderer.new()
		add_child(key_renderer)
		key_label = make_label("KEY", Vector3.ZERO, Color("ffb75e"), 20)
		key_label.no_depth_test = true
		add_child(key_label)
	key_renderer.visible = world.key_id >= 0
	key_label.visible = world.key_id >= 0
	if world.key_id < 0: return
	var points: PackedVector3Array = world.slice_points(world.key_id, mode, point[World.MODES[mode].hidden])
	key_renderer.visible = not points.is_empty()
	if not points.is_empty(): key_renderer.render({"visible": true, "color": Color("ffb75e"), "show_edges": true}, points)
	key_label.text = "KEY / SECURED" if world.plate_active else "KEY / CARRIED" if world.holding else "KEY / G TO GRAB"
	if points.is_empty(): key_label.text += " / OTHER SLICE"
	key_label.modulate = Color("c3a0ff") if points.is_empty() else Color.WHITE
	key_label.position = World.to_view(world.key_position, mode) + Vector3(0, 0.7, 0)
	key_label.visible = not (first_person and (world.holding or world.plate_active))
	update_sign_sizes()

func update_sign_sizes() -> void:
	# Orthographic labels otherwise become enormous when viewed from one unit away.
	var signs: Array = geometry.get_children()
	if key_label != null: signs.append(key_label)
	for sign in signs:
		if sign is Label3D:
			sign.pixel_size = maxf(camera.position.distance_to(sign.position), 0.25) * 0.003 if first_person else 0.014
			sign.outline_size = 2 if first_person else 5
