extends RefCounted
## Every box, landmark, trigger and object lives in one shared 4D world.
static func build(index: int) -> Dictionary:
	var d := {"index": index, "solids": [], "pads": [], "cubes": [], "sockets": [], "signs": [],
		"spawn": Vector4(0.9, -7, 0.851, 0.9), "exit": Vector4(0.9, 7, 0.851, 4),
		"exit_mode": 0, "goal_circuit": "", "bounds_low": Vector4(0, -10, 0, 0), "bounds_high": Vector4(12, 10, 8, 8)}
	shell(d)
	match index:
		0:
			d.title = "01 / THE WALL IS A FLOOR"
			d.subtitle = "You stayed in the same place. Down did not."
			d.brief = "The barrier spans the XYZ room. At the first station choose XYW: gravity changes from -Z to -X and the side wall becomes your floor. Walk along W, pass the barrier, then return to XYZ at the far station."
			d.hints = ["In XYZ the floor is XY and W is fixed. At A, choose XYW (3). Its floor is YW, on the old X wall.", "In XYW, W is a walking direction. Move toward W=4, then along Y past the end of the barrier. All coordinates stay physical.", "The far station is at X≈0.9, Y=5, Z≈0.9, W=4. Choose XYZ (1); then reach the exit at Y=7, W=4."]
			box(d, Vector4(0, -0.4, 0, 0), Vector4(12, 0.4, 8, 2.3), "barrier")
			pad(d, "A", Vector4(0.9, -5, 0.9, 0.9), [0, 1, 2, 3])
			pad(d, "B", Vector4(0.9, 5, 0.9, 4), [0, 1, 2, 3])
			add_sign(d, "THE WALL IS YOUR NEXT FLOOR", Vector4(3, -3, 2.4, 0.9))
			add_sign(d, "W → 4 / WALK AROUND THE EDGE", Vector4(0.9, -2, 0.9, 4))
		1:
			d.title = "02 / A DIFFERENT DEPTH"
			d.subtitle = "The doorway is real. It is just outside this slice."
			d.spawn = Vector4(3, -7, 0.851, 0.9)
			d.exit = Vector4(3, 7, 0.851, 6.5)
			d.goal_circuit = "exit"
			d.brief = "Carry the orange cell. XZW keeps Z as gravity and lets you walk continuously along W while Y stays fixed. Find the doorway's W range, return to XYZ, and bring the cell through the wall to the exit receiver."
			d.hints = ["The wall has an opening only between W=5.6 and W=7.4. Walking in XYZ cannot change W.", "Take the cell to A. Choose XZW (2) and walk along W toward 6.5. Station B lets you return to XYZ without moving any coordinate.", "Return to XYZ at W=6.5. The held cell follows you into the new system automatically. Carry it through the doorway to EXIT at Y=5."]
			box(d, Vector4(0, -0.4, 0, 0), Vector4(12, 0.4, 8, 5.6), "barrier")
			box(d, Vector4(0, -0.4, 0, 7.4), Vector4(12, 0.4, 8, 8), "barrier")
			pad(d, "A", Vector4(3, -5, 0.9, 0.9), [0, 1])
			pad(d, "B", Vector4(3, -5, 0.9, 6.5), [0, 1])
			cube(d, "a", Vector4(3, -6, 0.35, 0.9))
			socket(d, "exit", Vector4(3, 5, 0.7, 6.5), 2, "EXIT")
			add_sign(d, "DOORWAY / 5.6 < W < 7.4", Vector4(3, -3, 2.4, 0.9))
			add_sign(d, "W = 6.5 / RETURN TO XYZ", Vector4(3, -4, 1.9, 6.5))
		2:
			d.title = "03 / ABOVE AND BESIDE"
			d.subtitle = "Carry a height into a world where height no longer falls."
			d.spawn = Vector4(0.9, -7, 0.851, 0.9)
			d.exit = Vector4(0.9, 8.5, 0.851, 6)
			d.goal_circuit = "exit"
			d.brief = "Climb the gold steps with the cell. At the raised station switch to XYW: Z becomes fixed and X becomes down. Carry that height along the wall, walk W to the far station, then return to XYZ and power the exit."
			d.hints = ["The barrier fills W but ends at Z=2.8. Jump up the gold staircase to the raised station at Z≈3.25.", "At A choose XYW (3). Your Z coordinate is now frozen above the barrier. The old X wall supports you as you walk Y and W.", "Take the cell to B at Y=5, W=6 while keeping Z≈3.25. Choose XYZ (1), land on the far side, power EXIT, and walk to Y=7."]
			box(d, Vector4(0, -0.4, 0, 0), Vector4(12, 0.4, 2.8, 8), "barrier")
			# A jump staircase on the XY floor. Final support ends before the barrier.
			for i in range(4):
				box(d, Vector4(0, -5.8 + i * 1.05, 0, 0), Vector4(2.1, -4.75 + i * 1.05, (i + 1) * 0.6, 2.1), "steps")
			pad(d, "A", Vector4(0.9, -2.05, 3.25, 0.9), [0, 2])
			pad(d, "B", Vector4(0.9, 5, 3.25, 6), [0, 2])
			box(d, Vector4(0, 4, 0, 5), Vector4(2.1, 5.7, 2.4, 7), "steps")
			cube(d, "a", Vector4(0.9, -6.5, 0.35, 0.9))
			socket(d, "exit", Vector4(0.9, 7, 0.7, 6), 2, "EXIT")
			add_sign(d, "CLIMB / THEN FREEZE Z", Vector4(3.2, -4, 4.7, 0.9))
			add_sign(d, "KEEP Z > 3 / Y → 5 / W → 6", Vector4(0.9, 1, 3.25, 5))
	return d

static func box(d: Dictionary, low: Vector4, high: Vector4, role: String = "wall") -> void:
	d.solids.append({"low": low, "high": high, "role": role})

static func shell(d: Dictionary) -> void:
	var low: Vector4 = d.bounds_low; var high: Vector4 = d.bounds_high
	for axis in range(4):
		var a := low - Vector4.ONE * 0.5; var b := high + Vector4.ONE * 0.5
		b[axis] = low[axis]
		box(d, a, b, "shell")
		a = low - Vector4.ONE * 0.5; b = high + Vector4.ONE * 0.5
		a[axis] = high[axis]
		box(d, a, b, "shell")

static func pad(d: Dictionary, id: String, p: Vector4, modes: Array) -> void:
	d.pads.append({"id": id, "p": p, "modes": modes})

static func cube(d: Dictionary, id: String, p: Vector4) -> void:
	d.cubes.append({"id": id, "p": p})

static func socket(d: Dictionary, id: String, p: Vector4, gravity: int, label: String) -> void:
	d.sockets.append({"id": id, "p": p, "gravity": gravity, "label": label})

static func add_sign(d: Dictionary, text: String, p: Vector4) -> void:
	d.signs.append({"text": text, "p": p})
