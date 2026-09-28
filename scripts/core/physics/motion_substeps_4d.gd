extends RefCounted
## Conservative travel budget for discrete convex collision sampling, not a TOI solver.
## Accounts for translation, rotation and prescribed geometry changes at sample endpoints.
const Bounds=preload("res://scripts/core/physics/broad_phase_4d.gd")
const Math4D=preload("res://scripts/core/math/transform_4d.gd")
const Box=preload("res://scripts/core/physics/contact_manifold_4d.gd")
static func required(previous: Dictionary,current: Dictionary,types: Dictionary,fraction: float=0.2,states: Dictionary={},dt: float=1.0/60.0) -> int:
	var sweep: Dictionary={}
	var travel: Dictionary={}
	var width: Dictionary={}
	for id in current:
		if not previous.has(id): continue
		var a:=Bounds.bounds(previous[id]);var b:=Bounds.bounds(current[id])
		var lo: Vector4=a.low;var hi: Vector4=a.high
		for k in range(4): lo[k]=minf(lo[k],b.low[k]);hi[k]=maxf(hi[k],b.high[k])
		sweep[id]={"low":lo,"high":hi}
		var motion:=0.0
		for v in current[id].geometry.vertices:
			motion=maxf(motion,(Math4D.apply(current[id].world,v)-Math4D.apply(previous[id].world,v)).length())
		var angular_travel:=0.0
		if states.has(id):
			var state: PackedFloat64Array=states[id]
			var center:=Vector4(state[0]+state[30],state[1]+state[31],state[2]+state[32],state[3]+state[33])
			var radius:=0.0
			for v in previous[id].geometry.vertices: radius=maxf(radius,(Math4D.apply(previous[id].world,v)-center).length())
			for k in range(6): angular_travel+=absf(deg_to_rad(state[24+k]))*radius*dt
			var linear:=Vector4(state[4],state[5],state[6],state[7]).length()*dt
			motion=maxf(motion,linear+angular_travel)
		if angular_travel>0:
			for k in range(4): sweep[id].low[k]-=angular_travel;sweep[id].high[k]+=angular_travel
		travel[id]=motion
		var thickness:=INF
		var box:=Box.box(previous[id])
		if not box.is_empty():
			for k in range(4):
				var positive: Dictionary=box.planes[2*k];var negative: Dictionary=box.planes[2*k+1]
				thickness=minf(thickness,(positive.b+negative.b)/positive.n.length())
		else:
			for k in range(4):
				if a.high[k]-a.low[k]>1e-6: thickness=minf(thickness,a.high[k]-a.low[k])
		width[id]=maxf(0.0001,thickness)
	var steps:=1
	var ids:=sweep.keys()
	for i in range(ids.size()):
		for j in range(i+1,ids.size()):
			var a=ids[i];var b=ids[j]
			if types.get(a)!="dynamic" and types.get(b)!="dynamic": continue
			if not Bounds.overlap(sweep[a],sweep[b]): continue
			# The moving dynamic body's size limits how far it may advance through a thin wall.
			var size: float=width[a] if types.get(a)=="dynamic" else width[b]
			if types.get(a)=="dynamic" and types.get(b)=="dynamic": size=minf(size,width[b])
			steps=maxi(steps,int(ceil((travel[a]+travel[b])/(fraction*size))))
	return steps
