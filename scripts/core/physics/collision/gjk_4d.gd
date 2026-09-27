extends RefCounted
## Distance GJK for compact convex support maps in R4. No scene, IO or renderer.
## Support providers expose valid, center, radius, and support(double4).
const Simplex = preload("res://scripts/core/physics/collision/simplex_4d.gd")
const Vertices = preload("res://scripts/core/physics/collision/convex_vertices_4d.gd")
const ABS_TOLERANCE := 1e-7
const REL_TOLERANCE := 1e-6

static func unknown(reason: String) -> Dictionary:
	return {"status":"indeterminate","reason":reason,"iterations":0,"distance":null,"converged":false,"simplex":[]}

static func difference(a, b, direction: PackedFloat64Array, scale: float) -> Dictionary:
	var opposite := direction.duplicate()
	for i in range(4): opposite[i] = -opposite[i]
	var pa: PackedFloat64Array = a.support(direction)
	var pb: PackedFloat64Array = b.support(opposite)
	var point := PackedFloat64Array([0,0,0,0])
	for i in range(4): point[i] = (pa[i]-pb[i])/scale
	return {"point":point,"a":pa,"b":pb}

static func query(a, b, max_iterations: int = 64) -> Dictionary:
	if not a.valid or not b.valid: return unknown("Empty or nonfinite collider")
	var scale: float = maxf(a.radius+b.radius, 1e-12)
	var tolerance: float = ABS_TOLERANCE + REL_TOLERANCE*scale
	var epsilon: float = tolerance/scale
	var direction := PackedFloat64Array([0,0,0,0])
	for i in range(4): direction[i] = b.center[i]-a.center[i]
	if Simplex.dot(direction,direction) == 0: direction[0] = 1
	var simplex: Array = [difference(a,b,direction,scale)]
	var lower := 0.0
	var certificate := PackedFloat64Array()
	var solution := {}
	for iteration in range(max_iterations):
		var points: Array = []
		for vertex in simplex: points.append(vertex.point)
		solution = Simplex.closest(points)
		if solution.is_empty(): return unknown("Simplex solver failed")
		var reduced: Array = []
		for index in solution.indices: reduced.append(simplex[index])
		simplex = reduced
		var q: PackedFloat64Array = solution.point
		var upper := sqrt(solution.squared)
		if upper <= epsilon:
			return finish(a,b,simplex,solution,scale,tolerance,0.0,"intersecting","Within contact tolerance",iteration+1,true,certificate)
		for i in range(4): direction[i] = -q[i]/upper
		var next := difference(a,b,direction,scale)
		var bound := Simplex.dot(q,next.point)/upper
		if bound > lower:
			lower = bound
			certificate = direction.duplicate()
		if lower > upper + epsilon: return unknown("Inconsistent numerical distance bounds")
		if upper-lower <= epsilon:
			var status := "separated" if lower > epsilon else "indeterminate"
			return finish(a,b,simplex,solution,scale,tolerance,lower,status,"Distance bounds converged",iteration+1,true,certificate)
		var duplicate := false
		for old in simplex:
			var squared := 0.0
			for i in range(4): squared += (old.point[i]-next.point[i]) ** 2
			if squared <= 1e-24: duplicate = true
		if duplicate or simplex.size() >= 5:
			var status := "separated" if lower > epsilon else "indeterminate"
			return finish(a,b,simplex,solution,scale,tolerance,lower,status,"Support/simplex stalled",iteration+1,false,certificate)
		simplex.append(next)
	# Do not attach stale weights to a simplex changed by the final iteration.
	if solution.is_empty(): return unknown("Iteration limit")
	var points: Array = []
	for vertex in simplex: points.append(vertex.point)
	solution = Simplex.closest(points)
	var reduced: Array = []
	for index in solution.indices: reduced.append(simplex[index])
	return finish(a,b,reduced,solution,scale,tolerance,lower,"separated" if lower > epsilon else "indeterminate","Iteration limit",max_iterations,false,certificate)

static func finish(a,b,simplex: Array, solution: Dictionary, scale: float, tolerance: float, lower: float, status: String, reason: String, iterations: int, converged: bool, certificate: PackedFloat64Array) -> Dictionary:
	var pa := PackedFloat64Array([0,0,0,0])
	var pb := PackedFloat64Array([0,0,0,0])
	for j in range(simplex.size()):
		for i in range(4):
			pa[i] += solution.weights[j]*simplex[j].a[i]
			pb[i] += solution.weights[j]*simplex[j].b[i]
	var distance := sqrt(solution.squared)*scale
	var result := {"status":status,"reason":reason,"iterations":iterations,"converged":converged,"distance":distance,"distance_lower":maxf(0.0,lower)*scale,"tolerance":tolerance,"point_a":pa,"point_b":pb,"simplex":simplex,"simplex_scale":scale,"weights":solution.weights,"direction":null}
	if status == "separated" and distance > 0:
		var direction: PackedFloat64Array = certificate.duplicate()
		if direction.is_empty():
			direction = solution.point.duplicate()
			for i in range(4): direction[i] *= -scale/distance
		var opposite := direction.duplicate()
		for i in range(4): opposite[i] = -opposite[i]
		# Center interval coordinates on A to avoid cancellation in the inspector.
		var origin: PackedFloat64Array = a.center
		var intervals := []
		for collider in [a,b]:
			var low: PackedFloat64Array = collider.support(opposite)
			var high: PackedFloat64Array = collider.support(direction)
			var lo := 0.0
			var hi := 0.0
			for i in range(4):
				lo += (low[i]-origin[i])*direction[i]
				hi += (high[i]-origin[i])*direction[i]
			intervals.append(Vector2(lo,hi))
		result.direction = direction
		result.intervals = intervals
		result.gap = intervals[1].x-intervals[0].y
	return result
