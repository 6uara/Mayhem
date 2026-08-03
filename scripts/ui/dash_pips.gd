class_name DashPips
extends Control
## One pip per dash charge: filled when ready, an arc filling up for the charge
## currently regenerating, hollow when spent.

@export var pip_radius: float = 7.0
@export var pip_spacing: float = 24.0
@export var ready_color: Color = Color(1, 1, 1, 0.9)
@export var recharging_color: Color = Color(1, 1, 1, 0.45)

var _available: int = 2
var _max_charges: int = 2
var _next_progress: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var total_width: float = float(_max_charges - 1) * pip_spacing
	var start: Vector2 = size * 0.5 - Vector2(total_width * 0.5, 0.0)
	for i: int in _max_charges:
		var center: Vector2 = start + Vector2(pip_spacing * float(i), 0.0)
		if i < _available:
			draw_circle(center, pip_radius, ready_color)
		else:
			draw_arc(center, pip_radius, 0.0, TAU, 20, recharging_color, 1.5)
			# The first spent pip shows the regen progress of the next charge.
			if i == _available and _next_progress > 0.0:
				draw_arc(center, pip_radius, -PI * 0.5,
					-PI * 0.5 + TAU * _next_progress, 20, ready_color, 2.5)


func update_charges(available: int, max_charges: int, next_progress: float) -> void:
	if available == _available and max_charges == _max_charges \
			and is_equal_approx(next_progress, _next_progress):
		return
	_available = available
	_max_charges = max_charges
	_next_progress = next_progress
	queue_redraw()
