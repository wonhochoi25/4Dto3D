extends SceneTree
const World = preload("res://game/world.gd")
const Frame = preload("res://game/frame.gd")
const Sprint = preload("res://game/sprint.gd")
var failures := 0
var checks := 0
var facing := Vector3.FORWARD
var abort_route := false
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ", text)
func _initialize() -> void: call_deferred("run")
func settle(w: RefCounted, frames: int = 20) -> void:
	for i in range(frames): w.step(Vector3.ZERO, false, 1.0 / 60, facing)
func walk(w: RefCounted, target: Vector4, jumping: bool = false, sprint: bool = false) -> void:
	if abort_route: return
	for i in range(900):
		var delta: Vector3 = w.frame.to_view(target - w.player); delta.y = 0
		if w.won or delta.length() < 0.08: settle(w); return
		facing = delta.normalized()
		w.step(facing * minf(1.0, delta.length() / ((World.RUN_SPEED if sprint else World.SPEED) / 60)), jumping and w.grounded, 1.0 / 60, facing, sprint)
	check(false, "walk room %d %s to %s, at %s held %s: %s" % [w.definition.index + 1, w.frame.description(), target, w.player, w.held, w.message])
	abort_route = true
func change(w: RefCounted, mode: int) -> void:
	if abort_route: return
	var p: Vector4 = w.player
	var cargo_id: String = w.held
	check(w.switch_mode(mode), "switch at %s: %s" % [p, w.message])
	check(w.player == p, "basis change preserves ALL FOUR player coordinates")
	if not cargo_id.is_empty():
		check(w.held == cargo_id and w.cell(cargo_id).p[w.frame.hidden()] == w.player[w.frame.hidden()], "held cargo follows new slice without alignment")
	settle(w)
	if not cargo_id.is_empty():
		check(w.held == cargo_id and w.visible_box(w.cell(cargo_id).p - World.CELL_HALF, w.cell(cargo_id).p + World.CELL_HALF), "held cargo stays attached and visible after physics")
func aim(w: RefCounted, p: Vector4) -> Vector3:
	return (w.frame.to_view(p - w.player) - Vector3.UP * 0.64).normalized()
func grab(w: RefCounted) -> void:
	if abort_route: return
	facing = aim(w, w.cell("a").p)
	check(w.interact(facing) and w.held == "a", "cell pickup with ray / " + str(w.focus(facing)))
	settle(w)
func feed(w: RefCounted) -> void:
	if abort_route: return
	var s: Dictionary = w.definition.sockets[0]
	facing = aim(w, s.p); settle(w)
	check(w.interact(facing) and w.powered.has("exit"), "power exit: " + w.message)
func finish(w: RefCounted) -> void:
	walk(w, w.definition.exit)
	check(w.won, "room %d completed / selectable=%s" % [w.definition.index + 1, w.manual_gravity])
	check(w.falls == 0, "solution needs no recovery")

func room_one(manual: bool) -> void:
	abort_route = false
	var w := World.new(0, manual); settle(w)
	check(w.grounded and absf(w.player.z - 0.85) < 0.01, "XYZ uses XY floor / gravity -Z")
	check(not w.switch_mode(2), "no frame switching outside a station")
	walk(w, Vector4(0.9, -5, 0.85, 0.9))
	change(w, 2)
	check(w.frame.gravity == 0 and w.frame.axes() == [1, 0, 3], "XYW turns original X wall into YW floor")
	var frozen_z: float = w.player.z
	walk(w, Vector4(0.85, -5, frozen_z, 4))
	check(absf(w.player.w - 4) < 0.1 and w.player.z == frozen_z, "W changes continuously while hidden Z is frozen")
	walk(w, Vector4(0.85, 5, frozen_z, 4))
	change(w, 0); finish(w)
	print("Room 1 solved / ", "selectable" if manual else "priority")

func room_two(manual: bool) -> void:
	abort_route = false
	var w := World.new(1, manual); settle(w)
	grab(w)
	walk(w, Vector4(3, -5, 0.85, 0.9))
	change(w, 1)
	check(w.frame.gravity == 2, "XYZ -> XZW retains -Z under priority (and manual retention)")
	var frozen_y: float = w.player.y
	walk(w, Vector4(3, frozen_y, 0.85, 6.5))
	check(w.player.y == frozen_y, "XZW walking cannot change hidden Y")
	# Keep looking along W: no manual cargo alignment should be needed.
	change(w, 0)
	walk(w, Vector4(3, 3.1, 0.85, 6.5))
	feed(w); finish(w)
	print("Room 2 solved / ", "selectable" if manual else "priority")

func room_three(manual: bool) -> void:
	abort_route = false
	var w := World.new(2, manual); settle(w)
	grab(w)
	# Jump each 0.6m step. Same player motor/input, no artificial position changes.
	for y in [-5.3, -4.25, -3.2, -2.05]:
		walk(w, Vector4(0.9, y, 0, 0.9), true)
	check(w.player.z > 3.2 and w.grounded, "raised station reached by grounded jumping")
	change(w, 2)
	var height: float = w.player.z
	walk(w, Vector4(0.85, -2.05, height, 6))
	walk(w, Vector4(0.85, 5, height, 6))
	check(w.player.z == height and height > 3.2, "wall walk carries frozen height over the barrier")
	change(w, 0)
	if manual:
		check(w.choose_gravity(2), "manual return chooses -Z explicitly")
		settle(w)
	walk(w, Vector4(0.85, 6.5, 0, 6)); settle(w, 60)
	feed(w); finish(w)
	print("Room 3 solved / ", "selectable" if manual else "priority")

