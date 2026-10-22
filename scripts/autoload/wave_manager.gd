extends Node
## Wave sequencing, spawn scheduling and wave-clear detection.
## Owns no enemy behavior - it asks the registered spawner for enemies and counts
## what is alive.

const WAVE_COUNT: int = 10
## Segundos de juego sin progreso -ninguna kill, ningun golpe a un enemigo- con
## todo ya spawneado antes de dar la oleada por trabada. Ver _rescue_stalled_wave().
const STALL_TIME: float = 40.0

## Any node with `spawn(enemy_data: EnemyData, door_ids: Array[StringName]) -> Node`.
var spawner: Node

var waves: Array[WaveData] = []
var current_index: int = -1
var is_wave_active: bool = false

var _alive_enemies: int = 0
var _pending_spawns: int = 0
var _wave_start_time: float = 0.0
## GameManager.get_paused_seconds() al arrancar la oleada: la pausa no corre el PAR.
var _wave_paused_at_start: float = 0.0
var _damage_taken_this_wave: float = 0.0
## Bumped on reset so in-flight spawn coroutines from an abandoned wave die off.
var _run_generation: int = 0
var _last_breakdown: Dictionary = {}
## Los enemigos que largo esta oleada, por instance id. Un cuerpo del pool que
## vuelve a salir en la misma oleada pisa su propia entrada, asi que no se cuenta
## dos veces.
var _tracked: Dictionary = {}
## Spawns que no devolvieron un Enemy (los dobles de los tests). Con alguno, el
## conteo de vivos no se puede verificar contra los cuerpos y no se corrige.
var _untracked_spawns: int = 0
var _stall_time: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.player_damaged.connect(_on_player_damaged)
	# `stop()` y no `reset()`: la oleada deja de spawnear, pero `current_index`
	# sigue diciendo en cual se murio. Este autoload se conecta antes que
	# MatchDirector, y resetear aca dejaba toda derrota anotada con 0 oleadas.
	EventBus.player_died.connect(stop)


func _process(delta: float) -> void:
	# Solo con todo spawneado: un grupo que llega a los 40 segundos no es una
	# oleada trabada, es una oleada que todavia no termino de llegar.
	if not is_wave_active or _pending_spawns > 0:
		_stall_time = 0.0
		return
	_stall_time += delta
	if _stall_time >= STALL_TIME:
		_stall_time = 0.0
		_rescue_stalled_wave()


# Public API

func setup(wave_list: Array[WaveData]) -> void:
	waves = wave_list
	current_index = -1
	is_wave_active = false


func reset() -> void:
	stop()
	current_index = -1


## Corta la oleada en curso -los spawns en vuelo mueren por la generacion- sin
## olvidar que oleada era.
func stop() -> void:
	_run_generation += 1
	is_wave_active = false
	_alive_enemies = 0
	_pending_spawns = 0
	_damage_taken_this_wave = 0.0
	_forget_spawns()


func start_next_wave() -> bool:
	if current_index + 1 >= waves.size():
		return false
	current_index += 1
	var wave: WaveData = waves[current_index]
	is_wave_active = true
	_alive_enemies = 0
	_pending_spawns = wave.get_total_enemy_count()
	_damage_taken_this_wave = 0.0
	_forget_spawns()
	_wave_start_time = _now()
	_wave_paused_at_start = GameManager.get_paused_seconds()
	EconomyManager.begin_wave()
	EventBus.wave_started.emit(current_index, wave)
	_schedule_wave(wave, _run_generation)
	return true


## Adds spawned by a Summoner. They count toward the wave, so a wave cannot be
## declared clear while adds are still alive - and they still count if their
## summoner dies first.
func spawn_summoned(enemy_data: EnemyData, position: Vector3) -> Node:
	if not is_wave_active or enemy_data == null:
		return null
	var enemy: Node = _spawn_at(enemy_data, position)
	if enemy != null:
		_alive_enemies += 1
		_track(enemy)
	return enemy


func get_current_wave() -> WaveData:
	if current_index < 0 or current_index >= waves.size():
		return null
	return waves[current_index]


## Tiempo de juego de la oleada: de pared, menos lo que se estuvo en pausa. Es
## lo que paga el bono de velocidad, asi que pausar no puede costar plata.
func get_wave_duration() -> float:
	return _now() - _wave_start_time \
		- (GameManager.get_paused_seconds() - _wave_paused_at_start)


func get_alive_count() -> int:
	return _alive_enemies


func get_remaining_count() -> int:
	return _alive_enemies + _pending_spawns


func is_last_wave() -> bool:
	return current_index >= waves.size() - 1


func get_damage_taken_this_wave() -> float:
	return _damage_taken_this_wave


## The last wave's itemised payout, for the wave-complete breakdown screen.
## Empty until a wave has been cleared.
func get_last_breakdown() -> Dictionary:
	return _last_breakdown


# Private

func _schedule_wave(wave: WaveData, generation: int) -> void:
	for group: SpawnGroup in wave.spawn_groups:
		if group == null or group.enemy_data == null:
			var skipped: int = group.count if group != null else 0
			push_warning("WaveManager: skipping malformed spawn group in wave %d" % current_index)
			_pending_spawns = maxi(_pending_spawns - skipped, 0)
			continue
		_spawn_group(group, generation)
	# A wave whose groups were all malformed would otherwise never complete.
	_check_wave_cleared()


