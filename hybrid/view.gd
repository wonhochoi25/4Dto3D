extends "res://hybrid/imported/scripts/campaign/level_view.gd"
## Both cameras present the same slice and player; neither owns physics.
var first_person := true
var look_yaw := -PI / 2.0
var look_pitch := 0.0
var eye := Vector3.ZERO

func set_player(point: Vector4) -> void:
	super.set_player(point)
	eye = World.to_view(point, mode)
	player.visible = not first_person
	player_label.visible = not first_person
	update_camera()

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
				child.surface.material_override = grid
