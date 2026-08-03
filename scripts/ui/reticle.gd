class_name Reticle
extends Control
## One reticle system for every aiming state: hipfire crosshair, grapple-anchor
## confirmation, hitmarkers, kill confirmation and the four ADS sights.
##
## The handoff is explicit that ADS sights are screen-space Controls drawn by this
## same system rather than 3D geometry, so they inherit the VOID outline, the colour
## tokens and the hitmarker states for free.
##
## Every state changes shape as well as colour - a colour-blind player reads the
## anchor state from the square ring, not the cyan.

enum Hit { NONE, BODY, HEADSHOT, KILL }
enum Sight { HIPFIRE, RIFLE, SHOTGUN, SMG, PISTOL }

@export var crosshair_color: Color = Color("#E6E8EF")
@export var anchor_color: Color = Color("#35E0D4")
## Player-configurable, per the settings spec.
@export var gap: float = 8.0
@export var thickness: float = 2.0
@export var show_dot: bool = true

@export_group("Audio")
@export var body_sound: AudioStream
@export var headshot_sound: AudioStream
@export var kill_sound: AudioStream

var sight: Sight = Sight.HIPFIRE:
	set(value):
		sight = value
		queue_redraw()

var is_anchor_available: bool = false:
	set(value):
		if is_anchor_available == value:
			return
		is_anchor_available = value
		queue_redraw()

## 0 = hipfire, 1 = fully aimed. Drives the crossfade to the weapon's sight.
var ads_progress: float = 0.0

var _spread_gap: float = 0.0
var _hit: Hit = Hit.NONE
var _hit_timer: float = 0.0
var _kill_timer: float = 0.0
## Splays the SMG's wings as sustained fire climbs the recoil pattern.
var _recoil_heat: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_apply_settings()
	EventBus.settings_applied.connect(_apply_settings)


func _process(delta: float) -> void:
	var dirty: bool = false
	if _hit_timer > 0.0:
		_hit_timer -= delta
		dirty = true
	if _kill_timer > 0.0:
		_kill_timer -= delta
		dirty = true
	if _recoil_heat > 0.0:
		_recoil_heat = maxf(_recoil_heat - delta * 2.5, 0.0)
		dirty = true
	if dirty:
		queue_redraw()


func _draw() -> void:
	var centre: Vector2 = size * 0.5
	# Hipfire ticks fade out as the weapon's own sight fades in.
	if ads_progress < 0.99:
		_draw_crosshair(centre, 1.0 - ads_progress)
	if ads_progress > 0.01:
		_draw_sight(centre, ads_progress)
	_draw_hitmarker(centre)
	_draw_kill_confirm(centre)


# Public API

## `spread_degrees` is the weapon's real cone; the gap is the honest projection of it.
func set_spread(spread_degrees: float, fov: float) -> void:
	var half_fov: float = tan(deg_to_rad(maxf(fov, 1.0) * 0.5))
	var pixels: float = 0.0
	if half_fov > 0.0:
		pixels = (tan(deg_to_rad(spread_degrees)) / half_fov) * (size.y * 0.5)
	if not is_equal_approx(pixels, _spread_gap):
		_spread_gap = pixels
		queue_redraw()


func show_hit(hit: Hit) -> void:
	if hit == Hit.NONE:
		return
	if hit == Hit.KILL:
		_kill_timer = Tokens.KILL_CONFIRM_LIFE
		AudioPool.play_2d(kill_sound, AudioPool.BUS_UI)
	else:
		# A headshot marker lives 25% longer, so it reads as the better hit.
		_hit = hit
		_hit_timer = Tokens.HITMARKER_LIFE * (1.25 if hit == Hit.HEADSHOT else 1.0)
		AudioPool.play_2d(headshot_sound if hit == Hit.HEADSHOT else body_sound,
			AudioPool.BUS_UI)
	queue_redraw()


func note_shot_fired() -> void:
	_recoil_heat = minf(_recoil_heat + 0.35, 1.0)


# Private

func _apply_settings() -> void:
	gap = float(SettingsManager.get_value("hud/crosshair_gap", gap))
	thickness = float(SettingsManager.get_value("hud/crosshair_thickness", thickness))
	crosshair_color = SettingsManager.get_value("hud/crosshair_color", crosshair_color)
	show_dot = bool(SettingsManager.get_value("hud/crosshair_dot", show_dot))
	queue_redraw()


