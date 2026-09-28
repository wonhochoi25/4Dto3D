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
	print("Projected hull failures: ",failures)
	quit(1 if failures else 0)