func run() -> void:
	for manual in [false, true]:
		room_one(manual); room_two(manual); room_three(manual)
	abort_route = false
	# Compare the user's two gravity ideas in the same physical corner.
	var w := World.new(1, true); settle(w)
	walk(w, Vector4(4.2, -7, 0.85, 0.9)); walk(w, Vector4(4.2, -5, 0.85, 0.9)); change(w, 1)
	var p: Vector4 = w.player
	check(w.choose_gravity(3) and w.frame.gravity == 3 and w.player == p, "manual XZW can choose -W and floor XZ without translation")
	settle(w)
	check(w.grounded and absf(w.player.w - 0.85) < 0.01, "manual -W falls onto the real W wall")
	var before: Vector4 = w.player
	w.step(Vector3.ZERO, true, 1.0 / 60, facing)
	check(w.player.w > before.w and w.player.y == before.y, "jump opposes -W; hidden Y remains fixed")
	check(not w.choose_gravity(1), "hidden axis cannot become gravity")
	var fixed := World.new(1); settle(fixed); walk(fixed, Vector4(4.2, -7, 0.85, 0.9)); walk(fixed, Vector4(4.2, -5, 0.85, 0.9))
	check(not fixed.choose_gravity(0), "priority policy disallows arbitrary gravity")
	for mode in range(4):
		check(Frame.priority_axis(mode) == [2, 2, 0, 2][mode], "exact Z > X > Y > W ordering")
	# All four systems are available in the first room's calibration stations.
	w = World.new(0, true); settle(w); walk(w, Vector4(0.9, -5, 0.85, 0.9))
	before = w.player
	check(w.switch_mode(3) and w.frame.hidden() == 0 and w.player == before, "YZW is playable and freezes X without teleportation")
	var frozen_x: float = w.player.x
	walk(w, Vector4(frozen_x, -5, 0.85, 1.4))
	check(w.player.x == frozen_x and w.player.w > 1.3, "YZW walks continuously in W while X stays fixed")
	# A selected -Y is also a real physical down direction, not a visual roll.
	w = World.new(0, true); settle(w); walk(w, Vector4(0.9, -5, 0.85, 0.9))
	check(w.choose_gravity(1), "manual gravity can select -Y in XYZ")
	settle(w, 120)
	check(w.grounded and absf(w.player.y + 9.15) < 0.01, "-Y gravity lands on the physical Y boundary")
	w.respawn()
	check(w.frame.gravity == 2 and w.player.distance_to(w.definition.pads[0].p) < 1.35, "recovery restores stable gravity after unsupported selection")
	# Body reorientation must validate clearance atomically.
	w = World.new(0, true); settle(w); walk(w, Vector4(0.9, -5, 0.85, 0.9))
	var lo: Vector4 = w.player + Vector4(-0.35, 0.6, -0.35, -0.35)
	var hi: Vector4 = w.player + Vector4(0.35, 1.0, 0.35, 0.35)
	var body := w.motor.descriptor((lo + hi) * 0.5, (hi - lo) * 0.5)
	body.bounds = {"low": lo, "high": hi}; w.obstacles.append(body)
	before = w.player
	check(not w.choose_gravity(1) and w.frame.gravity == 2 and w.player == before, "blocked standing orientation rejects without moving or partially changing frame")
	# Carry attachment survives every basis and gravity change, regardless of its
	# old hidden-coordinate offset. Released cells must remain untouched.
	for mode in range(4):
		for gravity in Frame.MODES[mode].visible:
			var carried := World.new(0, true)
			carried.player = carried.definition.pads[0].p
			carried.cells.append({"id": "regression", "p": carried.player + Vector4(0.5, 0.7, 0.5, 1.2), "start": carried.player, "secured": false, "velocity": 0.0, "gravity": 2})
			carried.cells.append({"id": "released", "p": Vector4(5, 4, 1, 4), "start": Vector4(5, 4, 1, 4), "secured": false, "velocity": 0.0, "gravity": 2})
			carried.held = "regression"
			var released_before: Vector4 = carried.cell("released").p
			check(carried.change_frame(mode, gravity), "carry frame/gravity change accepted")
			check(carried.held == "regression" and carried.cell("regression").p[carried.frame.hidden()] == carried.player[carried.frame.hidden()], "attachment centered in new slice")
			check(not carried.cell_motor.blocked(carried.cell("regression").p, carried.obstacles), "transformed attachment clears architecture")
			check(carried.cell("released").p == released_before, "released cell unchanged by coordinate switch")
			settle(carried, 2)
			check(carried.held == "regression" and carried.visible_box(carried.cell("regression").p - World.CELL_HALF, carried.cell("regression").p + World.CELL_HALF), "attachment survives subsequent physics")
	# Sprint gesture and actual speeds, including sideways camera headings.
	var gesture := Sprint.new()
	gesture.press(1000); check(not gesture.active, "first W press walks")
	gesture.release(); gesture.press(1200); check(gesture.active, "quick second W press sprints")
	gesture.release(); check(not gesture.active, "W release ends sprint")
	gesture.press(2000); check(not gesture.active, "slow second tap does not sprint")
	gesture.reset(); gesture.press(2050); check(not gesture.active, "pause/frame reset clears double-tap history")
	var walking := World.new(0); var running := World.new(0)
	for i in range(20):
		walking.step(Vector3.BACK, false, 1.0 / 60, Vector3.BACK)
		running.step(Vector3.BACK, false, 1.0 / 60, Vector3.BACK, true)
	check(running.player.y - walking.player.y > 0.8, "sprint physically moves faster even when camera faces +Y")
	print("%s: %d checks, %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures else 0)
