class_name MayhemIcon
extends Control
## The whole 25-icon set, drawn procedurally instead of authored as PNGs.
##
## Every icon in the handoff is described as rectangles, circles, triangles and one
## skew on a 64x64 grid with a 4px stroke - which is exactly what _draw() does well,
## so the set costs no art time and stays perfectly crisp at any size.
##
## PNG escape hatch: assign `texture` and the icon draws that instead, with no change
## at any call site. When the hand-authored set exists, dropping the files in and
## setting `texture` is the entire migration.

enum Kind {
	NONE,
	# Weapons - proportions mirror the viewmodels, so the icon teaches the silhouette.
	RIFLE, SHOTGUN, SMG, PISTOL,
	# Utilities
	STUN_GRENADE, TEMP_WALL, SLOW_FIELD,
	# Status
	DASH, GRAPPLE, LOW_HEALTH, POWER_UP, HAZARD,
	# Category frames
	FRAME_MOBILITY, FRAME_WEAPON, FRAME_SURVIVABILITY,
	# Modifier glyphs, worn inside a category frame
	GLYPH_SPEED, GLYPH_DASH, GLYPH_GRAPPLE,
	GLYPH_DAMAGE, GLYPH_ACCURACY, GLYPH_FIRE_RATE,
	GLYPH_MAX_HP, GLYPH_ARMOUR, GLYPH_REGEN,
	# Economy
	CURRENCY,
}

## Authoring grid from the spec. All geometry below is written in these units and
## scaled to the node's real size, so one definition serves 24px and 256px alike.
const GRID: float = 64.0
const STROKE: float = 4.0

@export var kind: Kind = Kind.NONE:
	set(value):
		kind = value
		queue_redraw()

@export var color: Color = Color("#E6E8EF"):
	set(value):
		color = value
		queue_redraw()

## Set this to draw a hand-authored PNG instead. Nothing else has to change.
@export var texture: Texture2D:
	set(value):
		texture = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(GRID, GRID)


func _draw() -> void:
	if texture != null:
		draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false, color)
		return
	if kind == Kind.NONE:
		return

	# Uniform scale keeps the 4px stroke proportional at every export size.
	var scale: float = minf(size.x, size.y) / GRID
	var origin: Vector2 = (size - Vector2(GRID, GRID) * scale) * 0.5
	_draw_kind(origin, scale)


# Public API

## Pixel size the icon wants for a given box, honouring the 4px safe margin.
static func content_rect(box: float) -> float:
	return box - (STROKE * 2.0) * (box / GRID)


# Private - each icon is written in 64x64 grid units

func _draw_kind(origin: Vector2, s: float) -> void:
	match kind:
		Kind.RIFLE: _rifle(origin, s)
		Kind.SHOTGUN: _shotgun(origin, s)
		Kind.SMG: _smg(origin, s)
		Kind.PISTOL: _pistol(origin, s)
		Kind.STUN_GRENADE: _stun_grenade(origin, s)
		Kind.TEMP_WALL: _temp_wall(origin, s)
		Kind.SLOW_FIELD: _slow_field(origin, s)
		Kind.DASH: _dash(origin, s)
		Kind.GRAPPLE: _grapple(origin, s)
		Kind.LOW_HEALTH: _triangle(origin, s, 32, 34, 26, true)
		Kind.POWER_UP: _pentagon(origin, s)
		Kind.HAZARD: _hazard(origin, s)
		Kind.FRAME_MOBILITY: _rect(origin, s, 8, 8, 48, 48, false)
		Kind.FRAME_WEAPON: _diamond(origin, s, 32, 32, 26, false)
		Kind.FRAME_SURVIVABILITY: _circle(origin, s, 32, 32, 24, false)
		Kind.GLYPH_SPEED: _triangle(origin, s, 32, 38, 18, true)
		Kind.GLYPH_DASH: _dash(origin, s)
		Kind.GLYPH_GRAPPLE: _grapple(origin, s)
		Kind.GLYPH_DAMAGE: _rect(origin, s, 19, 29, 26, 6, true)
		Kind.GLYPH_ACCURACY: _circle(origin, s, 32, 32, 13, false)
		Kind.GLYPH_FIRE_RATE: _rect(origin, s, 29, 19, 6, 26, true)
		Kind.GLYPH_MAX_HP: _rect(origin, s, 19, 28, 26, 8, true)
		Kind.GLYPH_ARMOUR: _shield(origin, s)
		Kind.GLYPH_REGEN: _open_ring(origin, s)
		Kind.CURRENCY: _circle(origin, s, 32, 32, 20, false)


