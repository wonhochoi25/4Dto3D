extends SceneTree
const ObjectWorld = preload("res://hybrid/object_world.gd")
var failures := 0
var checks := 0
var captures := ""
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "--captures":
		captures = args[1]
		DirAccess.make_dir_recursive_absolute(captures)
	run.call_deferred()
func run() -> void:
	var w := ObjectWorld.new(3)
	check(not w.is_blocked(w.player_position), "Spawn is clear")
	check(not w.key_motor.blocked(w.key_position, w.obstacles), "Key spawn is clear")
	var narrow := w.key_motor.move(w.KEY_START, Vector4(8, 0, 0, 0), [0], w.obstacles, w.definition.low, w.definition.high)
	check(narrow.x < -0.69, "Key cannot sweep through narrow aperture")
	var wide := w.key_motor.move(Vector4(-2, 0, 0, 3), Vector4(4, 0, 0, 0), [0], w.obstacles, w.definition.low, w.definition.high)
	check(absf(wide.x - 2) < 0.001, "Same key fits wide aperture at W=3")
	var edge := w.key_motor.move(Vector4(-2, 0, 0, 2.1), Vector4(4, 0, 0, 0), [0], w.obstacles, w.definition.low, w.definition.high)
	check(edge.x < -0.69, "Visible wide slice alone is insufficient: full W extent must clear")
	check(w.key_motor.half_size == w.KEY_HALF, "Key size never changes with slice")
	w.set_player(Vector4(-0.85, 0, 0, 0))
	place_key(w, Vector4(0.85, 0, 0.5, 0))
	check(not w.interact(0, Vector3(1, 0, 0.3).normalized()), "Cannot grab key through a solid wall")
	w.reset()
	check(not w.interact(0, Vector3.LEFT), "Grab requires aiming at the key")
	place_key(w, w.PLATE - Vector4(0, 0, 0, 3))
	w.try_activate_plate()
	check(not w.plate_active, "Matching XYZ on wrong W slice cannot activate plate")
	place_key(w, w.PLATE)
	w.holding = true
	w.try_activate_plate()
	check(not w.plate_active, "Held key cannot activate plate")
	w.reset()
	w.set_player(w.PLATE)
	w.try_activate_plate()
	check(not w.plate_active, "Player alone cannot activate plate")
	var gate_hit := w.move_player(w.player_position, Vector3(10, 0, 0), 0)
	check(gate_hit.x < 3, "Exit gate physically blocks player before activation")
	check(not w.reached_goal(w.definition.goal), "Cannot win before plate activation")

	# Approximate placement succeeds even though the full key protrudes beyond
	# the outline; its center, not all its corners, is the intended target.
	for sign_value in [-1.0, 1.0]:
		w.reset()
		var off_center: Vector4 = w.PLATE + w.PLATE_CAPTURE_HALF * (0.95 * sign_value)
		place_key(w, off_center)
		w.holding = true
		w.interact(0, Vector3.RIGHT)
		check(w.plate_active, "Release near capture-volume corner activates plate")
		check(w.key_position == off_center, "Approximate placement does not snap or teleport key")
	for axis in range(4):
		for sign_value in [-1.0, 1.0]:
			w.reset()
			var outside: Vector4 = w.PLATE
			outside[axis] += sign_value * (w.PLATE_CAPTURE_HALF[axis] + 0.01)
			place_key(w, outside)
			w.holding = true
			w.interact(0, Vector3.RIGHT)
			check(not w.plate_active, "Release outside outlined range is rejected on axis %d" % axis)
	w.reset()
	var bounds: Dictionary = w.Bounds4D.bounds(w.collider(w.socket_id))
	check(bounds.low.is_equal_approx(w.PLATE - w.PLATE_CAPTURE_HALF) and bounds.high.is_equal_approx(w.PLATE + w.PLATE_CAPTURE_HALF), "Rendered capture outline matches activation bounds")

	var game = load("res://hybrid/training.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.load_level(3)
	check(game.level_buttons.size() == 4, "Fourth chamber is selectable")
	await capture(game, "01-key-and-narrow-hole")
	var grab := InputEventKey.new()
	grab.physical_keycode = KEY_G
	grab.pressed = true
	game._input(grab)
	check(game.world.holding, "G interaction grabs key under crosshair")
	var offset: Vector4 = game.world.key_position - game.player_position
	walk(game, Vector3(1, 0, 0), 5.0)
	check(game.world.key_position.x < -0.69 and game.player_position.x < -1.69, "Carried key blocks player at narrow hole")
	check((game.world.key_position - game.player_position).is_equal_approx(offset), "Collision preserves tether offset")
	await capture(game, "02-key-blocked")
	game.toggle_perspective()
	var fixed: Vector4 = game.world.key_position
	var player: Vector4 = game.player_position
	game.interact_key()
	game.step_movement(Vector3.ONE, 10.0)
	game.move_player(Vector3.ONE * 10)
	check(game.world.key_position == fixed and game.player_position == player and game.world.holding, "Inspection freezes both bodies and blocks release")
	game.toggle_shell()
	await capture(game, "03-inspection")
	game.set_mode(1)
	check(game.world.key_position == fixed and game.player_position == player, "Dimension switch never moves key or player")
	game.toggle_perspective()
	walk(game, Vector3(1, 0, 0), 3.0)
	check(absf(game.world.key_position.w - 3) < 0.001, "Can carry key along W")
	check(game.view.key_renderer.visible == false, "Key outside X slice is signposted, not rendered as a fake solid")
	await capture(game, "04-carried-in-other-slice")
	game.set_mode(0)
	check(game.view.key_renderer.visible, "Key returns in XYZ slice")
	await capture(game, "05-wide-hole")
	walk(game, Vector3(1, 0, 0), 1.8 - game.world.key_position.x)
	check(game.world.key_position.distance_to(game.world.PLATE) < 0.001, "Carry reaches plate")
	check(not game.world.plate_active, "Plate waits for release")
	await capture(game, "06-ready-to-release")
	game.toggle_perspective()
	game.toggle_shell()
	await capture(game, "06b-inspect-delivery")
	game.toggle_perspective()
	game.interact_key()
	check(game.world.plate_active and not game.world.holding, "Release activates plate")
	check(not game.world.gate_id in game.world.solid_ids, "Gate collider removed after valid placement")
	game.interact_key()
	check(not game.world.holding, "Activated plate secures key; gate stays latched")
	await capture(game, "07-gate-open")
	var hit: Vector4 = game.world.move_player(game.player_position, Vector3(2, 0, 0), 0)
	check(hit.x < 1.25, "Released key remains a solid obstacle")
	# Back off then walk around the key and through the open exit gate.
	game.world.set_player(Vector4(0.8, 0, 0, 3))
	walk(game, Vector3(0, 0, 1), 1.2)
	walk(game, Vector3(1, 0, 0), 4.2)
	walk(game, Vector3(0, 0, -1), 1.2)
	check(game.won, "Fourth chamber is solvable through first-person movement")
	await capture(game, "08-complete")
	game.restart()
	check(not game.world.holding and not game.world.plate_active and game.world.key_position == game.world.KEY_START, "Restart resets key and plate")
	check(game.world.gate_id in game.world.solid_ids, "Restart closes gate")
	game.load_level(0)
	check(game.world.key_id == -1 and not game.interact_button.visible and not game.view.key_renderer.visible, "Earlier chambers contain no leftover object state")
	game.queue_free()
	await process_frame
	print("Key chamber: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func place_key(w: RefCounted, point: Vector4) -> void:
	w.scene.dynamic_matrices[w.key_id] = w.Transform4D.translation(point)
	w.refresh_scene()
func walk(game: Control, direction: Vector3, distance: float) -> void:
	game.view.look_yaw = atan2(-direction.x, -direction.z)
	game.view.look_pitch = 0
	game.view.update_camera()
	var steps := int(ceil(distance / 0.04))
	for frame in range(steps):
		game.step_movement(Vector3.FORWARD, distance / steps / game.SPEED)
		check(not game.world.key_motor.blocked(game.world.key_position, game.world.obstacles), "Key stays clear of solids")
		check(not game.world.is_blocked(game.player_position), "Player stays clear of solids and key")
	game.update_hud()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func capture(game: Control, name: String) -> void:
	game.update_hud()
	check(game.status_label.get_global_rect().end.y <= game.size.y, "HUD fits window")
	check(game.next_button.get_global_rect().end.x <= game.size.x, "Action buttons fit width")
	for frame in range(4): await process_frame
	if captures.is_empty(): return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(captures.path_join(name + ".png")) == OK, "Capture saved")
