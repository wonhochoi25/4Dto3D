extends SceneTree
## Offline deterministic face table generator. Run from the project root:
## godot --headless --path . --script res://tools/generate_faces.gd
## For these regular graphs, shortest cycles are their polygonal 2-faces.
## Hypersphere squares are sampled surface patches, not natural polytope faces.
const Registry = preload("res://scripts/shapes/shape_registry.gd")
var adjacency: Array = []
var faces: Array = []
var cycle_size := 3
func _initialize() -> void:
	for index in range(Registry.ENTRIES.size()):
		var id: String = Registry.ENTRIES[index]["id"]
		if id == "custom": continue # Custom faces come directly from the editable JSON.
		var shape = Registry.create(index)
		adjacency.clear()
		faces.clear()
		for point in shape.vertices: adjacency.append([])
		for edge in shape.edges:
			adjacency[edge.x].append(edge.y)
			adjacency[edge.y].append(edge.x)
		for neighbors in adjacency: neighbors.sort()
		cycle_size = 5 if id == "cell120" else 4 if id in ["tesseract", "hypersphere"] else 3
		for vertex in range(shape.vertices.size()): visit([vertex])
		var file := FileAccess.open("res://data/faces/%s.json" % id, FileAccess.WRITE)
		file.store_string(JSON.stringify(faces) + "\n")
		print(id, ": ", faces.size(), " faces")
	quit()
func visit(path: Array) -> void:
	if path.size() == cycle_size:
		if path[0] in adjacency[path[-1]] and path[1] < path[-1]: faces.append(path)
		return
	for neighbor in adjacency[path[-1]]:
		if neighbor > path[0] and neighbor not in path:
			var next := path.duplicate()
			next.append(neighbor)
			visit(next)
