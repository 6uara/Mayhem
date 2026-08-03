class_name Crosshair
extends Control
## Four-line crosshair whose gap tracks the weapon's real spread cone, so the player
## can read their own accuracy without firing a shot.

@export var line_length: float = 8.0
@export var line_width: float = 2.0
@export var min_gap: float = 4.0
@export var color: Color = Color(1, 1, 1, 0.85)
@export var outline_color: Color = Color(0, 0, 0, 0.5)
## Reticle tint while aiming at a usable grapple anchor - the telegraph CLAUDE.md
## 5.2 requires. A bracket pair is drawn around the crosshair as well.
@export var grapple_color: Color = Color(0.35, 0.9, 1.0, 0.95)

var _gap: float = 4.0
var _is_anchor_available: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var center := size * 0.5
	var draw_color: Color = grapple_color if _is_anchor_available else color
	for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var from: Vector2 = center + direction * _gap
		var to: Vector2 = from + direction * line_length
		draw_line(from, to, outline_color, line_width + 2.0)
		draw_line(from, to, draw_color, line_width)
	if _is_anchor_available:
		var radius: float = _gap + line_length + 6.0
		draw_arc(center, radius, -PI * 0.25, PI * 0.25, 12, grapple_color, 2.0)
		draw_arc(center, radius, PI * 0.75, PI * 1.25, 12, grapple_color, 2.0)


## `spread_degrees` is the cone half-angle; `fov` and the viewport height convert it
## into the pixel radius that cone actually covers on screen.
func set_spread(spread_degrees: float, fov: float) -> void:
	var half_fov: float = tan(deg_to_rad(maxf(fov, 1.0) * 0.5))
	var pixels: float = 0.0
	if half_fov > 0.0:
		pixels = (tan(deg_to_rad(spread_degrees)) / half_fov) * (size.y * 0.5)
	var target: float = maxf(pixels, min_gap)
	if not is_equal_approx(target, _gap):
		_gap = target
		queue_redraw()


func set_anchor_available(value: bool) -> void:
	if _is_anchor_available == value:
		return
	_is_anchor_available = value
	queue_redraw()
