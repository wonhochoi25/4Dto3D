extends RefCounted
## Double press forward, then hold it. Release, pause, survey or a frame change stops it.
const DOUBLE_TAP_MS := 280
var last_press := -10000
var active := false

func press(now_ms: int) -> void:
	active = now_ms - last_press <= DOUBLE_TAP_MS
	last_press = now_ms

func release() -> void:
	active = false

func reset() -> void:
	active = false
	last_press = -10000
