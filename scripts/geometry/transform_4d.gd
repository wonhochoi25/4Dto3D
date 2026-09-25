extends RefCounted
## Column-vector homogeneous PRSA. Matrices are row-major arrays of 25 floats.
## Rotation angles are degrees, applied XY, XZ, XW, YZ, YW, ZW in that order.
const PLANES = [Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(1, 2), Vector2i(1, 3), Vector2i(2, 3)]
var position := Vector4.ZERO
var anchor := Vector4.ZERO
var scale := Vector4.ONE
var angles := PackedFloat64Array([0, 0, 0, 0, 0, 0])
var keep_in_place := true
var uniform_scale := false

static func identity() -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(25)
	for i in range(5): result[i * 5 + i] = 1
	return result

static func multiply(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(25)
	for row in range(5):
		for column in range(5):
			for k in range(5):
				result[row * 5 + column] += a[row * 5 + k] * b[k * 5 + column]
	return result

static func translation(offset: Vector4) -> PackedFloat64Array:
	var result := identity()
	for axis in range(4): result[axis * 5 + 4] = offset[axis]
	return result

## homogeneous=0 transforms a direction; homogeneous=1 transforms a point.
static func apply(matrix: PackedFloat64Array, point: Vector4, homogeneous: float = 1.0) -> Vector4:
	var result := Vector4.ZERO
	for row in range(4):
		result[row] = matrix[row * 5 + 4] * homogeneous
		for column in range(4):
			result[row] += matrix[row * 5 + column] * point[column]
	return result

func scaling_matrix() -> PackedFloat64Array:
	var result := identity()
	for axis in range(4): result[axis * 5 + axis] = scale[axis]
	return result

func rotation_matrix() -> PackedFloat64Array:
	var result := identity()
	for i in range(6):
		var plane: Vector2i = PLANES[i]
		var rotation := identity()
		var angle := deg_to_rad(angles[i])
		rotation[plane.x * 5 + plane.x] = cos(angle)
		rotation[plane.y * 5 + plane.y] = cos(angle)
		rotation[plane.x * 5 + plane.y] = -sin(angle)
		rotation[plane.y * 5 + plane.x] = sin(angle)
		result = multiply(rotation, result)
	return result

func matrix() -> PackedFloat64Array:
	return multiply(multiply(multiply(translation(position), rotation_matrix()), scaling_matrix()), translation(-anchor))

## Move the pivot while preserving every transformed point when compensation is enabled.
func set_anchor(value: Vector4) -> void:
	if keep_in_place:
		position += apply(multiply(rotation_matrix(), scaling_matrix()), value - anchor, 0)
	anchor = value

func transform_vertices(vertices: Array[Vector4]) -> Array[Vector4]:
	var combined := matrix()
	var result: Array[Vector4] = []
	for point in vertices: result.append(apply(combined, point))
	return result

func reset() -> void:
	position = Vector4.ZERO
	anchor = Vector4.ZERO
	scale = Vector4.ONE
	angles.fill(0)
