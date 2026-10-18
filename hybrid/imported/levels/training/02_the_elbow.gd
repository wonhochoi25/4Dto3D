extends RefCounted
const B = preload("res://hybrid/imported/scripts/campaign/chamber_builder.gd")
static func build() -> Dictionary:
	var solids := B.wall(-1.5, -1.5, 3)
	solids.append_array(B.wall(1.5, 1.5, 0))
	var chamber := B.box(Vector4(-1.15, -2, -4, -2), Vector4(1.15, 2, 4, 5))
	# A genuine L-shaped Z/W passage between the two walls, with finite Y clearance.
	solids.append_array(B.carve(chamber, [
		B.box(Vector4(-1.2, -0.8, -2.3, 2.2), Vector4(1.2, 0.8, 2.3, 3.8)),
		B.box(Vector4(-1.2, -0.8, 0.7, -0.8), Vector4(1.2, 0.8, 2.3, 3.8))]))
	return {
		"title": "THE ELBOW", "lesson": "A passage can turn through a dimension you cannot currently move along.",
		"start": Vector4(-3, 0, -1.5, 0), "low": Vector4(-4, -1.2, -3, -0.5), "high": Vector4(4, 1.2, 3, 4),
		"goal": Vector4(3, 0, 1.5, 0), "modes": [0, 1], "solids": solids,
		"route": [Vector4(-3, 0, -1.5, 3), Vector4(0, 0, -1.5, 3), Vector4(0, 0, 1.5, 3), Vector4(0, 0, 1.5, 0), Vector4(3, 0, 1.5, 0)],
		"route_modes": [1, 0, 1, 1, 0],
		"hints": ["The first aperture is on another W slice. Use what you learned in the first chamber.", "Cross the first gate, then stop inside the chamber between the walls.", "The far wall has no opening here. Turn along Z inside the passage; the cyan marker shows the elbow.", "Now turn along W. A route that bends in Z/W looks like a dead end when W is frozen.", "The second gate opens on the original W slice. Return to XYZ and cross to the exit."],
		"details": ["Press 2. Hold D to W = 3; keep Z near -1.5.", "Press 1. Hold D to X = 0, between the walls.", "Press 2. Hold S to Z = 1.5, keeping W near 3.", "Stay in YZW. Hold A to W = 0; keep Z near 1.5.", "Press 1. Hold D to X = 3."],
		"captions": ["01  /  FIRST APERTURE", "02  /  ENTER THE CHAMBER", "03  /  FIND THE ELBOW", "04  /  TURN THROUGH W", "05  /  SECOND APERTURE"],
		"shell": true,
	}
