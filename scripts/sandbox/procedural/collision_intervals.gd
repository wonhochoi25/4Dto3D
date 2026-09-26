extends Control
## Two 1D support intervals on a shared scale; not a 3D collision visualization.
var intervals: Array = []
func _init():
	custom_minimum_size = Vector2(240,42)
func show_intervals(values: Array):
	intervals = values
	queue_redraw()
func _draw():
	if intervals.size() != 2: return
	var low: float = minf(intervals[0].x,intervals[1].x)
	var high: float = maxf(intervals[0].y,intervals[1].y)
	var span := maxf(high-low,1e-12)
	for i in range(2):
		var y := 10.0+i*22
		var a: float = 6+(intervals[i].x-low)/span*(size.x-12)
		var b: float = 6+(intervals[i].y-low)/span*(size.x-12)
		var color := Color("70d7ff") if i == 0 else Color("d29aff")
		draw_line(Vector2(a,y),Vector2(b,y),color,4)
		draw_line(Vector2(a,y-5),Vector2(a,y+5),color,2)
		draw_line(Vector2(b,y-5),Vector2(b,y+5),color,2)
