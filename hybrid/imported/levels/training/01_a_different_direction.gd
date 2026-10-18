extends RefCounted
const B = preload("res://hybrid/imported/scripts/campaign/chamber_builder.gd")
static func build() -> Dictionary:
	return {
		"title": "A DIFFERENT DIRECTION", "lesson": "A view changes what you can move through.",
		"start": Vector4(-2.5, 0, 0, 0), "low": Vector4(-4, -1.2, -2.5, -0.5), "high": Vector4(4, 1.2, 2.5, 4),
		"goal": Vector4(2.5, 0, 0, 3), "modes": [0, 1],
		"solids": B.wall(0, 0, 3),
		"route": [Vector4(-2.5, 0, 0, 3), Vector4(2.5, 0, 0, 3)],
		"route_modes": [1, 0],
		"hints": ["The wall blocks X, but it does not block every direction. Select YZW to make W available.", "Same wall, different slice. Return to XYZ and look for the opening."],
		"details": ["Press 2, then hold D until W is near 3. Y and Z can stay at zero.", "Press 1, then hold D toward X = 2.5. Enter the gold exit."],
		"captions": ["01  /  DISCOVER W", "02  /  THROUGH THE WALL"],
		"shell": false,
	}