func _spawn_group(group: SpawnGroup, generation: int) -> void:
	# `process_always = false` en los dos timers: con el arbol en pausa la oleada
	# no sigue largando enemigos, que al despausar aparecian todos juntos.
	if group.delay > 0.0:
		await get_tree().create_timer(group.delay, false).timeout
	if generation != _run_generation or not is_wave_active:
		return

	# The door tell plays before anything comes out of it, so the player can
	# pre-position (CLAUDE.md 5.3).
	if spawner != null and spawner.has_method(&"telegraph"):
		await spawner.call(&"telegraph", group.spawn_door_ids)
	if generation != _run_generation or not is_wave_active:
		return

	for i: int in group.count:
		if generation != _run_generation or not is_wave_active:
			return
		_spawn_one(group)
		if i < group.count - 1 and group.interval > 0.0:
			await get_tree().create_timer(group.interval, false).timeout

	if spawner != null and spawner.has_method(&"close_doors"):
		spawner.call(&"close_doors", group.spawn_door_ids)
	_check_wave_cleared()


func _spawn_one(group: SpawnGroup) -> void:
	_pending_spawns = maxi(_pending_spawns - 1, 0)
	if spawner == null or not spawner.has_method(&"spawn"):
		push_warning("WaveManager: no spawner registered, enemy not spawned")
		return
	var enemy: Node = spawner.call(&"spawn", group.enemy_data, group.spawn_door_ids)
	if enemy != null:
		_alive_enemies += 1
		_track(enemy)


func _spawn_at(enemy_data: EnemyData, position: Vector3) -> Node:
	if spawner == null or not spawner.has_method(&"spawn_at"):
		push_warning("WaveManager: no spawner registered for summoned add")
		return null
	return spawner.call(&"spawn_at", enemy_data, position)


func _on_enemy_killed(_type: StringName, _position: Vector3, _reward: int) -> void:
	if not is_wave_active:
		return
	_stall_time = 0.0
	_alive_enemies = maxi(_alive_enemies - 1, 0)
	_check_wave_cleared()


func _on_player_damaged(amount: float, _remaining: float) -> void:
	_damage_taken_this_wave += amount


## A wave is clear only when nothing is alive AND nothing is still queued to spawn.
## That covers enemies killed by hazards and adds outliving their summoner.
func _check_wave_cleared() -> void:
	if not is_wave_active or _alive_enemies > 0 or _pending_spawns > 0:
		return
	is_wave_active = false
	var duration: float = get_wave_duration()
	var wave: WaveData = get_current_wave()
	if wave != null:
		_last_breakdown = EconomyManager.award_wave_bonuses(
			wave, duration, _damage_taken_this_wave > 0.0)
	EventBus.wave_completed.emit(current_index, duration, _damage_taken_this_wave)


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


# Red de ultimo recurso

func _on_damage_dealt(_target: Node, amount: float, _is_headshot: bool) -> void:
	if amount > 0.0:
		_stall_time = 0.0


func _track(enemy: Node) -> void:
	var typed := enemy as Enemy
	if typed == null:
		_untracked_spawns += 1
		return
	_tracked[typed.get_instance_id()] = typed


func _forget_spawns() -> void:
	_tracked.clear()
	_untracked_spawns = 0
	_stall_time = 0.0


## Lo que pasa cuando la oleada lleva STALL_TIME sin que nadie muera ni reciba un
## golpe, con todo ya spawneado. No deberia pasar nunca: el guardia de la arena
## (Enemy._tick_arena_guard) devuelve a los que quedan afuera y el destrabe por
## reloj saca a los encajados. Esto existe porque el playtest del 2026-10-21
## reporto una run que no se pudo terminar, y una run que no termina es el peor
## bug que puede tener el juego - peor que cualquier cosa que esta red pueda hacer
## mal. Dos fallas posibles, las dos se arreglan aca:
##
## - El conteo dice que hay vivos que ya no existen (un cuerpo que volvio al pool
##   sin `enemy_killed`). Se corrige el conteo con los cuerpos de verdad.
## - Hay vivos, pero donde nadie los encuentra. Vuelven a entrar por una puerta,
##   que es por donde el jugador ya espera verlos llegar.
func _rescue_stalled_wave() -> void:
	var live: Array[Enemy] = []
	for id: int in _tracked.keys():
		# Variant primero: un cuerpo liberado no se puede asignar a una variable tipada.
		var entry: Variant = _tracked[id]
		var enemy: Enemy = entry as Enemy if is_instance_valid(entry) else null
		if enemy != null and enemy.is_active and enemy.health != null \
				and not enemy.health.is_dead:
			live.append(enemy)
		else:
			_tracked.erase(id)
	if _untracked_spawns == 0 and live.size() < _alive_enemies:
		push_warning("WaveManager: la oleada contaba %d vivos y hay %d; se corrige"
			% [_alive_enemies, live.size()])
		_alive_enemies = live.size()
		_check_wave_cleared()
		if not is_wave_active:
			return
	var points: Array = []
	if spawner != null and spawner.has_method(&"get_rescue_points"):
		points = spawner.call(&"get_rescue_points")
	for enemy: Enemy in live:
		var point: Vector3 = enemy.arena_return_point(enemy.global_position)
		if not points.is_empty():
			point = points[_rng.randi_range(0, points.size() - 1)]
		enemy.return_to_arena(point)
	EventBus.wave_stall_rescued.emit(current_index, live.size())
