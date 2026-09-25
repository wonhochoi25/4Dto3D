extends Node3D
## Fan-triangulates projected polygon faces. Degenerate projected triangles are skipped.
## Alpha sorting has the usual overlapping-transparency limitations.
var surface := MeshInstance3D.new()
var edges := MeshInstance3D.new()
var face_material := StandardMaterial3D.new()
var edge_material := StandardMaterial3D.new()

func _ready() -> void:
	add_child(surface)
	add_child(edges)
	face_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	face_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	face_material.roughness = 0.7
	surface.material_override = face_material
	edge_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	edges.material_override = edge_material

func update_style(object) -> void:
	visible = object.visible
	face_material.albedo_color = object.color
	edge_material.albedo_color = Color(object.color.r, object.color.g, object.color.b, 0.7)
	edges.visible = object.show_edges

func render(object, points: PackedVector3Array) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for face in object.faces:
		var a := points[int(face[0])]
		for i in range(1, face.size() - 1):
			var b := points[int(face[i])]
			var c := points[int(face[i + 1])]
			var normal := (b - a).cross(c - a)
			if normal.length_squared() < 1e-12: continue
			normal = normal.normalized()
			vertices.append_array(PackedVector3Array([a, b, c]))
			normals.append_array(PackedVector3Array([normal, normal, normal]))
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	surface.mesh = mesh
	var line_arrays := []
	line_arrays.resize(Mesh.ARRAY_MAX)
	line_arrays[Mesh.ARRAY_VERTEX] = points
	var indices := PackedInt32Array()
	for edge in object.shape.edges: indices.append_array(PackedInt32Array([edge.x, edge.y]))
	line_arrays[Mesh.ARRAY_INDEX] = indices
	var line_mesh := ArrayMesh.new()
	line_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, line_arrays)
	edges.mesh = line_mesh
	update_style(object)
