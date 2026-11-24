extends SceneTree

const TestRoom = preload("res://hybrid/perspective_resize_test.tscn")
const World = preload("res://hybrid/perspective_test/test_room_world.gd")
const Grab = preload("res://hybrid/object_interaction/grab_controller_4d.gd")
const Placement = Grab.Placement
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func press(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	root.push_input(event, true)

func click(position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)

func walk_with_key(room, key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	room._physics_process(1.0 / 60.0)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func verify_mouse_capture(room) -> void:
	click(root.get_visible_rect().get_center())
	check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Clicking the game captures the mouse")
	var yaw: float = room.yaw
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(16, 0)
	root.push_input(motion, true)
	check(not is_equal_approx(room.yaw, yaw), "Captured motion turns the camera")
	press(KEY_ESCAPE)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Escape releases the mouse")
	click(Vector2(40, 40))
	check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Clicking over the HUD recaptures the mouse")
	press(KEY_R)
	press(KEY_G)
	room._physics_process(1.0 / 60.0)
	var player_before: Vector4 = room.world.player_position
	walk_with_key(room, KEY_W)
	check(room.world.player_position.x > player_before.x,
		"The movement key reaches the physics tick in resize mode")
	press(KEY_G)
	press(KEY_T)
	for tick in range(40):
		room._physics_process(1.0 / 60.0)
	press(KEY_2)
	check(room.mode == 1 and room.artifact.visible, "Fixed-size pickup brings the artifact into the new view")
	player_before = room.world.player_position
	var artifact_before: Vector4 = room.world.object_position
	walk_with_key(room, KEY_W)
	check(room.world.player_position.w > player_before.w and room.world.object_position.w > artifact_before.w,
		"The movement key in YZW advances both the player and the locked artifact along W")
	room.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	player_before = room.world.player_position
	walk_with_key(room, KEY_W)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and room.world.player_position == player_before,
		"Losing window focus releases the mouse and stops movement")
	press(KEY_ESCAPE)
	press(KEY_R)

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)

func screen_height(room) -> float:
	var top := INF
	var bottom := -INF
	var points: PackedVector3Array = room.world.slice_points(
		room.world.object_id, 0, room.world.player_position.w)
	for point in points:
		var screen: Vector2 = room.view.camera.unproject_position(point)
		top = minf(top, screen.y)
		bottom = maxf(bottom, screen.y)
	return bottom - top

func verify_contact_recovery(room) -> void:
	var wall: Array[Dictionary] = [{"low": Vector4(5, -2, -2, -2), "high": Vector4(6, 2, 2, 2)}]
	var half := Vector4.ONE * 0.25
	var touching_skin := Vector4(4.7495, 0, 0, 0)
	check(Placement.safe_fraction(touching_skin, touching_skin - Vector4(0.04, 0, 0, 0), half, half, wall) == 1.0,
		"An object already inside the wall's skin can back away")
	check(Placement.safe_fraction(touching_skin, touching_skin + Vector4(0, 0, 0, 0.04), half, half, wall) == 1.0,
		"An object already inside the wall's skin can slide along W")
	check(Placement.safe_fraction(touching_skin, touching_skin + Vector4(0.04, 0, 0, 0), half, half, wall) == 0.0,
		"An object next to a wall cannot move into it")
	var penetrating := Vector4(4.76, 0, 0, 0)
	check(Placement.safe_fraction(penetrating, penetrating + Vector4(0, 0, 0, 5), half, half, wall) == 0.0,
		"An actually intersecting box cannot use skin recovery to bypass the wall")

	press(KEY_R)
	press(KEY_G)
	room.step(Vector3.ZERO)
	var world: RefCounted = room.world
	var near_wall: float = World.ROOM_LOW.x + world.player_half.x + Placement.SKIN * 0.5
	world.set_player(Vector4(near_wall, 0, 0, 0))
	room.step(Vector3.BACK * (2.5 / 60.0))
	check(world.player_blocked and is_equal_approx(world.player_position.x, near_wall),
		"The player still stops at the wall while resizing")
	room.step(Vector3.FORWARD * (2.5 / 60.0))
	check(not world.player_blocked and world.player_position.x > near_wall + 0.03,
		"The player can immediately reverse while resizing")