## Long level barrel + top rail + angled grip + stock - the widest, lowest icon.
func _rifle(o: Vector2, s: float) -> void:
	_rect(o, s, 6, 28, 46, 7, true)     # barrel
	_rect(o, s, 34, 20, 16, 8, true)    # top rail
	_skewed(o, s, 20, 35, 8, 15, -0.3)  # grip
	_rect(o, s, 8, 35, 11, 6, true)     # stock


## Short thick barrel block + underslung tube - the tallest body.
func _shotgun(o: Vector2, s: float) -> void:
	_rect(o, s, 8, 24, 44, 11, true)    # barrel block
	_rect(o, s, 11, 35, 28, 5, true)    # tube
	_skewed(o, s, 27, 35, 9, 14, -0.3)  # grip


## Short barrel + tall top magazine - compact and vertical.
func _smg(o: Vector2, s: float) -> void:
	_rect(o, s, 17, 27, 30, 7, true)    # barrel
	_rect(o, s, 21, 18, 16, 8, true)    # top magazine
	_skewed(o, s, 24, 34, 8, 16, -0.2)  # grip
	_rect(o, s, 35, 34, 6, 11, true)    # foregrip


## Short barrel + steep grip, nothing else - the smallest.
func _pistol(o: Vector2, s: float) -> void:
	_rect(o, s, 21, 27, 22, 7, true)
	_skewed(o, s, 24, 34, 8, 15, -0.35)


func _stun_grenade(o: Vector2, s: float) -> void:
	_circle(o, s, 32, 36, 15, false)
	_rect(o, s, 29, 12, 7, 8, true)     # pin tab


func _temp_wall(o: Vector2, s: float) -> void:
	# Open-bottom box: a barrier you stand behind, not a closed container.
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var w: float = STROKE * s
	draw_line(p.call(14.0, 46.0), p.call(14.0, 20.0), color, w)
	draw_line(p.call(14.0, 20.0), p.call(50.0, 20.0), color, w)
	draw_line(p.call(50.0, 20.0), p.call(50.0, 46.0), color, w)


func _slow_field(o: Vector2, s: float) -> void:
	_diamond(o, s, 32, 32, 22, false)
	var inner: Color = color
	inner.a *= 0.5
	_diamond(o, s, 32, 32, 12, false, inner)


## Two skewed bars - the dash charge mark, matching the HUD pips.
func _dash(o: Vector2, s: float) -> void:
	_skewed(o, s, 18, 20, 10, 24, -0.35)
	_skewed(o, s, 34, 20, 10, 24, -0.35)


## Hook chevron: two borders rotated 45 degrees.
func _grapple(o: Vector2, s: float) -> void:
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var w: float = STROKE * s
	draw_line(p.call(14.0, 32.0), p.call(32.0, 14.0), color, w)
	draw_line(p.call(32.0, 14.0), p.call(50.0, 32.0), color, w)
	draw_line(p.call(32.0, 14.0), p.call(32.0, 46.0), color, w)


func _pentagon(o: Vector2, s: float) -> void:
	var points := PackedVector2Array()
	for i: int in 5:
		var angle: float = -PI * 0.5 + TAU * float(i) / 5.0
		points.push_back(o + (Vector2(32, 32) + Vector2(cos(angle), sin(angle)) * 22.0) * s)
	draw_colored_polygon(points, color)


