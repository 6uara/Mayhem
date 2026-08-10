class_name DamageNumber
extends Node3D
## Pooled floating damage number over whatever a hit landed on. Cosmetic only -
## driven by EventBus.damage_dealt, the same signal HitstopController already
## consumes, so this never becomes a second source of truth for damage.
##
## No exact hit_position travels on that signal (only `target`), so this spawns
## near the target's own position rather than the precise impact point - close
## enough to read as attached to what got hit, without threading a new
## parameter through EventBus for it.

const LIFETIME: float = 0.7
const RISE_HEIGHT: float = 1.0
## Small per-number offset so simultaneous hits (a shotgun blast, several
## enemies dying in the same frame) don't stack into one unreadable column.
const JITTER_RADIUS: float = 0.18
const FADE_START_FRACTION: float = 0.35
const BODY_FONT_SIZE: int = 48
## Headshots already get their own hitmarker treatment (Reticle.Hit.HEADSHOT);
## this mirrors that distinction here too - bigger and REWARD-coloured.
const HEADSHOT_FONT_SIZE: int = 64

@onready var _label: Label3D = $Label3D

var _timer: float = 0.0
var _is_playing: bool = false
var _tween: Tween


## `amount` is already the final applied damage (falloff, headshot multiplier,
## damage_taken_multiplier all resolved upstream) - this only ever displays it.
func play_at(hit_position: Vector3, amount: float, is_headshot: bool) -> void:
	var jitter := Vector3(
		randf_range(-JITTER_RADIUS, JITTER_RADIUS), 0.0,
		randf_range(-JITTER_RADIUS, JITTER_RADIUS))
	global_position = hit_position + jitter
	_label.text = "%d" % maxi(roundi(amount), 0)
	_label.modulate = Color(Tokens.REWARD, 1.0) if is_headshot else Color(Tokens.TEXT, 1.0)
	_label.font_size = HEADSHOT_FONT_SIZE if is_headshot else BODY_FONT_SIZE

	_timer = LIFETIME
	_is_playing = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "position:y", position.y + RISE_HEIGHT, LIFETIME) \
		.set_ease(Tween.EASE_OUT)
	_tween.tween_property(_label, "modulate:a", 0.0, LIFETIME * (1.0 - FADE_START_FRACTION)) \
		.set_delay(LIFETIME * FADE_START_FRACTION)


func _process(delta: float) -> void:
	if not _is_playing:
		return
	_timer -= delta
	if _timer <= 0.0:
		ObjectPool.release(self)


func _on_released() -> void:
	_is_playing = false
	if _tween != null and _tween.is_valid():
		_tween.kill()
