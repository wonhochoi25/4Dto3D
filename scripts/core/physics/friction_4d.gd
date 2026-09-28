extends RefCounted
## Isotropic Coulomb friction in the three-dimensional tangent space.
const Linear=preload("res://scripts/core/math/linear_solve.gd")
const Angular=preload("res://scripts/core/physics/angular_response_4d.gd")
static func setup(world,a: int,b: int,point: Variant,n: Vector4,linear_weight: float) -> Dictionary:
	var mu: float=sqrt(world.motion_settings.get(a,{}).get("friction",0.0)*world.motion_settings.get(b,{}).get("friction",0.0))
	if mu==0: return {"mu":0.0}
	var basis: Array[Vector4]=[]
	for axis in range(4):
		var v:=Vector4.ZERO;v[axis]=1;v-=n*v.dot(n)
		for tangent in basis: v-=tangent*v.dot(tangent)
		if v.length_squared()>1e-8: basis.append(v.normalized())
		if basis.size()==3: break
	var matrix:=PackedFloat64Array()
	matrix.resize(9)
	for i in range(3):
		for j in range(3):
			matrix[i*3+j]=linear_weight if i==j else 0.0
	if point!=null:
		for id in [a,b]:
			var inverse=world.inverse_inertia_world(id)
			var arm: Vector4=point-world.center_of_mass(id)
			for i in range(3):
				var ki:=Angular.moment(arm,basis[i])
				for j in range(3):
					var response:=Angular.multiply(inverse,Angular.moment(arm,basis[j]))
					for k in range(6): matrix[i*3+j]+=ki[k]*response[k]
	return {"mu":mu,"basis":basis,"matrix":matrix,"total":Vector3.ZERO}
static func update(state: Dictionary,relative: Vector4,normal_impulse: float) -> Dictionary:
	var rhs:=PackedFloat64Array()
	for tangent in state.basis: rhs.append(-relative.dot(tangent))
	var delta:=Linear.solve(state.matrix,rhs)
	if delta.is_empty(): return {"impulse":Vector4.ZERO,"total":state.total}
	var candidate: Vector3=state.total+Vector3(delta[0],delta[1],delta[2])
	var limit: float=state.mu*normal_impulse
	if candidate.length()>limit: candidate=candidate.normalized()*limit
	var change: Vector3=candidate-state.total
	var impulse:=Vector4.ZERO
	for i in range(3): impulse+=state.basis[i]*change[i]
	return {"impulse":impulse,"total":candidate}
