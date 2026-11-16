extends Node3D
## Debug visualization of the eight projected cubic cells of a tesseract.
const Hull = preload("res://scripts/rendering/projected_hull_3d.gd")
var meshes: Array[MeshInstance3D] = []
var enabled := false

func set_cells(point_clouds: Array, center: Vector3) -> void:
	while meshes.size() > point_clouds.size():
		var old = meshes.pop_back()
		old.queue_free()
	while meshes.size() < point_clouds.size():
		var instance := MeshInstance3D.new()
		add_child(instance)
		meshes.append(instance)
	for i in range(point_clouds.size()):
		var points: PackedVector3Array = point_clouds[i]
		var hull: Dictionary = Hull.build(points)
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		for tri in hull.triangles:
			var a: Vector3 = hull.vertices[tri[0]] - center
			var b: Vector3 = hull.vertices[tri[1]] - center
			var c: Vector3 = hull.vertices[tri[2]] - center
			var normal := (b-a).cross(c-a).normalized()
			vertices.append_array(PackedVector3Array([a,c,b]))
			normals.append_array(PackedVector3Array([normal,normal,normal]))
		var mesh := ArrayMesh.new()
		if not vertices.is_empty():
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		meshes[i].mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color.from_hsv(float(i)/8.0, 0.72, 0.95, 0.32)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		meshes[i].material_override = material
		meshes[i].visible = enabled and mesh.get_surface_count() > 0

func set_enabled(value: bool) -> void:
	enabled = value
	for mesh in meshes: mesh.visible = enabled and mesh.mesh != null
