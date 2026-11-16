extends SceneTree
const Game = preload("res://game/main.tscn")
var failures := 0
var checks := 0
func _initialize() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1440, 900)
	call_deferred("run")
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ", text)
func capture(name: String) -> void:
	await process_frame; await process_frame
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw()
		get_root().get_texture().get_image().save_png("/tmp/seam-basis-" + name + ".png")
func key(code: int, pressed: bool = true) -> void:
	var event := InputEventKey.new(); event.physical_keycode = code; event.pressed = pressed
	Input.parse_input_event(event)
func flush_input() -> void:
	await process_frame; await process_frame
func run() -> void:
	var game := Game.instantiate(); root.add_child(game)
	await process_frame
	check(game.paused and game.menu.visible, "intro shown")
	await capture("intro")
	for i in range(3):
		game.load_room(i); game.resume()
		await process_frame
		check(not game.paused and not game.menu.visible, "room resumes")
		check(game.view.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "first person camera")
		await capture("room%d-xyz" % (i + 1))
		game.view.survey = true
		await capture("room%d-survey" % (i + 1))
		var before: Vector4 = game.world.player
		await physics_frame; await physics_frame
		check(game.world.player == before, "survey freezes physics")
		game.view.survey = false
		# Stage screenshots at real authored stations; solution tests use walking only.
		game.world.player = game.world.definition.pads[0].p
		check(game.world.switch_mode(1 if i == 1 else 2), "station switch for capture")
		await capture("room%d-alternate" % (i + 1))
		game.view.survey = true
		await capture("room%d-alternate-survey" % (i + 1))
	game.load_room(0); game.resume()
	for j in range(10): await physics_frame
	var start: Vector4 = game.world.player
	key(KEY_W)
	for j in range(10): await physics_frame
	key(KEY_W, false); await flush_input()
	check(game.world.player.y > start.y + 0.4, "physical W walks on XY floor")
	key(KEY_SPACE)
	for j in range(8): await physics_frame
	check(game.world.player.z > start.z + 0.3, "Space jumps against -Z")
	key(KEY_SPACE, false)
	game.sprint.reset()
	key(KEY_W); await flush_input(); key(KEY_W, false); await flush_input(); key(KEY_W)
	for j in range(3): await physics_frame
	check(game.sprint.active and game.world.running, "double-tap W dispatch starts sprint")
	key(KEY_W, false); await flush_input()
	check(not game.sprint.active, "release W dispatch ends sprint")
	game.world.player = game.world.definition.pads[0].p; game.world.velocity = 0
	key(KEY_3); await flush_input()
	check(game.world.frame.mode == 2 and game.world.frame.gravity == 0, "3 switches XYZ to XYW with -X down")
	check(game.view.last_axes == [1, 0, 3], "renderer uses gravity-aligned basis")
	await capture("wall-walk")
	key(KEY_F); await flush_input()
	check(game.view.survey and not game.sprint.active, "F pauses into survey and stops sprint")
	key(KEY_ESCAPE); await flush_input()
	check(game.paused and game.menu.visible, "Escape pauses through dispatcher")
	game.toggle_gravity_policy()
	check(game.manual_gravity and game.world.manual_gravity and game.paused, "gravity policy switch creates a fresh selectable trial")
	game.resume(); game.world.player = game.world.definition.pads[0].p
	key(KEY_G); await flush_input()
	check(game.world.frame.gravity == 0, "G selects -X at the station in manual mode")
	game.load_room(1); game.resume()
	game.world.player = game.world.definition.pads[0].p
	game.world.held = "a"
	game.world.cell("a").p = game.world.player + Vector4(0, 0.8, 0.5, 1.0)
	check(game.world.switch_mode(1), "held cell follows into XZW")
	game.view.sync(game.world)
	check(game.view.cell_meshes["a"].visible, "renderer keeps held cell visible in XZW")
	check(game.world.switch_mode(0), "held cell follows back into XYZ without alignment")
	game.view.sync(game.world)
	check(game.view.cell_meshes["a"].visible, "renderer keeps held cell visible after return")
	check(game.world.switch_mode(1) and game.world.choose_gravity(3), "manual XZW allows -W down and XZ floor")
	await capture("manual-xzw-w-gravity")
	game.load_room(0)
	game.world.won = true; game.paused = true; game.update_menu()
	check(game.next_button.visible and not game.resume_button.visible, "completion offers next room")
	await capture("complete")
	game.next_room(); check(game.room == 1 and game.paused and not game.world.won, "next room has fresh briefing")
	game.load_room(2); game.world.won = true; game.update_menu()
	check(not game.next_button.visible and "Research complete" in game.menu_body.text, "finale offers replay")
	check(game.menu.get_global_rect().size.x >= 600, "readable menu width")
	print("Presentation: %s / %d checks" % ["PASS" if failures == 0 else "FAIL", checks])
	game.queue_free(); await process_frame
	quit(1 if failures else 0)
