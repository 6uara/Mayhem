class_name SceneTransition
extends CanvasLayer
## Fades the screen through a shader wipe around every scene change
## `GameManager` drives, so a `change_scene_to_file()` cut never reads as a
## hitch or a crash. `GameManager` owns this as its own child (not part of
## the scene being replaced), so it survives every scene change untouched -
## see docs/Mayhem/07 UI and HUD.md#Scene transitions.
##
## `layer = 10`, above every other CanvasLayer in the game (pause menu, the
## highest otherwise, sits at 4) - a transition has to cover everything, always.

## Wipe duration each way. GameManager's restart budget is "under 2 seconds
## back to a shooting state" - this eats a fraction of it on purpose, short
## enough to leave room for the rest of the sequence.
@export var duration: float = 0.35
## Hard wall-clock ceiling on one fade. If the tween is ever interrupted
## (freed mid-flight, or some future bug), the game must not hang on a black
## screen forever waiting for a signal that will never come. Exported (not a
## const) so a test can shrink it rather than actually waiting out 3 seconds.
@export var safety_timeout: float = 3.0

@onready var _rect: ColorRect = $Rect

var _material: ShaderMaterial


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_material = _rect.material as ShaderMaterial
	_rect.visible = false
	_set_t(0.0)


## Covers the screen. Await this before touching the scene underneath it.
func fade_out() -> void:
	await _play(0.0, 1.0)


## Reveals whatever is now on screen - call once the scene change is done.
func fade_in() -> void:
	await _play(1.0, 0.0)


# Private

func _play(from: float, to: float) -> void:
	_rect.visible = true
	_set_t(from)

	var tween: Tween = create_tween()
	tween.tween_method(_set_t, from, to, duration)

	# Polled rather than `await tween.finished` directly - is_running() flips
	# to false the instant the tween completes on its own, and the loop's own
	# ceiling is what lets a stalled tween be forced rather than awaited forever.
	var elapsed: float = 0.0
	while tween.is_valid() and tween.is_running() and elapsed < safety_timeout:
		await get_tree().process_frame
		elapsed += get_process_delta_time()

	if tween.is_valid() and tween.is_running():
		push_warning("SceneTransition: fade did not finish within %.1fs, forcing it" \
			% safety_timeout)
		tween.kill()
		_set_t(to)

	if to <= 0.0:
		_rect.visible = false


func _set_t(value: float) -> void:
	if _material != null:
		_material.set_shader_parameter(&"t", value)
