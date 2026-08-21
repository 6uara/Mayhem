extends Node
## Pooled audio playback. Never `add_child(AudioStreamPlayer3D.new())` per shot.
## Decides HOW to play, never WHEN - callers own the trigger logic.
##
## Y cuando no hay voces libres, decide QUÉ se calla. Sin eso el orden de llegada
## era la única regla: en una ola elite (27 enemigos, una SMG a 15 balas/segundo,
## un impacto por bala) el disparo del jugador podía perder contra el paso de un
## bicho, que es el pilar 1 del proyecto perdiendo contra ruido de fondo.

## Qué se pierde si este sonido no suena. Es lo único que ordena el robo de voces.
##
## No es "qué tan importante es" en abstracto - es una escala de daño concreto:
## un impacto que falta no se nota, un aviso que falta es daño sin explicación, y
## un disparo que falta rompe el juego entero.
enum Priority {
	## Cosmético y numeroso. Es el primero que se sacrifica, y es el que inunda:
	## una bala por impacto, quince por segundo.
	AMBIENT = 0,
	## El default de casi todo. Un enemigo, un pickup, una puerta.
	NORMAL = 1,
	## La promesa de que algo va a doler: wind-ups, la espoleta del Bomber, el
	## aviso del charco, la plataforma que se desvanece. Un telegraph que no suena
	## es daño sin aviso, que es la regla que CLAUDE.md 5.3 no deja romper - y no
	## se puede confiar en el bus para esto, porque los avisos están repartidos
	## entre `Enemies` y `World`.
	TELEGRAPH = 2,
	## El arma del jugador y la voz del Host. Nunca se caen.
	CRITICAL = 3,
}

const BUS_MASTER: StringName = &"Master"
const BUS_SFX: StringName = &"SFX"
const BUS_WEAPONS: StringName = &"Weapons"
const BUS_IMPACTS: StringName = &"Impacts"
const BUS_ENEMIES: StringName = &"Enemies"
const BUS_WORLD: StringName = &"World"
const BUS_MUSIC: StringName = &"Music"
const BUS_VO: StringName = &"VO"
const BUS_UI: StringName = &"UI"

const POOL_SIZE_3D: int = 48
const POOL_SIZE_2D: int = 16
## Decibel offset applied to non-VO buses while narrator VO is playing.
const DUCK_AMOUNT_DB: float = -8.0
const DUCK_FADE_TIME: float = 0.15

## Prioridad por bus, para que las cuarenta llamadas que ya existen queden bien
## clasificadas sin tocar ninguna: el bus ya dice de qué es cada sonido.
## `tools/configure_audio_mix.gd` describía esta jerarquía como ganancia ("VO y
## Weapons arriba, UI abajo"); esto es la mitad que faltaba, que es asignación de
## voces y no volumen.
##
## `Impacts` es el único que baja de NORMAL, y es a propósito: es el bus más
## numeroso de todos y el que menos se extraña. Lo que no entra acá - los avisos -
## no se puede deducir del bus y viaja por parámetro.
const BUS_PRIORITY: Dictionary = {
	BUS_WEAPONS: Priority.CRITICAL,
	BUS_VO: Priority.CRITICAL,
	BUS_IMPACTS: Priority.AMBIENT,
}

var _players_3d: Array[AudioStreamPlayer3D] = []
var _players_2d: Array[AudioStreamPlayer] = []
## Con qué prioridad está sonando cada voz, en el mismo orden que los arrays de
## arriba. Paralelo y no un diccionario por jugador: se recorre entero en cada
## robo y esto se recorre sin tocar el heap.
var _priority_3d: PackedInt32Array = PackedInt32Array()
var _priority_2d: PackedInt32Array = PackedInt32Array()
## Cuándo arrancó cada voz, para desempatar robando la más vieja.
var _started_3d: PackedFloat64Array = PackedFloat64Array()
var _started_2d: PackedFloat64Array = PackedFloat64Array()
var _duck_refs: int = 0
var _duck_tween: Tween
## bus -> user volume in dB, owned here so ducking never fights the settings menu.
var _base_db: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i: int in POOL_SIZE_3D:
		var player := AudioStreamPlayer3D.new()
		player.name = "Player3D_%d" % i
		add_child(player)
		_players_3d.push_back(player)
	_priority_3d.resize(POOL_SIZE_3D)
	_started_3d.resize(POOL_SIZE_3D)
	for i: int in POOL_SIZE_2D:
		var player := AudioStreamPlayer.new()
		player.name = "Player2D_%d" % i
		add_child(player)
		_players_2d.push_back(player)
	_priority_2d.resize(POOL_SIZE_2D)
	_started_2d.resize(POOL_SIZE_2D)


# Public API

## Positional one-shot. Returns the player used, or null if the pool is exhausted.
##
## `priority` por defecto sale del bus (ver `BUS_PRIORITY`). Se pasa a mano sólo
## cuando el bus no alcanza para saberlo, que en la práctica es un caso: los
## avisos, que viven repartidos entre `Enemies` y `World`.
func play_3d(stream: AudioStream, position: Vector3, bus: StringName = BUS_SFX,
		volume_db: float = 0.0, pitch_scale: float = 1.0,
		priority: int = -1) -> AudioStreamPlayer3D:
	if stream == null:
		return null
	var level: int = _resolve_priority(bus, priority)
	var index: int = _claim_3d(level)
	if index < 0:
		return null
	var player: AudioStreamPlayer3D = _players_3d[index]
	_priority_3d[index] = level
	_started_3d[index] = Time.get_ticks_msec() / 1000.0
	player.stream = stream
	player.global_position = position
	player.bus = _resolve_bus(bus)
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()
	return player


