extends RefCounted
## World-plane bivectors in XY,XZ,XW,YZ,YW,ZW order. Physics algebra uses radians.
const Math4D=preload("res://scripts/core/math/transform_4d.gd")
static func moment(arm: Vector4, impulse: Vector4) -> PackedFloat64Array:
	var result:=PackedFloat64Array()
	for axes in Math4D.PLANES: result.append(arm[axes.x]*impulse[axes.y]-arm[axes.y]*impulse[axes.x])
	return result

static func multiply(matrix: PackedFloat64Array, vector: PackedFloat64Array) -> PackedFloat64Array:
	var result:=PackedFloat64Array([0,0,0,0,0,0])
	if matrix.size()!=36: return result
	for i in range(6):
		for j in range(6): result[i]+=matrix[i*6+j]*vector[j]
	return result

static func surface_velocity(arm: Vector4, angular_radians: PackedFloat64Array) -> Vector4:
	var result:=Vector4.ZERO
	for i in range(6):
		var axes: Vector2i=Math4D.PLANES[i]
		result[axes.x]-=angular_radians[i]*arm[axes.y]
		result[axes.y]+=angular_radians[i]*arm[axes.x]
	return result
