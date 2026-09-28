extends RefCounted
## Contact-plane intersection of two affine boxes. Not tied to GJK/EPA.
## Other vertex hulls retain their backend witness contact.
const Math4D=preload("res://scripts/core/math/transform_4d.gd")
const Linear=preload("res://scripts/core/math/linear_solve.gd")
static func box(collider: Dictionary) -> Dictionary:
	var vertices=collider.geometry.vertices
	if vertices.size()!=16: return {}
	var low: Vector4=vertices[0]
	var high:=low
	for v in vertices:
		for k in range(4): low[k]=minf(low[k],v[k]);high[k]=maxf(high[k],v[k])
	var masks: Dictionary={}
	for v in vertices:
		var mask:=0
		for k in range(4):
			if high[k]-low[k]<1e-8: return {}
			if absf(v[k]-high[k])<1e-6: mask|=1<<k
			elif absf(v[k]-low[k])>1e-6: return {}
		masks[mask]=true
	if masks.size()!=16: return {}
	var m: PackedFloat64Array=collider.world
	var transpose:=PackedFloat64Array()
	for i in range(4):
		for j in range(4): transpose.append(m[j*5+i])
	var planes: Array=[]
	for k in range(4):
		var unit:=PackedFloat64Array([0,0,0,0]);unit[k]=1
		var row:=Linear.solve(transpose,unit)
		if row.is_empty(): return {}
		var n:=Vector4(row[0],row[1],row[2],row[3])
		var translation:=Vector4(m[4],m[9],m[14],m[19])
		planes.append({"n":n,"b":high[k]+n.dot(translation)})
		planes.append({"n":-n,"b":-low[k]-n.dot(translation)})
	var points: Array[Vector4]=[]
	for v in vertices: points.append(Math4D.apply(m,v))
	return {"planes":planes,"points":points}

static func points(a: Dictionary,b: Dictionary,n: Vector4) -> Array[Vector4]:
	var result: Array[Vector4]=[]
	var ba:=box(a);var bb:=box(b)
	if ba.is_empty() or bb.is_empty(): return result
	var hi: float=-INF;var lo: float=INF
	for v in ba.points: hi=maxf(hi,n.dot(v))
	for v in bb.points: lo=minf(lo,n.dot(v))
	var gap:=lo-hi
	var plane: float=(hi+lo)*0.5
	var planes: Array=[]
	for entry in ba.planes: planes.append({"n":entry.n,"b":entry.b+entry.n.dot(n)*gap*0.5+absf(entry.n.dot(n))*0.005})
	for entry in bb.planes: planes.append({"n":entry.n,"b":entry.b-entry.n.dot(n)*gap*0.5+absf(entry.n.dot(n))*0.005})
	for i in range(planes.size()):
		for j in range(i+1,planes.size()):
			for k in range(j+1,planes.size()):
				var matrix:=PackedFloat64Array()
				for row in [n,planes[i].n,planes[j].n,planes[k].n]:
					for axis in range(4): matrix.append(row[axis])
				var p:=Linear.solve(matrix,PackedFloat64Array([plane,planes[i].b,planes[j].b,planes[k].b]))
				if p.is_empty(): continue
				var v:=Vector4(p[0],p[1],p[2],p[3])
				var inside:=true
				for bound in planes:
					if bound.n.dot(v)>bound.b+0.00001*maxf(1,bound.n.length()): inside=false;break
				if not inside: continue
				for existing in result:
					if (v-existing).length_squared()<1e-8: inside=false;break
				if inside: result.append(v)
	return result

static func attach(reports: Array,colliders: Dictionary) -> void:
	for report in reports:
		if not colliders.has(report.body_a) or not colliders.has(report.body_b): continue
		var r: Dictionary=report.result
		var source: Dictionary=r.get("penetration",{}) if r.get("status")=="intersecting" else r
		if r.get("status")=="intersecting" and not source.get("converged",false): continue
		if r.get("status")=="separated" and r.get("gap",INF)>0.005: continue
		var direction=source.get("direction",[])
		if direction.size()!=4: continue
		var n:=Vector4(direction[0],direction[1],direction[2],direction[3])
		if not n.is_finite() or absf(n.length()-1)>0.001: continue
		var manifold:=points(colliders[report.body_a],colliders[report.body_b],n)
		if not manifold.is_empty(): r.contacts=manifold