func _draw_crosshair(centre: Vector2, alpha: float) -> void:
	var tint: Color = anchor_color if is_anchor_available else crosshair_color
	tint.a *= alpha
	var reach: float = maxf(gap + _spread_gap, gap)
	var tick: float = Tokens.RETICLE_TICK.y

	for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var from: Vector2 = centre + direction * reach
		var to: Vector2 = from + direction * tick
		_outlined_line(from, to, tint, thickness)

	if show_dot:
		var dot: float = Tokens.RETICLE_DOT
		draw_rect(Rect2(centre - Vector2(dot, dot) * 0.5, Vector2(dot, dot)), tint)

	# Anchor state: a rotated square ring. The shape is the signal; cyan confirms it.
	if is_anchor_available:
		var radius: float = Tokens.RETICLE_EXPANDED * 0.25
		_diamond(centre, radius, tint, 2.0)


## The weapon's own sight, per SPEC-VIEWMODELS 1.3.
func _draw_sight(centre: Vector2, alpha: float) -> void:
	var tint: Color = anchor_color
	tint.a *= alpha
	match sight:
		Sight.RIFLE:
			# Holo cross + centre square: occludes least.
			_outlined_line(centre - Vector2(0, 22), centre - Vector2(0, 6), tint, 2.0)
			_outlined_line(centre + Vector2(0, 6), centre + Vector2(0, 22), tint, 2.0)
			_outlined_line(centre - Vector2(22, 0), centre - Vector2(6, 0), tint, 2.0)
			_outlined_line(centre + Vector2(6, 0), centre + Vector2(22, 0), tint, 2.0)
			draw_rect(Rect2(centre - Vector2(4, 4), Vector2(8, 8)), tint, false, 2.0)
		Sight.SHOTGUN:
			# Dashed ring whose radius IS the current pellet spread.
			draw_circle(centre, 5.0, tint)
			_dashed_ring(centre, maxf(_spread_gap, 18.0), tint)
		Sight.SMG:
			# Wings splay with sustained fire - recoil made visible.
			var splay: float = 10.0 + _recoil_heat * 22.0
			_triangle_up(centre - Vector2(0, 20), 9.0, tint)
			_outlined_line(centre - Vector2(splay + 22, 0), centre - Vector2(splay, 0), tint, 2.0)
			_outlined_line(centre + Vector2(splay, 0), centre + Vector2(splay + 22, 0), tint, 2.0)
		Sight.PISTOL:
			# Post and notch, one bead. The dark geometry is the viewmodel's own.
			draw_circle(centre - Vector2(0, 6), 4.0, tint)
		_:
			pass


func _draw_hitmarker(centre: Vector2) -> void:
	if _hit_timer <= 0.0 or _hit == Hit.NONE:
		return
	var is_headshot: bool = _hit == Hit.HEADSHOT
	var life: float = Tokens.HITMARKER_LIFE * (1.25 if is_headshot else 1.0)
	var tint: Color = Tokens.ENEMY if is_headshot else Color.WHITE
	tint.a = clampf(_hit_timer / life, 0.0, 1.0)
	var width: float = 3.0 if is_headshot else 2.0
	var inner: float = 10.0
	var outer: float = inner + (18.0 if is_headshot else 14.0)

	for direction: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		var normalized: Vector2 = direction.normalized()
		draw_line(centre + normalized * inner, centre + normalized * outer, tint, width)


## Diamond expanding 1.0 -> 1.35 then fading, per the spec.
func _draw_kill_confirm(centre: Vector2) -> void:
	if _kill_timer <= 0.0:
		return
	var progress: float = 1.0 - clampf(_kill_timer / Tokens.KILL_CONFIRM_LIFE, 0.0, 1.0)
	var tint: Color = Tokens.ENEMY
	tint.a = 1.0 - progress
	_diamond(centre, 16.0 * lerpf(1.0, Tokens.KILL_CONFIRM_SCALE, progress), tint, 3.0)


func _diamond(centre: Vector2, radius: float, tint: Color, width: float) -> void:
	var points := PackedVector2Array([
		centre + Vector2(0, -radius), centre + Vector2(radius, 0),
		centre + Vector2(0, radius), centre + Vector2(-radius, 0),
		centre + Vector2(0, -radius)])
	draw_polyline(points, tint, width)


func _triangle_up(tip: Vector2, radius: float, tint: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		tip, tip + Vector2(radius, radius * 1.6), tip + Vector2(-radius, radius * 1.6)]), tint)


func _dashed_ring(centre: Vector2, radius: float, tint: Color) -> void:
	var segments: int = 16
	for i: int in segments:
		if i % 2 == 1:
			continue
		var from: float = TAU * float(i) / float(segments)
		draw_arc(centre, radius, from, from + TAU / float(segments), 4, tint, 2.0)


## 1px VOID outline so the reticle survives a bright surface.
func _outlined_line(from: Vector2, to: Vector2, tint: Color, width: float) -> void:
	var outline: Color = Tokens.VOID
	outline.a = tint.a
	draw_line(from, to, outline, width + Tokens.RETICLE_OUTLINE * 2.0)
	draw_line(from, to, tint, width)
