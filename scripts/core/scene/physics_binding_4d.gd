extends RefCounted
## Scene-side adapter. Physics never reads tracks, hierarchy, offsets or playback.
const Math4D = preload("res://scripts/core/math/transform_4d.gd")
const Graph = preload("res://scripts/core/scene/transform_graph_4d.gd")

static func sync(scene, physics, start_time: float) -> void:
	var matrices: Dictionary = physics.matrices()
	scene.dynamic_matrices.clear()
	for id in matrices:
		var matrix: PackedFloat64Array = matrices[id]
		if physics.motion_settings.has(id):
			var offset: PackedFloat64Array = scene.entries[id].offset
			var inverse := Graph.inverse(offset)
			var initial = scene.objects[id].group.sample(start_time)
			if inverse.is_empty() or initial==null: continue
			matrix=Math4D.multiply(Math4D.multiply(Math4D.multiply(inverse,matrix),offset),initial.matrix)
		scene.dynamic_matrices[id]=matrix

static func configuration_error(scene, physics, id: int) -> String:
	if not scene.objects.has(id): return "Unknown object ID"
	if Graph.inverse(scene.entries[id].offset).is_empty(): return "Reset the singular parenting offset before configuring body motion"
	return physics.error

static func configure(scene, physics, id: int, body_type: String, velocity: Vector4) -> bool:
	if not scene.objects.has(id) or Graph.inverse(scene.entries[id].offset).is_empty(): return false
	return physics.configure_body(id,body_type,velocity)

static func run_error(scene, physics) -> String:
	for id in physics.motion_settings:
		if scene.entries[id].parent!=0:
			return "For this first motion version, put Physics shapes directly under World before running."
	return ""
