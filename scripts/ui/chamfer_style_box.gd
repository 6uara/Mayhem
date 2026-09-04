@tool
class_name ChamferStyleBox
extends StyleBox
## The panel look from the handoff: flat fill, thin border, one 45-degree cut on the
## bottom-right, and an optional accent rail on one edge.
##
## Godot's StyleBoxFlat only offers rounded corners, and the style guide bans radius
## outright ("cut corners, never rounded"), so the panel is drawn by hand. It is still
## a StyleBox, so every Control themes with it normally.
##
## `@tool` because the editor draws styleboxes too - the theme preview, the
## inspector, every panel in an open scene. Without it the script does not run
## there, Godot falls back to the bare StyleBox, and every draw logs "Required
## virtual method StyleBox::_draw must be overridden" while the panels render
## as nothing. Only `_draw` runs here, so there is no editor side effect to fear.

@export var fill_color: Color = Color("#14161C")
@export var fill_alpha: float = 0.82
@export var border_color: Color = Color("#2C3140")
@export var border_width: float = 1.0
## Size of the 45-degree cut on the bottom-right corner.
@export var chamfer: float = 12.0

@export_group("Accent rail")
## 0 disables the rail. The rail is how "current" is expressed everywhere: the
## equipped weapon, the selected menu row, the affordable shop card.
@export var rail_width: float = 0.0
@export var rail_color: Color = Color("#35E0D4")
@export var rail_side: Side = SIDE_LEFT

@export_group("Corner ticks")
## Frames are incomplete: bracket corners rather than closed boxes.
@export var tick_length: float = 0.0
@export var tick_color: Color = Color("#2C3140")


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var points: PackedVector2Array = _outline(rect)

	var fill: Color = fill_color
	fill.a *= fill_alpha
	if fill.a > 0.0:
		RenderingServer.canvas_item_add_polygon(to_canvas_item, points,
			PackedColorArray([fill, fill, fill, fill, fill]))

	if border_width > 0.0 and border_color.a > 0.0:
		var closed: PackedVector2Array = points.duplicate()
		closed.push_back(points[0])
		RenderingServer.canvas_item_add_polyline(to_canvas_item, closed,
			_uniform(border_color, closed.size()), border_width)

	_draw_rail(to_canvas_item, rect)
	_draw_ticks(to_canvas_item, rect)


# Private

## Rectangle with the bottom-right corner cut at 45 degrees.
func _outline(rect: Rect2) -> PackedVector2Array:
	var cut: float = minf(chamfer, minf(rect.size.x, rect.size.y) * 0.5)
	var left: float = rect.position.x
	var top: float = rect.position.y
	var right: float = rect.position.x + rect.size.x
	var bottom: float = rect.position.y + rect.size.y
	return PackedVector2Array([
		Vector2(left, top),
		Vector2(right, top),
		Vector2(right, bottom - cut),
		Vector2(right - cut, bottom),
		Vector2(left, bottom),
	])


func _draw_rail(to_canvas_item: RID, rect: Rect2) -> void:
	if rail_width <= 0.0 or rail_color.a <= 0.0:
		return
	var bar: Rect2
	match rail_side:
		SIDE_LEFT:
			bar = Rect2(rect.position, Vector2(rail_width, rect.size.y))
		SIDE_RIGHT:
			bar = Rect2(Vector2(rect.position.x + rect.size.x - rail_width, rect.position.y),
				Vector2(rail_width, rect.size.y))
		SIDE_TOP:
			bar = Rect2(rect.position, Vector2(rect.size.x, rail_width))
		_:
			bar = Rect2(Vector2(rect.position.x, rect.position.y + rect.size.y - rail_width),
				Vector2(rect.size.x, rail_width))
	RenderingServer.canvas_item_add_rect(to_canvas_item, bar, rail_color)


func _draw_ticks(to_canvas_item: RID, rect: Rect2) -> void:
	if tick_length <= 0.0 or tick_color.a <= 0.0:
		return
	var thickness: float = maxf(border_width, 2.0)
	var left: float = rect.position.x
	var top: float = rect.position.y
	var right: float = rect.position.x + rect.size.x
	var bottom: float = rect.position.y + rect.size.y
	# Top-left and bottom-right brackets only - enough to read as a frame.
	for bar: Rect2 in [
		Rect2(Vector2(left, top), Vector2(tick_length, thickness)),
		Rect2(Vector2(left, top), Vector2(thickness, tick_length)),
		Rect2(Vector2(right - tick_length, bottom - thickness), Vector2(tick_length, thickness)),
		Rect2(Vector2(right - thickness, bottom - tick_length), Vector2(thickness, tick_length)),
	]:
		RenderingServer.canvas_item_add_rect(to_canvas_item, bar, tick_color)


func _uniform(tint: Color, count: int) -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(count)
	colors.fill(tint)
	return colors
