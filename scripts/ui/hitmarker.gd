class_name Hitmarker
extends Control
## Hit confirmation. Body, headshot and kill are three visually distinct marks -
## the player must be able to tell them apart without reading anything.

enum Kind { BODY, HEADSHOT, KILL }

const DURATION: float = 0.18

@export var body_color: Color = Color(1, 1, 1, 0.9)
@export var headshot_color: Color = Color(1, 0.45, 0.2, 1)
@export var kill_color: Color = Color(1, 0.15, 0.15, 1)
@export var inner_radius: float = 5.0
@export var outer_radius: float = 11.0

@export_group("Audio")
@export var body_sound: AudioStream
@export var headshot_sound: AudioStream
@export var kill_sound: AudioStream

var _timer: float = 0.0
var _kind: Kind = Kind.BODY


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0


func _process(delta: float) -> void:
	if _timer <= 0.0:
		return
	_timer -= delta
	modulate.a = clampf(_timer / DURATION, 0.0, 1.0)
	if _timer <= 0.0:
		modulate.a = 0.0


func _draw() -> void:
	var center := size * 0.5
	var scale_factor: float = 1.35 if _kind == Kind.KILL else 1.0
	for direction: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		var normalized: Vector2 = direction.normalized()
		draw_line(center + normalized * inner_radius * scale_factor,
			center + normalized * outer_radius * scale_factor, _get_color(), 2.0)


# Public API

func show_hit(kind: Kind) -> void:
	_kind = kind
	_timer = DURATION
	modulate.a = 1.0
	queue_redraw()
	AudioPool.play_2d(_get_sound(), AudioPool.BUS_UI)


# Private

func _get_color() -> Color:
	match _kind:
		Kind.HEADSHOT: return headshot_color
		Kind.KILL: return kill_color
	return body_color


func _get_sound() -> AudioStream:
	match _kind:
		Kind.HEADSHOT: return headshot_sound
		Kind.KILL: return kill_sound
	return body_sound
