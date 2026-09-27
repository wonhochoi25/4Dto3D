extends SceneTree
const EPA = preload("res://scripts/core/physics/collision/epa_4d.gd")
const GJK = preload("res://scripts/core/physics/collision/gjk_4d.gd")
const Collider = preload("res://scripts/core/physics/collision/convex_vertices_4d.gd")
const Math4D = preload("res://scripts/core/math/transform_4d.gd")
const Box = preload("res://scripts/core/geometry/generators/tesseract.gd")
var failures := 0
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		push_error(label)
func box(position: Vector4, size: Vector4 = Vector4.ONE):
	var t := Math4D.new()
	t.position = position
	t.scale = size
	return Collider.new(Box.new().vertices,t.matrix())
func query(a,b): return EPA.query(a,b,GJK.query(a,b))
func _initialize(): call_deferred("verify")
func verify():
	var a = box(Vector4.ZERO)
	for w in [0.0,0.5,1.0,1.9,2.0]:
		var r = query(a,box(Vector4(0,0,0,w)))
		check(r.get("converged",false),"Converged W %.2f"%w)
		if r.get("converged",false): check(absf(r.depth-(2-w)) < 1e-4,"Analytic depth")
	var rng := RandomNumberGenerator.new()
	rng.seed = 48012
	for test in range(60):
		var delta := Vector4(rng.randf_range(-1.8,1.8),rng.randf_range(-1.8,1.8),rng.randf_range(-1.8,1.8),rng.randf_range(-1.8,1.8))
		var expected := 2.0
		for k in range(4): expected = minf(expected,2.0-absf(delta[k]))
		var rigid := Math4D.new()
		for plane in range(6): rigid.angles[plane] = rng.randf_range(-180,180)
		rigid.position = Vector4(5,-2,4,1)
		var ca = Collider.new(Box.new().vertices,rigid.matrix())
		var cb = Collider.new(Box.new().vertices,Math4D.multiply(rigid.matrix(),Math4D.translation(delta)))
		var r = query(ca,cb)
		check(r.get("converged",false),"Rotated case %d: %s" % [test,r])
		if not r.get("converged",false): continue
		check(absf(r.depth-expected)<2e-4,"Rotated analytic depth")
		var swap = query(cb,ca)
		check(swap.get("converged",false) and absf(swap.get("depth",0)-r.depth)<2e-4,"Swap depth")
		if swap.get("converged",false):
			check(Simplex_dot(r.direction,swap.direction)<-0.999,"Swap direction for unique minimum")
		var translated = cb.points.duplicate(true)
		for point in translated:
			for k in range(4): point[k] += r.direction[k]*(r.depth+1e-3)
		cb.points = translated
		for k in range(4): cb.center[k] += r.direction[k]*(r.depth+1e-3)
		check(GJK.query(ca,cb).status=="separated","EPA translation separates")
		var difference := EPA.subtract(r.point_a,r.point_b)
		check(sqrt(Simplex_dot(EPA.subtract(difference,r.translation_b),EPA.subtract(difference,r.translation_b)))<2e-4,"Witness difference matches translation")
	# Independent XW rotation: analytic SAT normals for the product of a 2D box and Y/Z intervals.
	for test in range(60):
		var theta := rng.randf_range(-1.5,1.5)
		var c := cos(theta)
		var sn := sin(theta)
		var matrix := Math4D.identity()
		matrix[0] = c
		matrix[3] = -sn
		matrix[15] = sn
		matrix[18] = c
		matrix[4] = rng.randf_range(-1,1)
		matrix[19] = rng.randf_range(-1,1)
		var cb = Collider.new(Box.new().vertices,matrix)
		var expected := INF
		for n in [PackedFloat64Array([1,0,0,0]),PackedFloat64Array([0,1,0,0]),PackedFloat64Array([0,0,1,0]),PackedFloat64Array([0,0,0,1]),PackedFloat64Array([c,0,0,sn]),PackedFloat64Array([-sn,0,0,c])]:
			var negative: PackedFloat64Array = n.duplicate()
			for k in range(4): negative[k] = -negative[k]
			expected = minf(expected,Simplex_dot(n,a.support(n))-Simplex_dot(n,cb.support(negative)))
			expected = minf(expected,Simplex_dot(n,cb.support(n))-Simplex_dot(n,a.support(negative)))
		var r = query(a,cb)
		check(r.get("converged",false) and absf(r.get("depth",-10)-expected)<2e-4,"Independent rotated SAT oracle: %s"%r)
	# Shared shear preserves convexity but not perpendicular box edges.
	var shear := Math4D.identity()
	shear[3] = 0.5
	var sheared = Collider.new(Box.new().vertices,shear)
	var shear_result = query(sheared,sheared)
	check(shear_result.get("converged",false) and absf(shear_result.get("depth",0)-2.0/sqrt(1.25))<1e-4,"Shared shear depth")
	var containment = query(a,box(Vector4.ZERO,Vector4.ONE*0.2))
	check(containment.get("converged",false) and absf(containment.get("depth",0)-1.2)<1e-4,"Containment uses exit distance")
	var flat = box(Vector4.ZERO,Vector4(1,1,0,0))
	check(query(flat,flat).status=="indeterminate","Lower dimensional explicit")
	check(EPA.query(a,a,GJK.query(a,a),0).status=="indeterminate","Iteration cap explicit")
	check(query(a,box(Vector4(5,0,0,0))).status=="indeterminate","Separated input rejected")
	for size in [0.0001,10000.0]:
		var r = query(box(Vector4.ZERO,Vector4.ONE*size),box(Vector4(0,0,0,size),Vector4.ONE*size))
		check(r.get("converged",false) and absf(r.get("depth",0)-size)<maxf(1e-7,size*1e-5),"Scale invariant")
	print("EPA failures: ",failures)
	quit(1 if failures else 0)

func Simplex_dot(a,b): return preload("res://scripts/core/physics/collision/simplex_4d.gd").dot(a,b)
