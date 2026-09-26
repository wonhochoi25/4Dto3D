extends "res://scripts/core/scene/transform_graph_4d.gd"
## Authoritative object ownership. Public object IDs refer to automatic group nodes.
const Track = preload("res://scripts/core/animation/transform_track_4d.gd")
var objects: Dictionary = {}

func add_geometry(geometry, geometry_settings: Dictionary = {}, group_settings: Dictionary = {}, time: float = 0.0) -> int:
	var owned = preload("res://scripts/core/geometry/geometry_4d.gd").new()
	owned.display_name = geometry.display_name
	owned.description = geometry.description
	owned.vertices = geometry.vertices.duplicate()
	owned.edges = geometry.edges.duplicate()
	owned.faces = geometry.faces.duplicate(true)
	owned.original_vertices = geometry.original_vertices.duplicate()
	var group := Track.new(true)
	var leaf := Track.new(false)
	if not group.initialize_defaults(group_settings, time):
		error = "Group " + group.error_field + ": " + group.error
		return 0
	if not leaf.initialize_defaults(geometry_settings, time):
		error = "Geometry " + leaf.error_field + ": " + leaf.error
		return 0
	var id := add(group)
	var leaf_id := add(leaf)
	entries[leaf_id].parent = id
	objects[id] = {"geometry": owned, "group": group, "track": leaf, "leaf_id": leaf_id, "name": geometry.display_name}
	return id

func remove_object(id: int, time: float) -> bool:
	if not objects.has(id): return false
	var leaf_id: int = objects[id].leaf_id
	if not remove(id, time): return false
	entries.erase(leaf_id)
	objects.erase(id)
	return true

func world_vertices(id: int, state: Dictionary) -> Array[Vector4]:
	var result: Array[Vector4] = []
	for vertex in objects[id].geometry.vertices:
		result.append(Math4D.apply(state[objects[id].leaf_id].world, vertex))
	return result

## Dynamic matrices override the group's local track, then use normal parent/offset composition.
var dynamic_matrices: Dictionary = {}
func local_sample(id: int, time: float) -> Variant:
	if dynamic_matrices.has(id): return {"matrix": dynamic_matrices[id]}
	return entries[id].model.sample(time)
