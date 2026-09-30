class_name EnemyModelMotion
extends Node
## Anima el modelo de un enemigo sin clips: flotar, oscilar, girar, inclinarse
## hacia donde avanza, respirar e inflarse al usar su habilidad.
##
## Mismo razonamiento que `LeggedGait`: los modelos llegan quietos, y una
## animacion derivada del estado del cuerpo no se puede desincronizar de el. El
## Bomber que flota y gira mas rapido con la espoleta armada, o el Healer que se
## infla en el instante en que cura, salen de leer al enemigo, no de una linea de
## tiempo autorada.
##
## Si el modelo trae un AnimationPlayer con clips, tambien los usa: busca por
## nombre uno de reposo, uno de movimiento y uno de habilidad, y los reproduce
## segun el mismo estado. Lo procedural va encima, asi que un modelo con clips
## igual flota y se inclina si su arquetipo lo pide.
##
## Todos los valores viven en `EnemyData` (grupo "Model motion"). Es cosmetico:
## escribe solo el transform del modelo, nunca el del cuerpo ni las hitboxes.

## Nombres, en minusculas, que se aceptan para cada clip. Se busca por contenido,
## asi "Armature|Idle_Loop" cuenta como reposo.
const IDLE_CLIP_HINTS: Array[String] = ["idle", "hover", "float", "rest"]
const MOVE_CLIP_HINTS: Array[String] = ["walk", "run", "move", "fly"]
const CAST_CLIP_HINTS: Array[String] = ["cast", "heal", "attack", "shoot", "spell"]

## Velocidad horizontal a la que la inclinacion llega a `model_lean_degrees`.
const LEAN_FULL_SPEED: float = 5.0
## Por encima de esto el enemigo cuenta como en movimiento para elegir clip.
const MOVE_SPEED_THRESHOLD: float = 0.4
## Cuanto dura el inflado de la habilidad.
const CAST_POP_TIME: float = 0.45
## Con la espoleta armada todo va mas rapido y tiembla: es el aviso de que va a
## reventar, ademas del parpadeo y el sonido que ya tiene.
const FUSE_BOB_MULTIPLIER: float = 3.5
const FUSE_SPIN_MULTIPLIER: float = 4.0
const FUSE_SHAKE: float = 0.035
## Que tan rapido la inclinacion sigue a la velocidad. Sin suavizado, cada
## correccion del steering se ve como un tic.
const LEAN_SMOOTHING: float = 6.0

var _model: Node3D
var _enemy: Enemy
var _rest_position: Vector3 = Vector3.ZERO
var _rest_scale: Vector3 = Vector3.ONE
## La orientacion de reposo entera, sin escala: yaw y tambien el cabeceo que
## corrige a un modelo que llego acostado. Guardar solo el yaw lo volvia a acostar.
var _rest_rotation: Basis = Basis.IDENTITY

var _phase: float = 0.0
var _spin: float = 0.0
var _lean: Vector3 = Vector3.ZERO
var _cast_left: float = 0.0

var _player: AnimationPlayer
## Clip elegido a mano (el visor de enemigos). Mientras este puesto, la eleccion
## automatica por estado no toca el AnimationPlayer.
var _clip_override: StringName = &""
var _idle_clip: StringName = &""
var _move_clip: StringName = &""
var _cast_clip: StringName = &""


## Devuelve false cuando el arquetipo no pide nada y el modelo no trae clips, para
## que quien llama no pague un nodo que no hace nada cada frame.
func setup(model: Node3D, enemy: Enemy) -> bool:
	_model = model
	_enemy = enemy
	if _model == null or _enemy == null or _enemy.data == null:
		return false
	_find_clips(model)
	if not _wants_procedural() and _player == null:
		return false
	if not _enemy.ability_used.is_connected(_on_ability_used):
		_enemy.ability_used.connect(_on_ability_used)
	capture_rest()
	return true


## Los clips que trae el modelo, sin RESET. Vacio si no trae ninguno.
func get_clip_names() -> Array[StringName]:
	var out: Array[StringName] = []
	if _player == null:
		return out
	for clip_name: String in _player.get_animation_list():
		if clip_name != "RESET":
			out.append(StringName(clip_name))
	return out


## Reproduce un clip a mano y suspende la eleccion automatica. `&""` la devuelve.
func set_clip_override(clip: StringName) -> void:
	_clip_override = clip
	if _player == null:
		return
	if clip != &"" and _player.has_animation(clip):
		_player.play(clip)
	elif clip == &"":
		_player.stop()


## Toma la pose actual del modelo como la de reposo. `Enemy` la llama despues de
## ubicar el modelo, que es cuando esa pose es la correcta.
func capture_rest() -> void:
	if _model == null:
		return
	_rest_position = _model.position
	_rest_scale = _model.scale
	_rest_rotation = _model.basis.orthonormalized()
	# Cada uno con su fase: cinco bombas que suben y bajan juntas se leen como una
	# sola cosa rigida, no como cinco que flotan.
	_phase = randf() * TAU
	_spin = 0.0
	_lean = Vector3.ZERO
	_cast_left = 0.0
	_play_loop(_idle_clip)