func verify_carry_obstruction(room) -> void:
	press(KEY_R)
	var world: RefCounted = room.world
	world.room_bounds.append({"low": Vector4(-2.6, -2, -2, -1), "high": Vector4(-2.4, 2, 2, 1)})
	press(KEY_T)
	check(world.hold == Grab.Hold.RELEASED, "Fixed-size pickup requires an unobstructed view")
	world.room_bounds.pop_back()
	press(KEY_T)
	var initial_player: Vector4 = world.player_position
	var initial_artifact: Vector4 = world.object_position
	world.room_bounds.append({"low": Vector4(-3.4, -2, -2, 0.6), "high": Vector4(-2.6, 2, 2, 2.1)})
	press(KEY_2)
	check(room.mode == 0 and world.player_position == initial_player and world.object_position == initial_artifact,
		"A blocked transfer leaves the player, object and slice untouched")
	world.room_bounds.pop_back()
	world.room_bounds.append({"low": Vector4(-2.55, -2, -2, 0.5), "high": Vector4(-2.25, 2, 2, 2)})
	press(KEY_2)
	check(room.mode == 0 and world.object_position == initial_artifact,
		"A clear destination cannot be reached by skipping an obstacle along the transfer path")
	world.room_bounds.pop_back()
	press(KEY_2)
	check(room.mode == 1 and world.player_position == initial_player and room.artifact.visible,
		"Clearing the obstruction lets the held artifact move into YZW")
	var size: float = world.object_scale
	for tick in range(180):
		room.step(Vector3.FORWARD * (2.5 / 60.0))
	check(absf(world.object_position.w + World.OBJECT_HALF.w * size - World.ROOM_HIGH.w) < 0.01,
		"The artifact travels along W until its full thickness reaches the wall")
	check(world.carry_limited, "The game reports that a wall restricted carrying")
	check(world.hold == Grab.Hold.CARRY and world.object_scale == size,
		"An obstructed artifact remains attached at the locked scale")
	var limit: float = world.object_position.w
	var before: Vector4 = world.player_position
	room.step(Vector3.RIGHT * 0.25)
	check(world.player_position.distance_to(before) > 0.2, "A held artifact at the wall allows sidestepping")
	for tick in range(75):
		room.step(Vector3.BACK * (2.5 / 60.0))
	check(world.object_position.w < limit - 1.0 and room.artifact.visible,
		"The artifact backs away from the wall and stays in the active slice")
	check(not world.carry_limited, "The carry restriction clears when the artifact catches up")

func verify_carry_turn(room) -> void:
	press(KEY_R)
	press(KEY_T)
	room.yaw = PI / 2.0
	for tick in range(80):
		room.step(Vector3.ZERO)
	check(room.world.object_position.x < room.world.player_position.x - 1.0 and room.world.object_scale == 1.0,
		"A fast turn moves the artifact around the player at its original size")

func verify_shared_controller() -> void:
	var grab := Grab.new(Vector4.ONE * 0.2)
	var player := Vector4(8, 0, 0, 1)
	var xyz := {"axes": [0, 1, 2], "hidden": 3}
	var yzw := {"axes": [3, 1, 2], "hidden": 0}
	var obstacles: Array[Dictionary] = []
	var fixed_size := Grab.Box.new(player + Vector4(1.3, 0, 0, 0), Vector4.ONE * 0.2, 1.4)
	fixed_size.can_resize = false
	var resizable := Grab.Box.new(player + Vector4(1.7, 0, 0, 0), Vector4.ONE * 0.25)
	resizable.max_scale = 1.1

	check(grab.pickup(fixed_size, Grab.Hold.RESIZE, player, xyz, Vector3.RIGHT, obstacles) == Grab.Result.DISABLED,
		"A room can disable resizing per object")
	check(grab.pickup(fixed_size, Grab.Hold.CARRY, player, xyz, Vector3.RIGHT, obstacles) == Grab.Result.OK,
		"The shared controller can grab an object with no demo scene")
	check(grab.pickup(resizable, Grab.Hold.RESIZE, player, xyz, Vector3.RIGHT, obstacles) == Grab.Result.ALREADY_HOLDING,
		"Selecting a second object cannot replace a held one")
	var transfer := grab.try_switch_slice(player, yzw, Vector3.RIGHT, obstacles)
	check(transfer == Grab.Result.OK and fixed_size.in_slice(player, yzw.hidden) and fixed_size.scale == 1.4,
		"A different room can supply its own positions and slice to transfer a held box")
	check(grab.release() == fixed_size, "Release returns the same object to the room")

	obstacles.append(Placement.bounds(fixed_size.position, fixed_size.half_extents()))
	check(grab.pickup(resizable, Grab.Hold.RESIZE, player, xyz, Vector3.RIGHT, obstacles) == Grab.Result.OK,
		"The controller can pick up a different object after release")
	grab.update(player, xyz, Vector3.RIGHT, 1.0 / 60.0, obstacles)
	check(is_equal_approx(resizable.scale, 1.1) and fixed_size.scale == 1.4,
		"Resizing uses the new object's scale limit and leaves the released box alone")

