extends RefCounted
## Scene-side adapter. Physics never reads tracks, hierarchy, offsets or playback.
const Math4D = preload("res://scripts/core/math/transform_4d.gd")
const Graph = preload("res://scripts/core/scene/transform_graph_4d.gd")

# Cached only between session invalidations (pose, parenting, body or start-time edits).
var starting_frames: Dictionary = {}

func invalidate() -> void:
	starting_frames.clear()

## Track-driven kinematic bodies use the ordinary graph at t. Other configured
## bodies freeze geometry at the start; dynamics/rate drivers own the group pose.
func sync(scene, physics, start_time: float) -> bool:
	scene.dynamic_matrices.clear()
	if starting_frames.is_empty() and not physics.motion_settings.is_empty():
		var initial = scene.sample(start_time)
		if initial == null: return false
		for id in physics.motion_settings:
			var object: Dictionary = scene.objects[id]
			var group = object.group.sample(start_time)
			var leaf = object.track.sample(start_time)
			var offset: PackedFloat64Array = scene.entries[id].offset
			starting_frames[id] = {"inverse":Graph.inverse(offset),
				"initial":Math4D.multiply(offset,group.matrix),
				"group":group.matrix,"leaf":leaf.matrix}
	physics.write_matrices(scene.dynamic_matrices)
	for id in physics.motion_settings:
		var config: Dictionary = physics.motion_settings[id]
		if config.get("source","rates") == "tracks":
			scene.dynamic_matrices.erase(id)
			continue
		var frame: Dictionary = starting_frames[id]
		scene.dynamic_matrices[scene.objects[id].leaf_id] = frame.leaf
		if config.type == "static":
			scene.dynamic_matrices[id] = frame.group
		else:
			scene.dynamic_matrices[id] = Math4D.multiply(Math4D.multiply(frame.inverse,scene.dynamic_matrices[id]),frame.initial)
	return true

static func configuration_error(scene, physics, id: int) -> String:
	if not scene.objects.has(id): return "Unknown object ID"
	if Graph.inverse(scene.entries[id].offset).is_empty(): return "Reset the singular parenting offset before configuring body motion"
	return physics.error

static func configure(scene, physics, id: int, body_type: String, velocity: Vector4, motion: Dictionary = {}) -> bool:
	if not scene.objects.has(id): return false
	if motion.get("source","rates") != "tracks" and body_type != "static" and Graph.inverse(scene.entries[id].offset).is_empty(): return false
	return physics.configure_body(id,body_type,velocity,motion)

static func run_error(scene, physics) -> String:
	for id in physics.motion_settings:
		if scene.entries[id].parent!=0 and physics.motion_settings[id].type != "static" and physics.motion_settings[id].get("source","rates") != "tracks":
			return "Dynamic and rate-driven bodies must be directly under World. Track-driven kinematic bodies may be parented."
	return ""

## Translate evaluated scene state to borrowed, read-only collider descriptors.
static func colliders(scene, physics, evaluated: Dictionary) -> Dictionary:
	var result := {}
	for id in physics.body_types:
		if not scene.objects.has(id): continue
		var object: Dictionary=scene.objects[id]
		if evaluated.has(object.leaf_id):
			result[id]={"geometry":object.geometry,"world":evaluated[object.leaf_id].world}
	return result