func _process(delta: float) -> void:
	if _model == null or _enemy == null or _enemy.data == null:
		return
	var data: EnemyData = _enemy.data
	var fused: bool = _enemy.is_fuse_armed()
	var horizontal := Vector3(_enemy.velocity.x, 0.0, _enemy.velocity.z)
	var speed: float = horizontal.length()

	_cast_left = maxf(_cast_left - delta, 0.0)
	_tick_clips(speed)

	var bob_rate: float = data.model_bob_rate * (FUSE_BOB_MULTIPLIER if fused else 1.0)
	_phase = fmod(_phase + bob_rate * TAU * delta, TAU)
	var spin_rate: float = data.model_spin_degrees_per_second \
		* (FUSE_SPIN_MULTIPLIER if fused else 1.0)
	_spin = fmod(_spin + deg_to_rad(spin_rate) * delta, TAU)

	# Posicion: flotar, oscilar y, con la espoleta armada, temblar.
	var position: Vector3 = _rest_position \
		+ Vector3.UP * (data.model_hover_height + sin(_phase) * data.model_bob_height)
	if fused:
		position += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)) * FUSE_SHAKE

	# Inclinacion hacia donde avanza, medida en el espacio del cuerpo: el cuerpo
	# gira para mirar, y la inclinacion tiene que acompañarlo.
	var goal := Vector3.ZERO
	if data.model_lean_degrees > 0.0 and speed > 0.05:
		var local: Vector3 = _enemy.global_basis.inverse() * horizontal
		local.y = 0.0
		var amount: float = clampf(speed / LEAN_FULL_SPEED, 0.0, 1.0)
		goal = local.normalized() * amount
	_lean = _lean.lerp(goal, clampf(LEAN_SMOOTHING * delta, 0.0, 1.0))

	# El giro va en el espacio del padre (vertical del mundo), encima del reposo.
	var basis := Basis(Vector3.UP, _spin) * _rest_rotation
	if _lean.length_squared() > 0.000001:
		var axis: Vector3 = Vector3.UP.cross(_lean).normalized()
		basis = Basis(axis, deg_to_rad(data.model_lean_degrees) * _lean.length()) * basis

	# Respirar estira en alto y afina en ancho, para que el volumen no cambie a la
	# vista. El inflado de la habilidad es parejo y sale con una curva que sube
	# rapido y baja lento.
	var breathe: float = sin(_phase * 0.5) * data.model_breathe
	var stretch := Vector3(1.0 - breathe * 0.5, 1.0 + breathe, 1.0 - breathe * 0.5)
	var pop: float = 0.0
	if _cast_left > 0.0:
		var t: float = 1.0 - _cast_left / CAST_POP_TIME
		pop = sin(t * PI) * (1.0 - t * 0.5) * data.model_cast_pop
	# La preparacion del ataque tambien se ve en el cuerpo, no solo en el brillo.
	pop += _enemy.windup_progress * data.model_cast_pop * 0.4

	_model.transform = Transform3D(basis.scaled(_rest_scale * stretch * (1.0 + pop)),
		position)


# Private

func _wants_procedural() -> bool:
	var data: EnemyData = _enemy.data
	return data.model_hover_height != 0.0 or data.model_bob_height != 0.0 \
		or data.model_spin_degrees_per_second != 0.0 or data.model_lean_degrees != 0.0 \
		or data.model_breathe != 0.0 or data.model_cast_pop != 0.0 or data.has_fuse


func _on_ability_used() -> void:
	_cast_left = CAST_POP_TIME
	if _player != null and _cast_clip != &"" and _clip_override == &"":
		_player.play(_cast_clip)


func _tick_clips(speed: float) -> void:
	if _player == null or _clip_override != &"":
		return
	# La habilidad no se corta: termina y recien ahi vuelve el loop.
	if _cast_clip != &"" and _player.current_animation == _cast_clip and _player.is_playing():
		return
	var moving: bool = speed > MOVE_SPEED_THRESHOLD and _move_clip != &""
	_play_loop(_move_clip if moving else _idle_clip)


func _play_loop(clip: StringName) -> void:
	if _player == null or clip == &"" or _player.current_animation == clip:
		return
	_player.play(clip, 0.2)


func _find_clips(node: Node) -> void:
	_player = _find_player(node)
	if _player == null:
		return
	var names: PackedStringArray = _player.get_animation_list()
	# RESET es el que el importador genera con la pose de reposo, no un clip.
	var usable: Array[StringName] = []
	for clip_name: String in names:
		if clip_name != "RESET":
			usable.append(StringName(clip_name))
	if usable.is_empty():
		_player = null
		return
	_idle_clip = _match(usable, IDLE_CLIP_HINTS)
	_move_clip = _match(usable, MOVE_CLIP_HINTS)
	_cast_clip = _match(usable, CAST_CLIP_HINTS)
	# Un solo clip sin nombre reconocible es casi siempre el loop de reposo.
	if _idle_clip == &"" and _move_clip == &"" and _cast_clip == &"":
		_idle_clip = usable[0]
	if _idle_clip == &"":
		_idle_clip = _move_clip
	for loop_clip: StringName in [_idle_clip, _move_clip]:
		if loop_clip != &"":
			_player.get_animation(loop_clip).loop_mode = Animation.LOOP_LINEAR


func _match(clips: Array[StringName], hints: Array[String]) -> StringName:
	for clip: StringName in clips:
		var lower: String = String(clip).to_lower()
		for hint: String in hints:
			if lower.contains(hint):
				return clip
	return &""


func _find_player(node: Node) -> AnimationPlayer:
	var player := node as AnimationPlayer
	if player != null:
		return player
	for child: Node in node.get_children():
		var found: AnimationPlayer = _find_player(child)
		if found != null:
			return found
	return null
