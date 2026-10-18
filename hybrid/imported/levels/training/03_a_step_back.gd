extends RefCounted
const B = preload("res://hybrid/imported/scripts/campaign/chamber_builder.gd")
static func build() -> Dictionary:
	var start := Vector4(0, 0, 0, 0)
	var route := [Vector4(0, 0, 0, 3), Vector4(-3, 0, 0, 3), Vector4(-3, 0, 2.5, 3), Vector4(3, 0, 2.5, 3)]
	var tunnels := []
	var previous := start
	for point in route:
		tunnels.append(B.tube(previous, point))
		previous = point
	return {
		"title": "A STEP BACK", "lesson": "Moving away from the exit can bring you closer to the route.",
		"start": start, "low": Vector4(-4, -1.2, -1, -0.5), "high": Vector4(4, 1.2, 3.5, 4),
		"goal": route[-1], "modes": [0, 1, 2],
		"solids": B.carve(B.box(Vector4(-4.5, -2, -1.5, -1), Vector4(4.5, 2, 4, 4.5)), tunnels),
		"route": route, "route_modes": [1, 2, 0, 0],
		"hints": ["The exit is ahead, but this pocket only opens through W. Find the cyan lift marker.", "Forward is sealed. Try the newly available XYW view: keeping Z fixed lets you move back along X.", "You have reached the return corridor. Restore XYZ to turn around the solid core along Z.", "Now move forward along X. The space you reached by stepping back leads around the obstruction."],
		"details": ["Press 2. Hold D until W = 3, keeping X and Z near zero.", "Press 3 (XYW). Hold A until X = -3; this does not undo your W progress.", "Press 1 (XYZ). Hold S until Z = 2.5, keeping X near -3.", "Stay in XYZ. Hold D until X = 3 and enter the exit."],
		"captions": ["01  /  INTO THE FOURTH DIRECTION", "02  /  STEP BACK IN X", "03  /  AROUND THE CORE", "04  /  FORWARD, SOMEWHERE ELSE"],
		"shell": true,
	}
