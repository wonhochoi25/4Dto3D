extends RefCounted
const B = preload("res://hybrid/imported/scripts/campaign/chamber_builder.gd")
static func build() -> Dictionary:
	# Same fixed wall in 4D: its aperture widens along W. No view-triggered collider swaps.
	var solids := B.carve(B.box(Vector4(-0.35, -2, -3, -1), Vector4(0.35, 2, 3, 5), "gate"), [
		B.box(Vector4(-1, -0.8, -0.28, -1), Vector4(1, 0.8, 0.28, 5)),
		B.box(Vector4(-1, -0.8, -0.9, 2), Vector4(1, 0.8, 0.9, 4.5))])
	solids.append(B.box(Vector4(3.2, -2, -3, -1), Vector4(3.6, 2, 3, 5), "exit_gate"))
	return {
		"title": "THE RIGHT FIT", "lesson": "The key stays the same. Find the slice where the opening fits.",
		"start": Vector4(-3, 0, 0, 0), "low": Vector4(-4, -1.2, -2, 0), "high": Vector4(6, 1.2, 2, 4),
		"goal": Vector4(5, 0, 0, 3), "modes": [0, 1], "solids": solids,
		"route": [Vector4(-2, 0, 0, 0), Vector4(-3, 0, 0, 3), Vector4(0.8, 0, 0, 3), Vector4(5, 0, 0, 3)],
		"route_modes": [0, 1, 0, 0],
		"hints": ["Look at the orange key and press G to grab it. It is wider than this opening.", "Carry the key along W. The aperture changes across slices; inspection can help you find the wider section.", "At W = 3, cross the wider opening in XYZ. Release the key over the violet plate to open the exit gate.", "The plate has secured the key and opened the gate. Go around the key and reach the gold exit."],
		"details": ["In first person, look at the key from within 1.8 units and press G. It keeps its 4D offset while carried.", "Select YZW (2). Move until W = 3. The carried key can be outside your current slice; its position is shown in the HUD.", "Select XYZ (1). Carry along +X until the key is roughly over the plate near X = 1.8, Y = 0, Z = 0, W = 3. Release with G while the key center is inside the outlined target; exact alignment is not needed.", "In XYZ, move sideways around the secured key, pass the open gate, and reach X = 5, Y = 0, Z = 0, W = 3."],
		"captions": ["01 / PICK UP THE KEY", "02 / FIND A WIDER SLICE", "03 / DELIVER TO THE PLATE", "04 / EXIT UNLOCKED"],
		"shell": false, "key_chamber": true,
	}
