class_name SegmentStrip
extends Control
## Health segments, dash pips and ammo pips are the same widget with different
## counts and sizes - one script, three configurations, exactly as the handoff asks.
##
## Discrete segments rather than a continuous bar: the player counts them
## peripherally without reading a number.

enum Shape { RECT, SKEWED }

@export var count: int = 10:
	set(value):
		count = maxi(value, 0)
		queue_redraw()

@export var filled: int = 10:
	set(value):
		filled = clampi(value, 0, count)
		queue_redraw()

@export var segment_size: Vector2 = Vector2(41, 14)
@export var gap: float = 3.0
@export var shape: Shape = Shape.RECT
## Horizontal lean for dash pips.
@export var skew: float = 8.0

@export var filled_color: Color = Color("#35E0D4")
@export var empty_color: Color = Color("#1E212B")
## Drawn over the empty part of the next segment: dash regen, reload progress.
@export var progress_color: Color = Color("#454C60")
## 0..1 fill of the first empty segment. -1 disables it.
@export var progress: float = -1.0:
	set(value):
		progress = value
		queue_redraw()

## Ghost of health just lost, draining behind the real bar (spec 4.6).
var _ghost: int = 0
var _ghost_timer: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_min_size()


func _process(delta: float) -> void:
	if _ghost_timer <= 0.0:
		return
	_ghost_timer -= delta
	if _ghost_timer <= 0.0:
		_ghost = 0
	queue_redraw()


func _draw() -> void:
	for i: int in count:
		var origin := Vector2(float(i) * (segment_size.x + gap), 0.0)
		var is_filled: bool = i < filled
		var is_ghost: bool = not is_filled and i < _ghost
		var tint: Color = filled_color if is_filled else (
			Tokens.ENEMY if is_ghost else empty_color)
		_segment(origin, segment_size, tint)

		if not is_filled and not is_ghost and i == filled and progress > 0.0:
			_segment(origin, Vector2(segment_size.x * clampf(progress, 0.0, 1.0),
				segment_size.y), progress_color)


# Public API

## Sets the filled count, leaving a draining ENEMY ghost behind any loss.
func set_filled_with_ghost(value: int) -> void:
	var clamped: int = clampi(value, 0, count)
	if clamped < filled:
		_ghost = filled
		_ghost_timer = Tokens.GHOST_DRAIN
	filled = clamped


func configure(new_count: int, new_filled: int) -> void:
	count = new_count
	filled = new_filled
	_update_min_size()


# Private

func _update_min_size() -> void:
	custom_minimum_size = Vector2(
		float(count) * segment_size.x + maxf(float(count - 1), 0.0) * gap,
		segment_size.y)


func _segment(origin: Vector2, dimensions: Vector2, tint: Color) -> void:
	if shape == Shape.RECT:
		draw_rect(Rect2(origin, dimensions), tint)
		return
	# Parallelogram: the dash pip shape, leaning into the direction of travel.
	draw_colored_polygon(PackedVector2Array([
		origin + Vector2(skew, 0.0),
		origin + Vector2(dimensions.x, 0.0),
		origin + Vector2(dimensions.x - skew, dimensions.y),
		origin + Vector2(0.0, dimensions.y)]), tint)
