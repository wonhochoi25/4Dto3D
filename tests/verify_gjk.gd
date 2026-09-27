extends SceneTree
const GJK = preload("res://scripts/core/physics/collision/gjk_4d.gd")
const Collider = preload("res://scripts/core/physics/collision/convex_vertices_4d.gd")
const Simplex = preload("res://scripts/core/physics/collision/simplex_4d.gd")
const Math4D = preload("res://scripts/core/math/transform_4d.gd")
const Box = preload("res://scripts/core/geometry/generators/tesseract.gd")
var failures := 0
class Sphere:
	var valid := true
	var center: PackedFloat64Array
	var radius: float
	func _init(c: PackedFloat64Array, r: float):
		center = c
		radius = r
	func support(d: PackedFloat64Array) -> PackedFloat64Array:
		var p := center.duplicate()
		var length := sqrt(Simplex.dot(d,d))
		if length > 0:
			for i in range(4): p[i] += radius*d[i]/length
		return p
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		push_error(label)
func box(position: Vector4, scale: Vector4 = Vector4.ONE):
	var transform := Math4D.new()
	transform.position = position
	transform.scale = scale
	return Collider.new(Box.new().vertices,transform.matrix())
func _initialize(): call_deferred("verify")
func verify():
	var inside := Simplex.closest([PackedFloat64Array([1,0,0,0]),PackedFloat64Array([0,1,0,0]),PackedFloat64Array([0,0,1,0]),PackedFloat64Array([0,0,0,1]),PackedFloat64Array([-1,-1,-1,-1])])
	check(inside.squared < 1e-20, "Origin inside 4-simplex")
	var segment := Simplex.closest([PackedFloat64Array([2,1,0,0]),PackedFloat64Array([-2,1,0,0]),PackedFloat64Array([-2,1,0,0])])
	check(absf(segment.squared-1) < 1e-12, "Degenerate simplex reduces to closest edge")
	var a = box(Vector4.ZERO)
	for distance in [0.0,1.0,2.0,2.01,4.0]:
		var result := GJK.query(a,box(Vector4(0,0,0,distance)))
		check(result.status == ("separated" if distance > 2 else "intersecting"), "W separation %.2f: %s" % [distance,result])
		if distance > 2: check(absf(result.distance-(distance-2)) < 1e-5, "Box distance")
	check(GJK.query(a,box(Vector4.ZERO,Vector4.ONE*0.1)).status == "intersecting", "Containment")
	check(GJK.query(box(Vector4.ZERO,Vector4(1,1,0,0)),box(Vector4(0,0,0,1),Vector4(1,1,0,0))).status == "separated", "Flat shapes separated in W")
	check(GJK.query(box(Vector4.ZERO,Vector4.ZERO),box(Vector4.ZERO,Vector4.ZERO)).status == "intersecting", "Collapsed points")
	check(GJK.query(a,a,0).status == "indeterminate", "Iteration limit explicit")
	check(GJK.query(Collider.new([],Math4D.identity()),a).status == "indeterminate", "Empty collider explicit")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42041
	for test in range(150):
		var delta := Vector4(rng.randf_range(-5,5),rng.randf_range(-5,5),rng.randf_range(-5,5),rng.randf_range(-5,5))
		var b = box(delta)
		var expected := 0.0
		for axis in range(4): expected += maxf(absf(delta[axis])-2,0) ** 2
		expected = sqrt(expected)
		var result := GJK.query(a,b)
		check(result.status == ("separated" if expected > 1e-4 else "intersecting"), "Random box status %d" % test)
		check(absf(result.distance-expected) < 2e-5, "Analytic box distance %d" % test)
		var swap := GJK.query(b,a)
		check(swap.status == result.status and absf(swap.distance-result.distance) < 2e-5, "Swap symmetry")
		if result.status == "separated": check(result.gap > 0, "Separating interval certificate")
		var rotation := Math4D.new()
		for plane in range(6): rotation.angles[plane] = rng.randf_range(-180,180)
		rotation.position = Vector4(12,-4,6,9)
		var ra = Collider.new(Box.new().vertices,rotation.matrix())
		var rb = Collider.new(Box.new().vertices,Math4D.multiply(rotation.matrix(),Math4D.translation(delta)))
		var rotated := GJK.query(ra,rb)
		check(rotated.status == result.status and absf(rotated.distance-expected) < 2e-5, "Common rigid transform invariant")
		var center := PackedFloat64Array([delta.x,delta.y,delta.z,delta.w])
		var sphere := GJK.query(Sphere.new(PackedFloat64Array([0,0,0,0]),1),Sphere.new(center,0.5))
		var sphere_distance := maxf(delta.length()-1.5,0)
		check(sphere.status == ("separated" if sphere_distance > 1e-4 else "intersecting"), "Analytic sphere status")
		check(absf(sphere.distance-sphere_distance) < 2e-5, "Analytic sphere distance")
	for size in [0.0001,1.0,10000.0]:
		var result := GJK.query(box(Vector4.ZERO,Vector4.ONE*size),box(Vector4(3,0,0,0)*size,Vector4.ONE*size))
		check(result.status == "separated" and absf(result.distance-size) < maxf(size*1e-5,1e-7), "Scale invariance")
	print("GJK failures: ",failures)
	quit(1 if failures else 0)
