class_name StripeBar
extends Control
## The 45-degree hazard stripe, drawn rather than tiled from a texture.
##
## One shape serves the elite-wave top stripe, hazard floor decals and the
## disappearing-platform warning, so "acid + 45 degrees" always means the same thing.

@export var stripe_color: Color = Color("#C6FF3D"):
	set(value):
		stripe_color = value
		queue_redraw()

@export var gap_color: Color = Color("#07080B"):
	set(value):
		gap_color = value
		queue_redraw()

## Width of one stripe; the gap matches it, giving the spec's 18/36px rhythm.
@export var stripe_width: float = 18.0:
	set(value):
		stripe_width = maxf(value, 1.0)
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), gap_color)
	# Diagonals are drawn past both edges and clipped by the control's own rect.
	var step: float = stripe_width * 2.0
	var x: float = -size.y
	while x < size.x + size.y:
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, size.y),
			Vector2(x + stripe_width, size.y),
			Vector2(x + stripe_width + size.y, 0.0),
			Vector2(x + size.y, 0.0)]), stripe_color)
		x += step
