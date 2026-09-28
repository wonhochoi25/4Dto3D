extends RefCounted
## Exact candidate-axis SAT for affine 4D boxes: facets of their Minkowski zonotope
## have normals orthogonal to triples chosen from the eight edge generators.
const Box=preload("res://scripts/core/physics/contact_manifold_4d.gd")
static func determinant(a: Vector3,b: Vector3,c: Vector3) -> float:
	return a.dot(b.cross(c))
static func normal(a: Vector4,b: Vector4,c: Vector4) -> Vector4:
	var result:=Vector4.ZERO
	for omitted in range(4):
		var rows: Array[Vector3]=[]
		for v in [a,b,c]:
			var values:=[]
			for i in range(4):
				if i!=omitted: values.append(v[i])
			rows.append(Vector3(values[0],values[1],values[2]))
		result[omitted]=determinant(rows[0],rows[1],rows[2])*(1 if omitted%2==0 else -1)
	return result
static func interval(points: Array,n: Vector4) -> Vector2:
	var result:=Vector2(INF,-INF)
	for p in points: result.x=minf(result.x,n.dot(p));result.y=maxf(result.y,n.dot(p))
	return result
static func witness(points: Array,n: Vector4,maximum: bool) -> Vector4:
	var bound:=interval(points,n)
	var value: float=bound.y if maximum else bound.x
	var sum:=Vector4.ZERO;var count:=0
	for p in points:
		if absf(n.dot(p)-value)<0.00001: sum+=p;count+=1
	return sum/maxi(1,count)
static func query(a: Dictionary,b: Dictionary,options: Dictionary) -> Dictionary:
	var ba:=Box.box(a);var bb:=Box.box(b)
	if ba.is_empty() or bb.is_empty(): return {}
	var edges: Array[Vector4]=[]
	for collider in [a,b]:
		for k in range(4):
			var m: PackedFloat64Array=collider.world
			edges.append(Vector4(m[k],m[5+k],m[10+k],m[15+k]).normalized())
	var best_gap: float=-INF;var best:=Vector4.ZERO
	for i in range(8):
		for j in range(i+1,8):
			for k in range(j+1,8):
				var n:=normal(edges[i],edges[j],edges[k])
				if n.length_squared()<1e-12: continue
				n=n.normalized()
				var ia:=interval(ba.points,n);var ib:=interval(bb.points,n)
				var gap: float=ib.x-ia.y
				if ia.x-ib.y>gap: gap=ia.x-ib.y;n=-n
				if gap>best_gap: best_gap=gap;best=n
	if not is_finite(best_gap): return {}
	var direction:=PackedFloat64Array([best.x,best.y,best.z,best.w])
	var pa:=witness(ba.points,best,true);var pb:=witness(bb.points,best,false)
	var result: Dictionary={"status":"separated" if best_gap>0.000001 else "intersecting","reason":"Affine-box SAT","direction":direction,"gap":maxf(0,best_gap),"point_a":pa,"point_b":pb,"diagnostics":{"backend":"Affine-box SAT"}}
	if result.status=="separated":
		var center:=Vector4.ZERO
		for p in ba.points: center+=p/16.0
		var ia:=interval(ba.points,best);var ib:=interval(bb.points,best)
		var origin:=center.dot(best)
		result.intervals=[Vector2(ia.x-origin,ia.y-origin),Vector2(ib.x-origin,ib.y-origin)]
		result.interval_origin=PackedFloat64Array([center.x,center.y,center.z,center.w])
		result.distance_lower=best_gap
		result.distance=(pb-pa).length()
	if result.status=="intersecting" and options.get("include_penetration",false):
		result.penetration={"status":"penetrating" if best_gap< -0.000001 else "touching","converged":true,"depth":maxf(0,-best_gap),"direction":direction,"point_a":pa,"point_b":pb,"translation_b":PackedFloat64Array([best.x*maxf(0,-best_gap),best.y*maxf(0,-best_gap),best.z*maxf(0,-best_gap),best.w*maxf(0,-best_gap)])}
	return result
