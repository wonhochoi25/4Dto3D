extends SceneTree
const Hull = preload("res://scripts/rendering/projected_hull_3d.gd")
var failures := 0
func check(ok: bool, label: String):
	if not ok:
		failures+=1
		push_error(label)
func _initialize(): call_deferred("verify")
func verify():
	var p := PackedVector3Array()
	for x in [-1,1]:
		for y in [-1,1]:
			for z in [-1,1]: p.append(Vector3(x,y,z))
	p.append(Vector3.ZERO)
	p.append(p[0])
	var cube := Hull.build(p)
	check(cube.dimension==3 and cube.triangles.size()==12 and cube.edges.size()==12,"Cube exterior ignores interior/duplicates")
	var volume := 0.0
	for t in cube.triangles: volume+=cube.vertices[t[0]].dot(cube.vertices[t[1]].cross(cube.vertices[t[2]]))/6.0
	check(absf(volume-8)<1e-4,"Closed outward hull volume")
	var plane := Hull.build(PackedVector3Array([Vector3(0,0,0),Vector3(1,0,0),Vector3(1,1,0),Vector3(0,1,0)]))
	check(plane.dimension==2 and plane.triangles.size()==2,"Planar hull")
	check(Hull.build(PackedVector3Array([Vector3.ZERO,Vector3.ONE])).dimension==1,"Line fallback")
	check(Hull.build(PackedVector3Array([Vector3.ZERO])).dimension==0,"Point fallback")
	var scene = preload("res://scripts/sandbox/physics/physics_scene.gd").new()
	root.add_child(scene)
	var card = scene.add_shape(0)
	check(scene.numeric_mode and scene.timeline.process_mode==Node.PROCESS_MODE_DISABLED,"No timeline playback")
	check(card.renderer.hull.dimension==3 and card.renderer.face_material.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED,"Opaque solid")
	card.fields["position.0"].text="t"
	scene.apply_card(card)
	check(card.message.text.contains("finite number"),"Expressions rejected")
	card.fields["position.0"].text="2"
	scene.apply_card(card)
	check(card.object.track.sources["position.0"].to_float()==2,"Numeric apply")
	for i in range(12): card.fields["projection.%d"%i].text="0"
	scene.apply_card(card)
	check(card.renderer.hull.dimension==0 and card.renderer.edges.visible,"Collapsed point visible")
	for index in range(1,7):
		var shape = scene.add_shape(index)
		check(shape.renderer.hull.dimension==3,"Built-in solid %d"%index)
		var hull: Dictionary = shape.renderer.hull
		var ridges := {}
		for tri in hull.triangles:
			var v0: Vector3 = hull.vertices[tri[0]]
			var n: Vector3 = (hull.vertices[tri[1]]-v0).cross(hull.vertices[tri[2]]-v0).normalized()
			for point in shape.object.last_points: check(n.dot(point-v0)<1e-4,"Hull contains projected vertices")
			for i in range(3):
				var edge := [tri[i],tri[(i+1)%3]]
				edge.sort()
				var key := str(edge)
				ridges[key] = ridges.get(key,0)+1
		for count in ridges.values(): check(count==2,"Closed triangular hull")
	var registry = preload("res://scripts/io/shape_catalog.gd")
	for i in range(registry.ENTRIES.size()):
		if registry.ENTRIES[i].get("path","").ends_with("hi_4d.json"):
			var custom = scene.add_shape(i)
			check(custom!=null,"Custom animation loads as static pose")
			if custom != null:
				for value in custom.object.sources.values(): check(str(value).is_valid_float(),"Custom fields frozen to numbers")
	var group = scene.pairs[card.get_meta("group_id")].group_card
	group.fields["anchor.0"].text="1"
	scene.apply_card(group)
	for value in group.object.track.sources.values(): check(str(value).is_valid_float(),"Anchor compensation stays numeric")
	scene.queue_free()
	await process_frame
	print("Physics view failures: ",failures)
	quit(1 if failures else 0)
