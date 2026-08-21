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

## Lo que significa `t` para el shader, que es al reves de lo que parece.
##
## El wipe es un cuadrado que crece: con t en 0 no hay cuadrado y toda la
## pantalla queda pintada con mask_color -tapada-, y con t en 1 el cuadrado cubre
## todo y la pantalla queda limpia. Nombrar los dos extremos es lo unico que
## evita que el script y el shader se desincronicen, que es exactamente lo que
## habia pasado: fade_out animaba hacia 1, o sea que "tapar la pantalla" la
## destapaba. Apretar Play mostraba el menu abriendose y recien despues la
## partida - dos transiciones donde habia una sola, al reves.
const COVERED_T: float = 0.0
const CLEAR_T: float = 1.0

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
## Hay un fade corriendo. Ver el warm-up en _ready().
var _is_playing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_material = _rect.material as ShaderMaterial
	# Visible un frame, limpio, para que el shader compile ahora y no la primera
	# vez que haga falta una transicion - un shader compilando a mitad de un
	# cambio de escena es un parpadeo con el sistema justo tapando la pantalla.
	_set_t(CLEAR_T)
	_rect.visible = true
	await get_tree().process_frame
	# Solo esconderlo si en ese frame no arranco una transicion de verdad: el
	# await deja un hueco, y apagar la cortina en el medio de un fade la abriria
	# de golpe justo cuando su trabajo es tapar.
	if not _is_playing:
		_rect.visible = false


## Covers the screen. Await this before touching the scene underneath it.
func fade_out() -> void:
	await _play(CLEAR_T, COVERED_T)


## Reveals whatever is now on screen - call once the scene change is done.
func fade_in() -> void:
	await _play(COVERED_T, CLEAR_T)


# Private

func _play(from: float, to: float) -> void:
	_is_playing = true
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

	# Solo deja de tapar cuando termino limpia: un rect invisible no bloquea
	# clicks, y uno tapando la pantalla tiene que seguir bloqueandolos.
	_is_playing = false
	if is_equal_approx(to, CLEAR_T):
		_rect.visible = false


func _set_t(value: float) -> void:
	if _material != null:
		_material.set_shader_parameter(&"t", value)
