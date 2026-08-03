class_name HostMark
extends Control
## The Host's mark: a crossed ring - a lens, a target and a gate at once.
##
## Two primitives, so it works as favicon, broadcast bug, floor decal and loading
## spinner. When it spins, the ring rotates and the cross does not, which is what
## makes it read as equipment rather than as decoration.

@export var color: Color = Color("#FFB020"):
	set(value):
		color = value
		queue_redraw()

## Turns the mark into the loading spinner.
@export var is_spinning: bool = false:
	set(value):
		is_spinning = value
		set_process(value)

var _spin: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(is_spinning)
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(34, 34)


func _process(delta: float) -> void:
	_spin = fmod(_spin + delta * 1.6, TAU)
	queue_redraw()


func _draw() -> void:
	var centre: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5
	var stroke: float = maxf(radius * (float(Tokens.HOST_MARK_STROKE) / 17.0), 1.5)

	# The ring carries the rotation; the cross stays level.
	draw_arc(centre, radius - stroke * 0.5 - 3.0, _spin, _spin + TAU * 0.86, 32,
		color, stroke)
	draw_line(centre - Vector2(radius, 0.0), centre + Vector2(radius, 0.0), color, stroke)
	draw_line(centre - Vector2(0.0, radius), centre + Vector2(0.0, radius), color, stroke)
