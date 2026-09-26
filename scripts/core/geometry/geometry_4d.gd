extends RefCounted
## Base model. A generator fills vertices/edges, then captures its reset coordinates.
## Rendering and UI never belong here. Edges always refer to stable vertex IDs.
var display_name := "Shape"
var description := ""
var vertices: Array[Vector4] = []
var faces: Array = []
var edges: Array[Vector2i] = []
var original_vertices: Array[Vector4] = []

func capture_original() -> void:
	original_vertices = vertices.duplicate()

## Normalize the initial circumradius for comparable on-screen size.
func normalize_radius(radius: float = 2.0) -> void:
	for i in range(vertices.size()):
		vertices[i] = vertices[i].normalized() * radius

## For regular convex polytopes, shortest vertex pairs are exactly the edges.
## Called once at generation, never after editing (which must preserve topology).
func connect_shortest_pairs() -> void:
	var shortest := INF
	for i in range(vertices.size()):
		for j in range(i + 1, vertices.size()):
			shortest = minf(shortest, vertices[i].distance_squared_to(vertices[j]))
	for i in range(vertices.size()):
		for j in range(i + 1, vertices.size()):
			if absf(vertices[i].distance_squared_to(vertices[j]) - shortest) < shortest * 0.0001:
				edges.append(Vector2i(i, j))

