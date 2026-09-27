extends SceneTree
## Run headlessly; setup is excluded. Compare the same workload across revisions.
const Session = preload("res://scripts/core/session_4d.gd")
const Box = preload("res://scripts/core/geometry/generators/tesseract.gd")
func _initialize():
	for trial in range(3):
		var session := Session.new()
		for i in range(24):
			var id := session.add_geometry(Box.new(), {}, {"rotation":{"XY":20}, "scale":2})
			session.configure_body(id,"dynamic",Vector4(1,2,3,4))
		var started := Time.get_ticks_usec()
		assert(session.seek(10))
		print("24 bodies / 600 steps: ", (Time.get_ticks_usec()-started)/1000.0, " ms")
	quit()
