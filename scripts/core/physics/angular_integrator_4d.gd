extends RefCounted
## World angular momentum integration with an implicit-midpoint orientation estimate.
## Matrix-exponential rotations preserve orthogonality; final omega is recovered from conserved L.
const Mass=preload("res://scripts/core/physics/mass_properties_4d.gd")
const Math4D=preload("res://scripts/core/math/transform_4d.gd")
const Angular=preload("res://scripts/core/physics/angular_response_4d.gd")
const Linear=preload("res://scripts/core/math/linear_solve.gd")
static func orientation(state: PackedFloat64Array) -> PackedFloat64Array:
	var r:=Math4D.identity()
	for i in range(4):
		for j in range(4): r[i*5+j]=state[8+i*4+j]
	return r
static func increment(omega: PackedFloat64Array,dt: float) -> PackedFloat64Array:
	var skew:=Math4D.identity()
	for i in range(25): skew[i]=0
	var size:=0.0
	for i in range(6): size+=absf(omega[i]*dt)
	var squarings:=maxi(0,int(ceil(log(maxf(1.0,size/0.25))/log(2.0))))
	var scale:=dt/pow(2.0,squarings)
	for i in range(6):
		var p: Vector2i=Math4D.PLANES[i]
		skew[p.x*5+p.y]=-omega[i]*scale
		skew[p.y*5+p.x]=omega[i]*scale
	var result:=Math4D.identity()
	var term:=Math4D.identity()
	for order in range(1,19):
		term=Math4D.multiply(term,skew)
		for i in range(25): term[i]/=order;result[i]+=term[i]
	for iteration in range(squarings): result=Math4D.multiply(result,result)
	return result
static func advance(previous: PackedFloat64Array,state: PackedFloat64Array,properties: Dictionary,dt: float) -> void:
	var r0:=orientation(previous)
	var omega:=PackedFloat64Array()
	for i in range(6): omega.append(deg_to_rad(previous[24+i]))
	var old:=Mass.transformed(properties,r0)
	var momentum:=Angular.multiply(old.inertia,omega)
	var midpoint:=momentum.duplicate()
	for i in range(6):
		momentum[i]+=state[46+i]*dt
		midpoint[i]+=state[46+i]*dt*0.5
	var estimate:=omega.duplicate()
	for iteration in range(8):
		var half:=Math4D.multiply(increment(estimate,dt*0.5),r0)
		var props:=Mass.transformed(properties,half)
		estimate=Angular.multiply(props.inverse_inertia,midpoint)
	var final:=Math4D.multiply(increment(estimate,dt),r0)
	var properties_final:=Mass.transformed(properties,final)
	var final_omega:=Angular.multiply(properties_final.inverse_inertia,momentum)
	for i in range(4):
		for j in range(4): state[8+i*4+j]=final[i*5+j]
	for i in range(6): state[24+i]=rad_to_deg(final_omega[i])
