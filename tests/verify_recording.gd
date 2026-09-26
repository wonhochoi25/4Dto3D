extends SceneTree
const Recording = preload("res://scripts/procedural/simulation_recording.gd")
var failures := 0
var evaluations := 0
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		push_error(label)
func valid(_time: float) -> bool:
	evaluations += 1
	return true
func _initialize(): call_deferred("verify")
func verify():
	var recording := Recording.new()
	recording.simulation.add_body(1, Vector4.ZERO, Vector4(1,2,3,4))
	recording.reset(-1, 4)
	check(recording.seek(1, valid), "Forward integration")
	check(absf(recording.simulation.bodies[1][3]-8) < 0.00001, "4D constant velocity")
	var state = recording.simulation.snapshot()
	var calls := evaluations
	check(recording.seek(-0.5, valid), "Reverse restore")
	check(absf(recording.simulation.bodies[1][0]-0.5) < 0.00001, "Earlier position restored")
	check(recording.seek(1, valid) and recording.simulation.bodies[1] == state[1], "Exact replay")
	check(evaluations == calls, "Replay does not step simulation")
	recording.seek(2, valid)
	check(absf(recording.simulation.bodies[1][0]-3) < 0.00001, "Extends from latest recorded state")
	recording.trim(0)
	check(recording.frames.size() == 61, "Trim bounded history")
	recording.reset(0, 10)
	recording.seek(10, valid, 2)
	check(not recording.ready_at(10), "Seek yields")
	while not recording.ready_at(10): recording.seek(10, valid, 100)
	check(recording.frames.size() == 601, "Every fixed step recorded")
	var scene = load("res://scripts/procedural/procedural_scene.gd").new()
	root.add_child(scene)
	var card = scene.add_shape(0)
	scene.evaluate_time(1.004)
	check(scene.timeline.time == 1, "Scrub snaps to step")
	var count: int = scene.recording.frames.size()
	card.fields["projection.0"].text = "2"
	scene.apply_card(card)
	check(scene.timeline.time == 1 and scene.recording.frames.size() == count, "Projection preserves recording")
	card.fields["position.0"].text = "t"
	scene.apply_card(card)
	check(scene.timeline.time == 0 and scene.recording.frames.size() == 1, "Transform edit resets")
	scene.timeline.direction = 1
	for i in range(120): scene.timeline._process(1.0/120.0)
	check(absf(scene.timeline.time-1) < 0.00001, "High FPS accumulates fractional steps")
	scene.queue_free()
	await process_frame
	print("Recording failures: ", failures)
	quit(1 if failures else 0)
