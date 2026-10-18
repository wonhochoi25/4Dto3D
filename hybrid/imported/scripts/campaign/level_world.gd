extends "res://hybrid/imported/scripts/game/puzzle_world.gd"
## Separate authored campaign; reuses the exact existing core scene/motor API.
const LEVELS = [preload("res://hybrid/imported/levels/training/01_a_different_direction.gd"), preload("res://hybrid/imported/levels/training/02_the_elbow.gd"), preload("res://hybrid/imported/levels/training/03_a_step_back.gd"), preload("res://hybrid/levels/04_the_right_fit.gd")]
var definition: Dictionary
var marker_ids: Array[int] = []
var stage := 0

func _init(index: int = 0) -> void:
	definition = LEVELS[index].build()
	# Parent initialization is intentionally discarded; no original demo data is edited.
	scene = Scene4D.new()
	state = {}
	solid_ids.clear()
	obstacles.clear()
	for solid in definition.solids:
		add_box(solid.tag, solid.min, solid.max)
	for i in range(definition.route.size()):
		var point: Vector4 = definition.route[i]
		marker_ids.append(add_shape("Route %d" % (i + 1), point - Vector4.ONE * 0.35, point + Vector4.ONE * 0.35))
	goal_id = add_shape("Exit", definition.goal - Vector4.ONE * 0.45, definition.goal + Vector4.ONE * 0.45)
	guide_id = marker_ids[0]
	player_id = add_shape("Player", -Vector4.ONE * HALF_SIZE, Vector4.ONE * HALF_SIZE)
	scene.dynamic_matrices[player_id] = Transform4D.translation(definition.start)
	refresh_scene()

func move_player(point: Vector4, delta: Vector3, mode: int) -> Vector4:
	var result := motor.move(point, to_world_delta(delta, mode), MODES[mode].axes, obstacles, definition.low, definition.high)
	set_player(result)
	while stage < definition.route.size() - 1 and (result - definition.route[stage]).length() < 0.65:
		stage += 1
	return result

func reset() -> void:
	stage = 0
	set_player(definition.start)