func verify_delivery(room) -> void:
	var world: RefCounted = room.world
	var chosen_size: float = world.object_scale
	var far_pose: Vector4 = world.object_position
	press(KEY_T)
	check(world.hold == Grab.Hold.RESIZE, "The fixed-size button cannot change an active resize pickup")
	press(KEY_2)
	check(room.mode == 0 and world.hold == Grab.Hold.RESIZE, "Release is required before switching while resizing")
	press(KEY_G)
	check(world.hold == Grab.Hold.RELEASED and world.object_scale == chosen_size and world.object_position == far_pose,
		"Releasing the resize pickup commits the selected pose and size")
	press(KEY_2)
	check(room.mode == 1 and not room.artifact.visible and world.object_position == far_pose,
		"A released artifact remains in 4D space when switching views")
	press(KEY_T)
	check(world.hold == Grab.Hold.RELEASED, "Fixed-size pickup requires seeing the artifact in the current slice")
	press(KEY_1)
	press(KEY_T)
	check(world.hold == Grab.Hold.CARRY and world.object_scale == chosen_size,
		"Fixed-size pickup can reacquire the resized artifact from across the room")
	press(KEY_G)
	check(world.hold == Grab.Hold.CARRY, "The resize button cannot change an active fixed-size pickup")
	for tick in range(40):
		room.step(Vector3.ZERO)
	check(world.object_position.x < far_pose.x - 1.0 and world.object_scale == chosen_size,
		"Fixed-size carry pulls the artifact into reach without resizing it")
	var player_before: Vector4 = world.player_position
	press(KEY_2)
	check(room.mode == 1 and room.artifact.visible and world.player_position == player_before,
		"Changing slices brings the held artifact visibly along without teleporting the player")
	check(is_equal_approx(world.object_position.x, player_before.x) and world.object_position.w > player_before.w,
		"The artifact is centered in YZW and in front of the player")
	room.step(Vector3.FORWARD * World.TARGET.w)
	check(is_equal_approx(world.player_position.w, World.TARGET.w) and room.artifact.visible,
		"The artifact follows the player down the W corridor")
	press(KEY_1)
	check(room.mode == 0 and room.artifact.visible and is_equal_approx(world.object_position.w, World.TARGET.w),
		"The artifact returns visibly to XYZ on the destination W slice")
	room.step(Vector3.FORWARD * (World.TARGET.x - world.object_position.x))
	var placed_at: Vector4 = world.object_position
	press(KEY_T)
	check(world.placed and world.hold == Grab.Hold.RELEASED, "Releasing in the 4D target confirms placement")
	room.step(Vector3.FORWARD * 0.5)
	check(world.object_position == placed_at and world.object_scale == chosen_size,
		"Placement keeps the chosen 4D pose and scale after the player moves")

func run() -> void:
	var room = TestRoom.instantiate()
	root.add_child(room)
	room.set_physics_process(false)
	if DisplayServer.get_name() != "headless":
		verify_mouse_capture(room)
	var world: RefCounted = room.world
	var pickup_height := screen_height(room)
	press(KEY_G)
	check(world.hold == Grab.Hold.RESIZE, "G picks up the artifact from the spawn view")
	room.step(Vector3.ZERO)
	var far_scale: float = world.object_scale
	var far_position: Vector4 = world.object_position
	check(far_scale > 3.5, "Looking into the alcove enlarges the artifact")
	check(pickup_height > 0.0 and absf(screen_height(room) - pickup_height) < 0.5,
		"A larger artifact at greater depth keeps its original projected height")
	check(absf(far_position.x + World.OBJECT_HALF.x * far_scale - 4.8) < 0.01,
		"The off-slice W lip limits full-volume placement: %s at ×%.3f" % [far_position, far_scale])
	var hidden_lip: Dictionary = world.room_bounds.pop_back()
	room.step(Vector3.ZERO)
	check(world.object_scale > far_scale + 1.0, "The same XYZ ray goes farther without the W lip: ×%.3f" % world.object_scale)
	world.room_bounds.append(hidden_lip)
	world.artifact.position = far_position
	world.artifact.scale = far_scale
	world.sync_scene(world.player_position)

	room.step(Vector3.FORWARD * 0.75)
	check(world.object_scale < far_scale - 0.2, "Walking toward the lip shrinks the held artifact: ×%.3f" % world.object_scale)
	var depth: float = world.object_position.x - world.player_position.x
	check(absf(world.object_scale / depth - 1.0 / 1.6) < 0.001,
		"Accepted depth and size preserve the original apparent scale")
	room.step(Vector3.BACK * 0.75)
	check(is_equal_approx(world.object_scale, far_scale), "Backing away restores the original held scale")

	verify_delivery(room)

	press(KEY_R)
	check(world.object_position == World.OBJECT_START and world.object_scale == 1.0 and not world.placed,
		"Reset restores the spawn and clears placement")
	press(KEY_G)
	for step_index in range(1, 37):
		room.yaw = -PI / 2.0 - step_index * 0.02
		room.step(Vector3.ZERO)
	check(world.object_scale < far_scale - 0.5, "Aiming toward the near wall shrinks the artifact")

	var obstacle: Array[Dictionary] = [
		{"low": Vector4(-0.01, -1, 0.2, -1), "high": Vector4(0.01, 1, 1, 1)}]
	var stop := Placement.safe_fraction(Vector4(-5, 0, 0, 0), Vector4(5, 0, 0, 0),
		Vector4.ONE * 0.4, Vector4.ONE * 0.7, obstacle)
	check(stop > 0.4 and stop < 0.5, "A changing full box hits a thin lip that the center ray misses")
	verify_contact_recovery(room)
	verify_carry_obstruction(room)
	verify_carry_turn(room)
	verify_shared_controller()
	print("Perspective resize room failures: ", failures)
	quit(int(failures > 0))
