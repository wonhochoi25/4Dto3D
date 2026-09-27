extends RefCounted
## Display-only convex hull. Never replaces the 4D collision geometry.
## Normalize for numerical scale, then incrementally expand a triangular boundary.
const EPS := 1e-6
static func face(a: int,b: int,c: int,p: Array,inside: Vector3) -> Dictionary:
	var n: Vector3 = (p[b]-p[a]).cross(p[c]-p[a]).normalized()
	if n.dot(inside-p[a])>0:
		var swap := b
		b=c
		c=swap
		n=-n
	return {"ids":[a,b,c],"n":n,"d":n.dot(p[a])}

static func build(input: PackedVector3Array) -> Dictionary:
	var result := {"dimension":0,"vertices":PackedVector3Array(),"triangles":[],"edges":[]}
	if input.is_empty(): return result
	var low := input[0]
	var high := low
	for v in input:
		if not v.is_finite(): return result
		low=low.min(v)
		high=high.max(v)
	var center := low*0.5+high*0.5
	var scale := maxf((high-low).length(),1e-12)
	var p := []
	var seen := {}
	for v in input:
		var q := (v-center)/scale
		var key := q.snapped(Vector3.ONE*EPS)
		if seen.has(key): continue
		seen[key]=true
		p.append(q)
		result.vertices.append(v)
	if p.size()<2: return result
	var b := 1
	for i in range(2,p.size()):
		if p[i].distance_squared_to(p[0])>p[b].distance_squared_to(p[0]): b=i
	var u: Vector3 = (p[b]-p[0]).normalized()
	var c := -1
	var best := 0.0
	for i in range(p.size()):
		var area: float = (p[i]-p[0]).cross(u).length_squared()
		if area>best: best=area; c=i
	if best<EPS*EPS:
		result.dimension=1
		var first := 0
		var last := 0
		for i in range(p.size()):
			if u.dot(p[i])<u.dot(p[first]): first=i
			if u.dot(p[i])>u.dot(p[last]): last=i
		result.edges=[[first,last]]
		return result
	var n: Vector3 = (p[b]-p[0]).cross(p[c]-p[0]).normalized()
	var d := -1
	best=0
	for i in range(p.size()):
		var distance: float = absf(n.dot(p[i]-p[0]))
		if distance>best: best=distance; d=i
	if best<EPS:
		result.dimension=2
		var v := n.cross(u)
		var ids := range(p.size())
		ids.sort_custom(func(i,j): return u.dot(p[i])<u.dot(p[j]) if absf(u.dot(p[i]-p[j]))>EPS else v.dot(p[i])<v.dot(p[j]))
		var lower := []
		var upper := []
		for i in ids:
			while lower.size()>1 and n.dot((p[lower[-1]]-p[lower[-2]]).cross(p[i]-p[lower[-1]]))<=EPS: lower.pop_back()
			lower.append(i)
		ids.reverse()
		for i in ids:
			while upper.size()>1 and n.dot((p[upper[-1]]-p[upper[-2]]).cross(p[i]-p[upper[-1]]))<=EPS: upper.pop_back()
			upper.append(i)
		lower.pop_back()
		upper.pop_back()
		lower.append_array(upper)
		for i in range(lower.size()): result.edges.append([lower[i],lower[(i+1)%lower.size()]])
		for i in range(1,lower.size()-1): result.triangles.append([lower[0],lower[i],lower[i+1]])
		return result
	result.dimension=3
	var inside: Vector3 = (p[0]+p[b]+p[c]+p[d])/4
	var faces := [face(0,b,c,p,inside),face(0,d,b,p,inside),face(0,c,d,p,inside),face(b,d,c,p,inside)]
	for i in range(p.size()):
		if i in [0,b,c,d]: continue
		var kept := []
		var horizon := {}
		for f in faces:
			if f.n.dot(p[i])-f.d<=EPS: kept.append(f); continue
			for j in range(3):
				var edge := [f.ids[j],f.ids[(j+1)%3]]
				edge.sort()
				var key := str(edge)
				if horizon.has(key): horizon.erase(key)
				else: horizon[key]=edge
		for edge in horizon.values(): kept.append(face(edge[0],edge[1],i,p,inside))
		faces=kept
	var edge_faces := {}
	for f in faces:
		result.triangles.append(f.ids)
		for j in range(3):
			var edge := [f.ids[j],f.ids[(j+1)%3]]
			edge.sort()
			var key := str(edge)
			if not edge_faces.has(key): edge_faces[key]={"edge":edge,"normal":f.n,"boundary":true}
			else: edge_faces[key].boundary = edge_faces[key].normal.dot(f.n)<1-1e-5
	for edge in edge_faces.values():
		if edge.boundary: result.edges.append(edge.edge)
	return result
