extends SceneTree
## Recorder test with no physics implementation installed.
const Recording = preload("res://scripts/core/playback/simulation_recording.gd")
class Counter:
	var value := 0
	func reset(): value=0
	func step(_dt): value+=1
	func snapshot(): return {"counter":value}
	func restore(state): value=state.counter
func _initialize():
	var counter := Counter.new()
	var recording := Recording.new(counter)
	recording.reset(0,2)
	assert(recording.seek(1,func(_time): return true))
	assert(counter.value==60)
	assert(recording.seek(0.5,func(_time): return true))
	assert(counter.value==30)
	assert(recording.seek(1,func(_time): return true))
	assert(counter.value==60)
	print("Recorder module passed")
	quit()