## 45-degree stripe plate - the hazard mark, same geometry as the arena decals.
func _hazard(o: Vector2, s: float) -> void:
	var rect := Rect2(o + Vector2(10, 14) * s, Vector2(44, 36) * s)
	draw_rect(rect, color, false, STROKE * s)
	var w: float = 3.0 * s
	var step: float = 10.0 * s
	var x: float = rect.position.x
	while x < rect.position.x + rect.size.x + rect.size.y:
		var from := Vector2(x, rect.position.y)
		var to := Vector2(x - rect.size.y, rect.position.y + rect.size.y)
		# Clip the diagonal to the plate so stripes never bleed past the border.
		if to.x < rect.position.x:
			var t: float = (rect.position.x - from.x) / (to.x - from.x)
			to = from.lerp(to, t)
		if from.x > rect.position.x + rect.size.x:
			x += step
			continue
		draw_line(from, to, color, w)
		x += step


func _shield(o: Vector2, s: float) -> void:
	var points := PackedVector2Array([
		o + Vector2(32, 14) * s, o + Vector2(48, 22) * s,
		o + Vector2(32, 50) * s, o + Vector2(16, 22) * s])
	draw_colored_polygon(points, color)


func _open_ring(o: Vector2, s: float) -> void:
	draw_arc(o + Vector2(32, 32) * s, 18.0 * s, PI * 0.25, PI * 1.9, 28, color, STROKE * s)


# Primitives, all in grid units

func _rect(o: Vector2, s: float, x: float, y: float, w: float, h: float,
		filled: bool) -> void:
	var rect := Rect2(o + Vector2(x, y) * s, Vector2(w, h) * s)
	draw_rect(rect, color, filled, -1.0 if filled else STROKE * s)


## The one skew the handoff allows - grip angles and dash pips.
func _skewed(o: Vector2, s: float, x: float, y: float, w: float, h: float,
		skew: float) -> void:
	var offset: float = h * skew
	draw_colored_polygon(PackedVector2Array([
		o + Vector2(x, y) * s,
		o + Vector2(x + w, y) * s,
		o + Vector2(x + w + offset, y + h) * s,
		o + Vector2(x + offset, y + h) * s]), color)


func _circle(o: Vector2, s: float, x: float, y: float, radius: float,
		filled: bool) -> void:
	var centre: Vector2 = o + Vector2(x, y) * s
	if filled:
		draw_circle(centre, radius * s, color)
	else:
		draw_arc(centre, radius * s, 0.0, TAU, 32, color, STROKE * s)


func _diamond(o: Vector2, s: float, x: float, y: float, radius: float, filled: bool,
		override_color: Color = Color(0, 0, 0, 0)) -> void:
	var tint: Color = color if override_color.a == 0.0 else override_color
	var centre: Vector2 = o + Vector2(x, y) * s
	var r: float = radius * s
	var points := PackedVector2Array([
		centre + Vector2(0, -r), centre + Vector2(r, 0),
		centre + Vector2(0, r), centre + Vector2(-r, 0)])
	if filled:
		draw_colored_polygon(points, tint)
	else:
		points.push_back(points[0])
		draw_polyline(points, tint, STROKE * s)


func _triangle(o: Vector2, s: float, x: float, y: float, radius: float,
		filled: bool) -> void:
	var centre: Vector2 = o + Vector2(x, y) * s
	var r: float = radius * s
	var points := PackedVector2Array([
		centre + Vector2(0, -r), centre + Vector2(r * 0.92, r * 0.6),
		centre + Vector2(-r * 0.92, r * 0.6)])
	if filled:
		draw_colored_polygon(points, color)
	else:
		points.push_back(points[0])
		draw_polyline(points, color, STROKE * s)
