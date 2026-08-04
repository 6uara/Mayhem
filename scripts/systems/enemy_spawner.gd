class_name EnemySpawner
extends Node
## Bridges WaveManager to the arena's spawn doors. Registers itself as the wave
## manager's spawner and pools every enemy through the single enemy scene.

@export var enemy_scene: PackedScene
## Prewarmed so no wave ever hitches on instantiation.
##
## This has to cover the largest authored wave, not the first one - falling short
## means the shortfall is instantiated live, and the wave that overruns the pool is
## by construction the biggest one in the run. A test pins it to the actual content
## so raising a wave's counts cannot quietly reintroduce the hitch.
@export var prewarm_count: int = 32

var _doors: Dictionary = {}  # StringName -> SpawnDoor
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	WaveManager.spawner = self
	_collect_doors.call_deferred()
	if enemy_scene != null:
		ObjectPool.prewarm(enemy_scene, prewarm_count)


func _exit_tree() -> void:
	if WaveManager.spawner == self:
		WaveManager.spawner = null


# WaveManager interface

## Lights the doors a group will use and resolves when the tell has played.
## Awaited once per spawn group, before any enemy appears.
func telegraph(door_ids: Array[StringName]) -> void:
	var doors: Array[SpawnDoor] = _matching_doors(door_ids)
	if doors.is_empty():
		return
	for i: int in range(1, doors.size()):
		doors[i].telegraph()  # Light them all; await only the first.
	await doors[0].telegraph()


## Spawns one enemy at one of `door_ids`. Synchronous by design: WaveManager
## counts what comes back, so this must not return a coroutine.
func spawn(enemy_data: EnemyData, door_ids: Array[StringName]) -> Node:
	var door: SpawnDoor = _pick_door(door_ids)
	if door == null:
		push_warning("EnemySpawner: no spawn doors in the scene, spawning at origin")
		return spawn_at(enemy_data, Vector3.ZERO)
	return spawn_at(enemy_data, door.get_spawn_position())


## Dims every door a group was using, once the group has finished spawning.
func close_doors(door_ids: Array[StringName]) -> void:
	for door: SpawnDoor in _matching_doors(door_ids):
		door.close()


## Direct spawn with no door or telegraph - used by Summoners.
func spawn_at(enemy_data: EnemyData, position: Vector3) -> Node:
	if enemy_scene == null or enemy_data == null:
		return null
	var enemy: Node = ObjectPool.acquire(enemy_scene)
	var typed := enemy as Enemy
	if typed == null:
		push_error("EnemySpawner: enemy_scene is not an Enemy")
		return null
	typed.setup(enemy_data, position)
	return typed


# Private

func _collect_doors() -> void:
	_doors.clear()
	for node: Node in get_tree().get_nodes_in_group(&"spawn_door"):
		var door := node as SpawnDoor
		if door != null:
			_doors[door.door_id] = door


## Doors named by the group, falling back to every door in the arena - a group with
## a bad door id still has to spawn, or the wave would never clear.
func _matching_doors(door_ids: Array[StringName]) -> Array[SpawnDoor]:
	if _doors.is_empty():
		_collect_doors()
	var candidates: Array[SpawnDoor] = []
	for id: StringName in door_ids:
		if _doors.has(id):
			candidates.push_back(_doors[id])
	if candidates.is_empty():
		for door: SpawnDoor in _doors.values():
			candidates.push_back(door)
	return candidates


func _pick_door(door_ids: Array[StringName]) -> SpawnDoor:
	var candidates: Array[SpawnDoor] = _matching_doors(door_ids)
	if candidates.is_empty():
		return null
	return candidates[_rng.randi_range(0, candidates.size() - 1)]
