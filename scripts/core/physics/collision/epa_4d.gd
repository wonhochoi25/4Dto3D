extends RefCounted
## Expanding polytope penetration query in R4. No movement or collision response.
## Facets are tetrahedra; their triangular ridges form the expansion horizon.
const GJK = preload("res://scripts/core/physics/collision/gjk_4d.gd")
const Simplex = preload("res://scripts/core/physics/collision/simplex_4d.gd")
const HULL_EPS := 1e-10
const MAX_FACETS := 4096

static func unresolved(reason: String, iterations: int = 0) -> Dictionary:
	return {"status":"indeterminate", "reason":reason, "iterations":iterations, "converged":false}

static func subtract(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var p := a.duplicate()
	for i in range(4): p[i] -= b[i]
	return p

static func determinant3(m: Array) -> float:
	return m[0][0]*(m[1][1]*m[2][2]-m[1][2]*m[2][1])-m[0][1]*(m[1][0]*m[2][2]-m[1][2]*m[2][0])+m[0][2]*(m[1][0]*m[2][1]-m[1][1]*m[2][0])

static func facet(ids: Array, vertices: Array, interior: PackedFloat64Array) -> Dictionary:
	var base: PackedFloat64Array = vertices[ids[0]].point
	var edges := []
	for j in range(1,4): edges.append(subtract(vertices[ids[j]].point,base))
	var normal := PackedFloat64Array([0,0,0,0])
	for k in range(4):
		var minor := []
		for edge in edges:
			var row := []
			for c in range(4):
				if c != k: row.append(edge[c])
			minor.append(row)
		normal[k] = determinant3(minor)*(1.0 if k%2 == 0 else -1.0)
	var length := sqrt(Simplex.dot(normal,normal))
	if length < 1e-14: return {}
	for k in range(4): normal[k] /= length
	if Simplex.dot(normal,subtract(interior,base)) > 0:
		for k in range(4): normal[k] = -normal[k]
	return {"ids":ids, "normal":normal, "distance":Simplex.dot(normal,base)}

static func append_unique(vertices: Array, v: Dictionary) -> int:
	for i in range(vertices.size()):
		var d := subtract(vertices[i].point,v.point)
		if Simplex.dot(d,d) < 1e-22: return i
	vertices.append(v)
	return vertices.size()-1

## Replace visible facets with tetrahedra joining the new vertex to horizon triangles.
## Build transactionally: a degenerate horizon never leaves a partially updated hull.
static func expand(faces: Array, vertices: Array, index: int, interior: PackedFloat64Array) -> Dictionary:
	var kept := []
	var ridges := {}
	var visible := 0
	for f in faces:
		if Simplex.dot(f.normal,vertices[index].point)-f.distance <= HULL_EPS:
			kept.append(f)
			continue
		visible += 1
		for omit in range(4):
			var ids := []
			for j in range(4):
				if j != omit: ids.append(f.ids[j])
			ids.sort()
			var key := str(ids)
			if ridges.has(key): ridges.erase(key)
			else: ridges[key] = ids
	if visible == 0: return {"ok":true,"faces":faces,"changed":false}
	for ridge in ridges.values():
		var ids: Array = ridge.duplicate()
		ids.append(index)
		var f := facet(ids,vertices,interior)
		if f.is_empty(): return {"ok":false}
		kept.append(f)
	if kept.size() > MAX_FACETS or ridges.is_empty() or not closed_hull(kept): return {"ok":false}
	return {"ok":true,"faces":kept,"changed":true}

## Every triangular ridge must belong to exactly two boundary tetrahedra.
static func closed_hull(faces: Array) -> bool:
	var counts := {}
	for f in faces:
		for omit in range(4):
			var ids := []
			for j in range(4):
				if j != omit: ids.append(f.ids[j])
			ids.sort()
			var key := str(ids)
			counts[key] = counts.get(key,0)+1
	for count in counts.values():
		if count != 2: return false
	return true

static func query(a, b, gjk_result: Dictionary, max_iterations: int = 192) -> Dictionary:
	if gjk_result.get("status","") != "intersecting": return unresolved("EPA requires a GJK contact result")
	if not a.valid or not b.valid: return unresolved("Invalid collider")
	var scale: float = maxf(a.radius+b.radius,1e-12)
	var tolerance: float = GJK.ABS_TOLERANCE+GJK.REL_TOLERANCE*scale
	var epsilon: float = tolerance/scale
	var vertices := []
	# Reuse witnesses, recomputing normalization rather than trusting external scale.
	for v in gjk_result.simplex:
		var p := subtract(v.a,v.b)
		for k in range(4): p[k] /= scale
		append_unique(vertices,{"point":p,"a":v.a,"b":v.b})
	# GJK often stops on a segment even for deep overlap. Seed a full-dimensional hull.
	for axis in range(4):
		for sign_value in [-1.0,1.0]:
			var n := PackedFloat64Array([0,0,0,0])
			n[axis] = sign_value
			append_unique(vertices,GJK.difference(a,b,n,scale))
	for mask in range(16):
		var n := PackedFloat64Array([0,0,0,0])
		for k in range(4): n[k] = 1.0 if mask & (1<<k) else -1.0
		append_unique(vertices,GJK.difference(a,b,n,scale))
	# Pick an affine-independent 4-simplex using farthest residuals / Gram-Schmidt.
	var seed := [0]
	var basis := []
	for dimension in range(4):
		var best := -1
		var best_length := 0.0
		var best_residual := PackedFloat64Array()
		for i in range(vertices.size()):
			var residual := subtract(vertices[i].point,vertices[0].point)
			for repeat in range(2):
				for q in basis:
					var coefficient := Simplex.dot(residual,q)
					for k in range(4): residual[k] -= coefficient*q[k]
			var length := Simplex.dot(residual,residual)
			if length > best_length:
				best = i
				best_length = length
				best_residual = residual
		if best_length < 1e-20: return unresolved("Collider difference is lower-dimensional; no full 4D EPA seed")
		seed.append(best)
		for k in range(4): best_residual[k] /= sqrt(best_length)
		basis.append(best_residual)
	var interior := PackedFloat64Array([0,0,0,0])
	for i in seed:
		for k in range(4): interior[k] += vertices[i].point[k]/5.0
	var faces := []
	for omit in range(5):
		var ids := []
		for j in range(5):
			if j != omit: ids.append(seed[j])
		var f := facet(ids,vertices,interior)
		if f.is_empty(): return unresolved("Degenerate seed facet")
		faces.append(f)
	for i in range(vertices.size()):
		if i in seed: continue
		var expanded := expand(faces,vertices,i,interior)
		if not expanded.ok: return unresolved("Seed hull expansion failed")
		faces = expanded.faces
	for iteration in range(max_iterations):
		var nearest: Dictionary = faces[0]
		for f in faces:
			if f.distance < nearest.distance: nearest = f
		var next := GJK.difference(a,b,nearest.normal,scale)
		var upper := Simplex.dot(nearest.normal,next.point)
		var lower: float = nearest.distance
		if not is_finite(upper) or upper < lower-epsilon: return unresolved("Inconsistent support bound",iteration+1)
		# Negative lower means seed still excludes origin: keep expanding to enclose it.
		if lower >= -epsilon and upper-lower <= epsilon:
			return finish(faces,vertices,nearest,scale,tolerance,upper,iteration+1)
		var before := vertices.size()
		var index := append_unique(vertices,next)
		if index < before: return unresolved("Duplicate support before convergence",iteration+1)
		var expanded := expand(faces,vertices,index,interior)
		if not expanded.ok or not expanded.changed: return unresolved("Hull expansion stalled or exceeded facet budget",iteration+1)
		faces = expanded.faces
	return unresolved("EPA iteration limit",max_iterations)

static func finish(faces: Array, vertices: Array, nearest: Dictionary, scale: float, tolerance: float, upper: float, iterations: int) -> Dictionary:
	var solution := {}
	var chosen := {}
	var best := INF
	# Coplanar tetrahedra partition a flat facet. Locate the one containing its foot.
	for f in faces:
		if absf(f.distance-nearest.distance)*scale > tolerance: continue
		if Simplex.dot(f.normal,nearest.normal) < 1.0-1e-7: continue
		var points := []
		for i in f.ids: points.append(vertices[i].point)
		var candidate := Simplex.closest(points)
		if not candidate.is_empty() and candidate.squared < best:
			best = candidate.squared
			solution = candidate
			chosen = f
	if solution.is_empty() or sqrt(best)*scale > maxf(0.0,nearest.distance)*scale+2*tolerance:
		return unresolved("Could not recover facet witnesses",iterations)
	var pa := PackedFloat64Array([0,0,0,0])
	var pb := pa.duplicate()
	for j in range(solution.indices.size()):
		var v: Dictionary = vertices[chosen.ids[solution.indices[j]]]
		for k in range(4):
			pa[k] += solution.weights[j]*v.a[k]
			pb[k] += solution.weights[j]*v.b[k]
	var depth := maxf(0.0,nearest.distance)*scale
	var translation: PackedFloat64Array = nearest.normal.duplicate()
	for k in range(4): translation[k] *= depth
	return {"status":"touching" if upper*scale <= tolerance else "penetrating","converged":true,"reason":"Penetration bounds converged","iterations":iterations,"depth":depth,"depth_lower":depth,"depth_upper":maxf(depth,upper*scale),"direction":nearest.normal,"translation_b":translation,"point_a":pa,"point_b":pb,"tolerance":tolerance}
