extends SceneTree
const LevelWorld = preload("res://hybrid/imported/scripts/campaign/level_world.gd")
var failures := 0
var checks := 0
func _initialize() -> void:
	for level in range(3):
		var world := LevelWorld.new(level)
		check(not world.is_blocked(world.definition.start), "Spawn has full player clearance")
		check(not world.is_blocked(world.definition.goal), "Exit has full player clearance")
		for target in world.definition.route:
			check(not world.is_blocked(target), "Every bend accommodates a finite 4D player")
		var q: Vector4 = world.definition.start
		var wall_hit := world.move_player(q, Vector3(100, 0, 0), 0)
		check(wall_hit.x < 1.0, "Long forward move cannot bypass the first obstacle")
		world.reset()
		for i in range(world.definition.route.size()):
			var target: Vector4 = world.definition.route[i]
			var mode: int = world.definition.route_modes[i]
			var hidden: int = world.MODES[mode].hidden
			check(is_equal_approx(q[hidden], target[hidden]), "Solution never moves the frozen coordinate")
			var displacement: Vector3 = world.to_view(target - q, mode)
			var steps := int(ceil(displacement.length() / 0.05))
			for step in range(steps):
				q = world.move_player(q, displacement / steps, mode)
				check(not world.is_blocked(q), "Continuous solution stays outside solids")
			check(q.distance_to(target) < 0.001, "Intended route reaches checkpoint %d in level %d" % [i, level])
		check(world.reached_goal(q), "Full route reaches exit")
		world.reset()
		check(world.stage == 0 and world.player_position == world.definition.start, "Reset clears route progress")
		if level == 1:
			q = Vector4(0, 0, -1.5, 3)
			var blocked := world.move_player(q, Vector3(10, 0, 0), 0)
			check(blocked.x < 1.0, "Second wall cannot be crossed on first gate's W/Z slice")
			blocked = world.move_player(q, Vector3(-3, 0, 0), 1)
			check(blocked.w > 2.3, "Cannot change W before turning along Z at the elbow")
		if level == 2:
			q = Vector4(0, 0, 0, 3)
			var blocked := world.move_player(q, Vector3(0, 0, 3), 0)
			check(blocked.z < 0.61, "Cannot skip the negative-X detour and move straight along Z")
			blocked = world.move_player(q, Vector3(4, 0, 0), 0)
			check(blocked.x < 0.61, "Positive X is blocked before going around the core")
		print("Chamber %d: %d convex solids; route and shortcut checks complete" % [level + 1, world.solid_ids.size()])
	print("Campaign geometry: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
