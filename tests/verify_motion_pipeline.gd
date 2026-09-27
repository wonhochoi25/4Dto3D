extends SceneTree
const Recording = preload("res://scripts/core/playback/simulation_recording.gd")
const Session = preload("res://scripts/core/session_4d.gd")
const Scene = preload("res://scripts/core/scene/scene_4d.gd")
class Counter:
	var value := 0
	var restores := 0
	func reset(): value = 0
	func step(_dt): value += 1
	func snapshot(): return {"counter":value}
	func restore(state):
		restores += 1
		value = state.counter
class CountedScene extends Scene:
	var samples := 0
	func sample(time: float) -> Variant:
		samples += 1
		return super.sample(time)
func _initialize():
	var counter := Counter.new()
	var recording := Recording.new(counter)
	var valid := func(_time): return true
	recording.reset(0,2)
	assert(recording.seek(1,valid))
	assert(counter.value == 60 and counter.restores == 0)
	assert(recording.seek(0.5,valid))
	assert(counter.value == 30 and counter.restores == 1)
	assert(recording.seek(1.5,valid))
	assert(counter.value == 90 and counter.restores == 2)
	recording.trim(0.25)
	assert(counter.value == 15 and recording.current_step == 15)
	recording.end = 2
	assert(recording.seek(1,valid,2))
	assert(counter.value == 15 and not recording.ready_at(1))
	assert(recording.seek(1,valid))
	assert(counter.value == 60)
	assert(not recording.seek(2,func(time): return time < 1.1))
	assert(counter.value == 60 and recording.current_step == 60)
	assert(recording.seek(2,valid))
	assert(counter.value == 120)
	var session := Session.new()
	var counted := CountedScene.new()
	session.scene = counted
	session.invalidate()
	assert(counted.samples == 1) # Initial validation supplies the display state.
	counted.samples = 0
	assert(session.seek(1))
	assert(counted.samples == 60) # No extra sample after the last validated step.
	counted.samples = 0
	assert(session.seek(0.5))
	assert(counted.samples == 1) # Replay still evaluates the restored scene.
	var moving := Session.new()
	var id := moving.add_geometry(preload("res://scripts/core/geometry/generators/tesseract.gd").new())
	assert(moving.configure_body(id,"dynamic",Vector4(1,0,0,0)))
	assert(moving.seek(1))
	assert(moving.set_group_expressions(id,{"position.0":"5"}))
	var initial := moving.world_vertices(id)
	assert(moving.seek(1))
	var advanced := moving.world_vertices(id)
	assert(absf(initial[0].x - 4.0) < 0.0001)
	assert(absf(advanced[0].x - initial[0].x - 1.0) < 0.0001)
	print("Motion pipeline passed")
	quit()
