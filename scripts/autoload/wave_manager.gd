extends Node
## Wave sequencing, spawn scheduling and wave-clear detection.
## Owns no enemy behavior - it only asks the registered spawner for enemies.
## Phase 0 skeleton: the spawner interface is implemented in Phase 3.

const WAVE_COUNT: int = 10

## Any node with `spawn(enemy_data: EnemyData, door_ids: Array[StringName]) -> Node`.
var spawner: Node

var waves: Array[WaveData] = []
var current_index: int = -1
var is_wave_active: bool = false

var _alive_enemies: int = 0
var _pending_spawns: int = 0
var _wave_start_time: float = 0.0
var _damage_taken_this_wave: float = 0.0


func _ready() -> void:
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.player_died.connect(reset)


# Public API

func setup(wave_list: Array[WaveData]) -> void:
	waves = wave_list
	current_index = -1
	is_wave_active = false


func reset() -> void:
	current_index = -1
	is_wave_active = false
	_alive_enemies = 0
	_pending_spawns = 0
	_damage_taken_this_wave = 0.0


func start_next_wave() -> bool:
	if current_index + 1 >= waves.size():
		return false
	current_index += 1
	var wave: WaveData = waves[current_index]
	is_wave_active = true
	_alive_enemies = 0
	_pending_spawns = wave.get_total_enemy_count()
	_damage_taken_this_wave = 0.0
	_wave_start_time = _now()
	EconomyManager.begin_wave()
	EventBus.wave_started.emit(current_index, wave)
	_schedule_wave(wave)
	return true


func get_current_wave() -> WaveData:
	if current_index < 0 or current_index >= waves.size():
		return null
	return waves[current_index]


func get_wave_duration() -> float:
	return _now() - _wave_start_time


func is_last_wave() -> bool:
	return current_index >= waves.size() - 1


# Private

func _schedule_wave(wave: WaveData) -> void:
	for group: SpawnGroup in wave.spawn_groups:
		if group == null or group.enemy_data == null:
			push_warning("WaveManager: skipping malformed spawn group in wave %d" % current_index)
			_pending_spawns -= group.count if group != null else 0
			continue
		_spawn_group(group)


func _spawn_group(group: SpawnGroup) -> void:
	if group.delay > 0.0:
		await get_tree().create_timer(group.delay).timeout
	for i: int in group.count:
		if not is_wave_active:
			return
		_spawn_one(group)
		if i < group.count - 1 and group.interval > 0.0:
			await get_tree().create_timer(group.interval).timeout


func _spawn_one(group: SpawnGroup) -> void:
	_pending_spawns = maxi(_pending_spawns - 1, 0)
	if spawner == null or not spawner.has_method(&"spawn"):
		push_warning("WaveManager: no spawner registered, enemy not spawned")
		return
	var enemy: Node = spawner.call(&"spawn", group.enemy_data, group.spawn_door_ids)
	if enemy != null:
		_alive_enemies += 1


func _on_enemy_killed(_type: StringName, _position: Vector3, _reward: int) -> void:
	if not is_wave_active:
		return
	_alive_enemies = maxi(_alive_enemies - 1, 0)
	_check_wave_cleared()


func _on_player_damaged(amount: float, _remaining: float) -> void:
	_damage_taken_this_wave += amount


## A wave is clear only when nothing is alive AND nothing is still queued to spawn -
## this covers summoned adds outliving their summoner and enemies killed by hazards.
func _check_wave_cleared() -> void:
	if _alive_enemies > 0 or _pending_spawns > 0:
		return
	is_wave_active = false
	var duration: float = get_wave_duration()
	var wave: WaveData = get_current_wave()
	if wave != null:
		EconomyManager.award_wave_bonuses(wave, duration, _damage_taken_this_wave > 0.0)
	EventBus.wave_completed.emit(current_index, duration, _damage_taken_this_wave)


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
