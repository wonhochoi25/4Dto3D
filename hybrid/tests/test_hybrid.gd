extends SceneTree
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
	var game = load("res://hybrid/training.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	for level in range(3):
		game.load_level(level)
		await capture("%d-first-person" % (level + 1))
		check(not game.inspecting and not game.view.xray, "Starts in solid first-person view")
		check(not game.view.player.visible, "Player cube cannot occlude own eyes")
		check(game.view.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "First-person perspective")
		check(game.camera_button.disabled and game.shell_button.disabled, "Inspection controls disabled in first person")
		var before: Vector4 = game.player_position
		game.step_movement(Vector3(0, 0, -1), 100.0)
		check(game.player_position.x < 1.0, "First-person movement cannot tunnel through first wall")
		game.restart()
		var look := InputEventMouseMotion.new()
		look.relative = Vector2(100, -40)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if DisplayServer.get_name() == "headless": game.view.look(look.relative)
		else: game._input(look)
		var yaw: float = game.view.look_yaw
		var pitch: float = game.view.look_pitch
		check(not is_equal_approx(yaw, -PI / 2), "Captured mouse turns first-person camera")
		game.perspective_button.pressed.emit()
		check(game.inspecting and game.view.player.visible, "Button opens inspection and shows player")
		game.step_movement(Vector3.ONE, 5.0)
		game.move_player(Vector3(5, 0, 0))
		check(game.player_position == before, "Inspection blocks both movement entry points")
		game.set_mode(1)
		game.toggle_shell()
		check(game.player_position == before, "Slice and X-ray toggles never teleport")
		game.toggle_shell()
		game.camera_button.button_pressed = true
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = game.viewport_container.get_global_rect().get_center()
		game._input(press)
		look.button_mask = MOUSE_BUTTON_MASK_LEFT
		var old_orbit: float = game.view.yaw
		game._input(look)
		check(game.view.yaw != old_orbit, "Inspection drag orbits")
		game.camera_button.button_pressed = false
		var locked: Transform3D = game.view.camera.transform
		game._input(look)
		check(game.view.camera.transform.is_equal_approx(locked), "Camera toggle locks inspection angle")
		await capture("%d-inspection" % (level + 1))
		game.perspective_button.pressed.emit()
		check(game.player_position == before and game.mode == 1, "Return preserves location and selected slice")
		check(game.view.look_yaw == yaw and game.view.look_pitch == pitch, "Inspection preserves first-person look")
		check(not game.view.xray, "X-ray cannot leak into walking mode")
		game.toggle_perspective()
		check(game.view.camera.transform.is_equal_approx(locked), "Inspection angle persists across camera switches")
		game.toggle_perspective()
		game.restart()
		for i in range(game.world.definition.route.size()):
			var target: Vector4 = game.world.definition.route[i]
			game.set_mode(game.world.definition.route_modes[i])
			var delta: Vector3 = game.world.to_view(target - game.player_position, game.mode)
			# Face each route segment and walk forward using the same control path as WASD.
			game.view.look_yaw = atan2(-delta.x, -delta.z)
			game.view.look_pitch = 0.0
			game.view.update_camera()
			var steps := int(ceil(delta.length() / 0.04))
			for frame in range(steps):
				var frozen: float = game.player_position[game.world.MODES[game.mode].hidden]
				game.step_movement(Vector3(0, 0, -1), delta.length() / steps / game.SPEED)
				check(not game.world.is_blocked(game.player_position), "Walked route never intersects 4D solids")
				check(is_equal_approx(game.player_position[game.world.MODES[game.mode].hidden], frozen), "Walking preserves hidden axis")
				check(game.view.camera.position.is_equal_approx(game.world.to_view(game.player_position, game.mode)), "Camera follows actual collision-resolved position")
			if i < game.world.definition.route.size() - 1:
				check(game.player_position.distance_to(target) < 0.001, "First-person route reaches bend")
				await capture("%d-bend-%d" % [level + 1, i])
		check(game.won and game.completed[level], "First-person route wins chamber")
		game.update_hud()
		await capture("%d-complete" % (level + 1))
		check(game.status_label.get_global_rect().end.y <= game.size.y, "HUD fits window")
		game.advance_level()
		check(not game.inspecting and not game.won, "Next chamber resets execution mode")
	game.queue_free()
	await process_frame
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Scene exit releases cursor")
	print("Hybrid: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func capture(label: String) -> void:
	for frame in range(4): await process_frame
	if captures.is_empty(): return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "Screenshot saved")
