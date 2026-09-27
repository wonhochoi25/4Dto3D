extends "res://scripts/core/playback/simulation_recording.gd"
## Legacy default constructor; new callers inject their runtime into the core recorder.
func _init(runtime = null):
	super(runtime if runtime != null else preload("res://scripts/core/physics/physics_world_4d.gd").new())