## Non-positional one-shot (UI, music stings, VO).
func play_2d(stream: AudioStream, bus: StringName = BUS_UI,
		volume_db: float = 0.0, pitch_scale: float = 1.0,
		priority: int = -1) -> AudioStreamPlayer:
	if stream == null:
		return null
	var level: int = _resolve_priority(bus, priority)
	var index: int = _claim_2d(level)
	if index < 0:
		return null
	var player: AudioStreamPlayer = _players_2d[index]
	_priority_2d[index] = level
	_started_2d[index] = Time.get_ticks_msec() / 1000.0
	player.stream = stream
	player.bus = _resolve_bus(bus)
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()
	return player


func stop_all() -> void:
	for player: AudioStreamPlayer3D in _players_3d:
		player.stop()
	for player: AudioStreamPlayer in _players_2d:
		player.stop()


## Set a bus's user volume (0..1 linear). SettingsManager owns the value, AudioPool owns
## the final dB so a duck in progress is never clobbered by the settings menu.
func set_bus_volume_linear(bus: StringName, linear: float) -> void:
	var index: int = AudioServer.get_bus_index(String(bus))
	if index < 0:
		return
	_base_db[bus] = linear_to_db(clampf(linear, 0.0, 1.0))
	if bus == BUS_SFX and _duck_refs > 0:
		AudioServer.set_bus_volume_db(index, _base_db[bus] + DUCK_AMOUNT_DB)
	else:
		AudioServer.set_bus_volume_db(index, _base_db[bus])


## Reference-counted ducking, so overlapping VO lines do not un-duck early.
func push_duck() -> void:
	_duck_refs += 1
	if _duck_refs == 1:
		_apply_duck(DUCK_AMOUNT_DB)


func pop_duck() -> void:
	_duck_refs = maxi(_duck_refs - 1, 0)
	if _duck_refs == 0:
		_apply_duck(0.0)


# Private

func _resolve_priority(bus: StringName, requested: int) -> int:
	if requested >= 0:
		return requested
	return int(BUS_PRIORITY.get(bus, Priority.NORMAL))


## Una voz para este sonido: primero una libre, y si no hay, una que valga menos.
##
## El robo pide prioridad **estrictamente** menor. Con "menor o igual" un disparo
## se cortaría a sí mismo al segundo tiro de la ráfaga, que es peor que el
## problema que esto arregla.
##
## Devuelve el índice y no el jugador porque quien llama tiene que anotar con qué
## prioridad quedó ocupada la voz, y esa anotación vive en un array paralelo.
func _claim_3d(priority: int) -> int:
	for i: int in _players_3d.size():
		if not _players_3d[i].playing:
			return i

	# Entre las robables, la que menos se va a extrañar: primero la de menor
	# prioridad, y a igual prioridad la más lejana del oyente - un impacto a
	# treinta metros ya casi no se escucha, y uno a dos metros sí.
	var listener: Vector3 = _listener_position()
	var victim: int = -1
	var victim_priority: int = priority
	var victim_distance: float = -1.0
	for i: int in _players_3d.size():
		var candidate: int = _priority_3d[i]
		if candidate >= priority:
			continue
		var distance: float = listener.distance_squared_to(_players_3d[i].global_position)
		if victim < 0 or candidate < victim_priority \
				or (candidate == victim_priority and distance > victim_distance):
			victim = i
			victim_priority = candidate
			victim_distance = distance

	if victim < 0:
		push_warning("AudioPool: 3D pool exhausted, dropping a sound")
		return -1
	_players_3d[victim].stop()
	return victim


## Igual que la de arriba pero sin distancia: un sonido no posicional no está en
## ningún lado, así que el desempate es la voz más vieja, que es la que más cerca
## está de terminarse sola.
func _claim_2d(priority: int) -> int:
	for i: int in _players_2d.size():
		if not _players_2d[i].playing:
			return i

	var victim: int = -1
	var victim_priority: int = priority
	var victim_started: float = 0.0
	for i: int in _players_2d.size():
		var candidate: int = _priority_2d[i]
		if candidate >= priority:
			continue
		if victim < 0 or candidate < victim_priority \
				or (candidate == victim_priority and _started_2d[i] < victim_started):
			victim = i
			victim_priority = candidate
			victim_started = _started_2d[i]

	if victim < 0:
		push_warning("AudioPool: 2D pool exhausted, dropping a sound")
		return -1
	_players_2d[victim].stop()
	return victim


## Dónde escucha el jugador. Sin cámara - un test, o el menú - todas las
## distancias dan lo mismo y el desempate cae en la primera candidata, que es
## exactamente el comportamiento viejo.
func _listener_position() -> Vector3:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	return camera.global_position if camera != null else Vector3.ZERO


## Falls back to Master when the project's bus layout has not been authored yet.
func _resolve_bus(bus: StringName) -> StringName:
	if AudioServer.get_bus_index(String(bus)) < 0:
		return BUS_MASTER
	return bus


## Ducks SFX and Music together - one ref-counted mechanism, not two, so a VO
## line ducking music and a second one ducking SFX can never fall out of sync.
func _apply_duck(offset_db: float) -> void:
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.set_parallel(true)
	for bus: StringName in [BUS_SFX, BUS_MUSIC]:
		var index: int = AudioServer.get_bus_index(String(bus))
		if index < 0:
			continue
		var target_db: float = float(_base_db.get(bus, 0.0)) + offset_db
		_duck_tween.tween_method(
			func(value: float) -> void: AudioServer.set_bus_volume_db(index, value),
			AudioServer.get_bus_volume_db(index), target_db, DUCK_FADE_TIME)
