extends RefCounted
## Sweep-and-prune on X, with all four axes checked. Conservative world-space bounds.
const Math4D=preload("res://scripts/core/math/transform_4d.gd")
static func bounds(collider: Dictionary) -> Dictionary:
	var low:=Vector4(INF,INF,INF,INF);var high:=-low
	for p in collider.geometry.vertices:
		var v:=Math4D.apply(collider.world,p)
		for k in range(4): low[k]=minf(low[k],v[k]);high[k]=maxf(high[k],v[k])
	return {"low":low,"high":high}
static func overlap(a: Dictionary,b: Dictionary,margin: float=0.005) -> bool:
	for k in range(4):
		if a.low[k]>b.high[k]+margin or b.low[k]>a.high[k]+margin: return false
	return true
static func candidates(colliders: Dictionary,margin: float=0.005) -> Dictionary:
	var entries:=[]
	for id in colliders: entries.append({"id":id,"bounds":bounds(colliders[id])})
	entries.sort_custom(func(a,b): return a.bounds.low.x<b.bounds.low.x if a.bounds.low.x!=b.bounds.low.x else a.id<b.id)
	var pairs: Dictionary={}
	for i in range(entries.size()):
		for j in range(i+1,entries.size()):
			if entries[j].bounds.low.x>entries[i].bounds.high.x+margin: break
			if overlap(entries[i].bounds,entries[j].bounds,margin): pairs[Vector2i(mini(entries[i].id,entries[j].id),maxi(entries[i].id,entries[j].id))]=true
	return pairs
