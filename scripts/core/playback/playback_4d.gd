extends RefCounted
## UI-independent playback clock. Host calls advance(delta).
signal time_requested(value: float)
const STEP := 1.0 / 60.0
var remainder := 0.0
var busy := false
var time := 0.0
var direction := 0
var start := 0.0
var end := 10.0
var speed := 1.0
var looping := false

func pause() -> void:
	direction = 0
	remainder = 0.0

func advance(delta: float) -> void:
	if direction == 0 or busy: return
	remainder += delta * speed
	var steps := int(floor(remainder / STEP))
	if steps == 0: return
	remainder -= steps * STEP
	var last := maxi(0, int(floor((end - start) / STEP + 0.000001)))
	var index := int(round((time - start) / STEP)) + steps * direction
	if index > last or index < 0:
		if looping: index = posmod(index, maxi(1, last))
		else:
			index = clampi(index, 0, last)
			pause()
	var next_time := start + index * STEP
	time_requested.emit(next_time)

