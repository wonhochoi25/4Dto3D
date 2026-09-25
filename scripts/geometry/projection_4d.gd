extends RefCounted
## Linear R4 → R3 mapping; no model mutation, slicing, or perspective division.
var rows: Array[Vector4] = [Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0)]

func project(vertices: Array[Vector4]) -> PackedVector3Array:
	var result := PackedVector3Array()
	for point in vertices:
		result.append(Vector3(rows[0].dot(point), rows[1].dot(point), rows[2].dot(point)))
	return result
