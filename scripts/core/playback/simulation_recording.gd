extends RefCounted
## Snapshots contain dynamic state, never vertices, projected meshes, or UI data.
const STEP := 1.0 / 60.0
const Simulation = preload("res://scripts/core/simulation/simulation_4d.gd")
var simulation := Simulation.new()
var frames: Array[Dictionary] = []
var start := 0.0
var end := 10.0
var current_step := 0
var error := ""

func reset(from: float, to: float) -> void:
	start = from
	end = to
	current_step = 0
	frames.clear()
	simulation.reset()

func last_step() -> int:
	return maxi(0, int(floor((end - start) / STEP + 0.000001)))

func index_at(time: float) -> int:
	return clampi(int(round((time - start) / STEP)), 0, last_step())

func time_at(index: int) -> float:
	return start + index * STEP

func trim(to: float) -> void:
	end = to
	if frames.size() > last_step() + 1: frames.resize(last_step() + 1)
	current_step = mini(current_step, last_step())

## Return false on invalid simulation step; valid earlier snapshots remain usable.
## A budget allows distant seeks to yield to the UI between batches.
func seek(time: float, validate: Callable, budget: int = 2147483647) -> bool:
	error = ""
	var target := index_at(time)
	if frames.is_empty():
		if not validate.call(start):
			error = "Invalid initial state"
			return false
		frames.append(simulation.snapshot())
	var steps := 0
	var started := Time.get_ticks_usec()
	while frames.size() <= target and steps < budget:
		simulation.restore(frames.back())
		simulation.step(STEP)
		if not validate.call(time_at(frames.size())):
			simulation.restore(frames[current_step])
			error = "Invalid simulation step"
			return false
		frames.append(simulation.snapshot())
		steps += 1
		if budget != 2147483647 and Time.get_ticks_usec() - started > 8000: break
	if frames.size() <= target:
		simulation.restore(frames[current_step])
		return true
	current_step = target
	simulation.restore(frames[target])
	return true

func ready_at(time: float) -> bool:
	return not frames.is_empty() and index_at(time) < frames.size()
