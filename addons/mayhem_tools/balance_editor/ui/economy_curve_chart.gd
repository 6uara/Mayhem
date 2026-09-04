@tool
class_name EconomyCurveChart
extends Control
## Cumulative money per wave, drawn against the shop's price ladder.
##
## This chart is the reason the balance editor exists: a table of payouts cannot
## show that wave four is where the second gun becomes affordable, and this can.

const CURVE_COLOR := Color("#3BE8FF")
const PRICE_COLOR := Color(1.0, 1.0, 1.0, 0.22)
const AXIS_COLOR := Color(1.0, 1.0, 1.0, 0.35)
const PADDING: float = 28.0

var series: PackedInt32Array = PackedInt32Array()
var prices: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	custom_minimum_size = Vector2(0.0, 200.0)


func set_data(new_series: PackedInt32Array, new_prices: PackedInt32Array) -> void:
	series = new_series
	prices = new_prices
	queue_redraw()


func _draw() -> void:
	var font: Font = get_theme_default_font()
	var font_size: int = get_theme_default_font_size()
	if series.is_empty():
		draw_string(font, Vector2(PADDING, PADDING), "No wave data to project.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, AXIS_COLOR)
		return

	var plot := Rect2(Vector2(PADDING, PADDING),
		size - Vector2(PADDING * 2.0, PADDING * 2.0))
	var max_value: float = float(series[series.size() - 1])
	for price: int in prices:
		max_value = maxf(max_value, float(price))
	max_value = maxf(max_value, 1.0)

	draw_line(plot.position + Vector2(0.0, plot.size.y), plot.end, AXIS_COLOR)
	draw_line(plot.position, plot.position + Vector2(0.0, plot.size.y), AXIS_COLOR)

	for price: int in prices:
		var y: float = plot.position.y + plot.size.y * (1.0 - float(price) / max_value)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), PRICE_COLOR)

	var points := PackedVector2Array()
	for index: int in series.size():
		var x: float = plot.position.x + plot.size.x * (float(index) / maxf(float(series.size() - 1), 1.0))
		var y: float = plot.position.y + plot.size.y * (1.0 - float(series[index]) / max_value)
		points.append(Vector2(x, y))
	if points.size() > 1:
		draw_polyline(points, CURVE_COLOR, 2.0, true)
	for point: Vector2 in points:
		draw_circle(point, 3.0, CURVE_COLOR)

	draw_string(font, Vector2(PADDING, PADDING - 8.0),
		"%d after wave %d" % [series[series.size() - 1], series.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, CURVE_COLOR)
	draw_string(font, Vector2(plot.position.x, plot.end.y + 18.0), "wave 1",
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, AXIS_COLOR)
	draw_string(font, Vector2(plot.end.x - 48.0, plot.end.y + 18.0), "wave %d" % series.size(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, AXIS_COLOR)
