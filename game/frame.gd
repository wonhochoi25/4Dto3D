extends RefCounted
## A visible three-axis slice and a downward axis, all in physical 4D coordinates.
const AXIS_NAMES := ["X", "Y", "Z", "W"]
const MODES := [
	{"name": "XYZ", "visible": [0, 1, 2], "hidden": 3},
	{"name": "XZW", "visible": [0, 2, 3], "hidden": 1},
	{"name": "XYW", "visible": [0, 1, 3], "hidden": 2},
	{"name": "YZW", "visible": [1, 2, 3], "hidden": 0},
]
const PRIORITY := [2, 0, 1, 3] # Z > X > Y > W. Gravity always points toward -axis.
var mode := 0
var gravity := 2

static func priority_axis(next_mode: int) -> int:
	for axis in PRIORITY:
		if axis in MODES[next_mode].visible: return axis
	return 2

func axes() -> Array:
	var horizontal: Array = []
	for axis in MODES[mode].visible:
		if axis != gravity: horizontal.append(axis)
	return [horizontal[0], gravity, horizontal[1]]

func to_view(p: Vector4) -> Vector3:
	var rows := axes()
	return Vector3(p[rows[0]], p[rows[1]], p[rows[2]])

func to_world(p: Vector3) -> Vector4:
	var result := Vector4.ZERO
	var rows := axes()
	for i in range(3): result[rows[i]] = p[i]
	return result

func half_size() -> Vector4:
	var half := Vector4.ONE * 0.28
	half[gravity] = 0.85
	return half

func up() -> Vector4:
	var result := Vector4.ZERO
	result[gravity] = 1.0
	return result

func hidden() -> int:
	return MODES[mode].hidden

func description() -> String:
	var rows := axes()
	return "%s  /  gravity -%s\nFloor %s%s  /  hidden %s" % [MODES[mode].name, AXIS_NAMES[gravity], AXIS_NAMES[rows[0]], AXIS_NAMES[rows[2]], AXIS_NAMES[hidden()]]
