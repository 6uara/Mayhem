extends Node
## Pooled audio playback. Never `add_child(AudioStreamPlayer3D.new())` per shot.
## Decides HOW to play, never WHEN - callers own the trigger logic.

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

var _players_3d: Array[AudioStreamPlayer3D] = []
var _players_2d: Array[AudioStreamPlayer] = []
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
	for i: int in POOL_SIZE_2D:
		var player := AudioStreamPlayer.new()
		player.name = "Player2D_%d" % i
		add_child(player)
		_players_2d.push_back(player)


# Public API

## Positional one-shot. Returns the player used, or null if the pool is exhausted.
func play_3d(stream: AudioStream, position: Vector3, bus: StringName = BUS_SFX,
		volume_db: float = 0.0, pitch_scale: float = 1.0) -> AudioStreamPlayer3D:
	if stream == null:
		return null
	var player: AudioStreamPlayer3D = _find_free_3d()
	if player == null:
		return null
	player.stream = stream
	player.global_position = position
	player.bus = _resolve_bus(bus)
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()
	return player


## Non-positional one-shot (UI, music stings, VO).
func play_2d(stream: AudioStream, bus: StringName = BUS_UI,
		volume_db: float = 0.0, pitch_scale: float = 1.0) -> AudioStreamPlayer:
	if stream == null:
		return null
	var player: AudioStreamPlayer = _find_free_2d()
	if player == null:
		return null
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

func _find_free_3d() -> AudioStreamPlayer3D:
	for player: AudioStreamPlayer3D in _players_3d:
		if not player.playing:
			return player
	push_warning("AudioPool: 3D pool exhausted, dropping a sound")
	return null


func _find_free_2d() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _players_2d:
		if not player.playing:
			return player
	push_warning("AudioPool: 2D pool exhausted, dropping a sound")
	return null


## Falls back to Master when the project's bus layout has not been authored yet.
func _resolve_bus(bus: StringName) -> StringName:
	if AudioServer.get_bus_index(String(bus)) < 0:
		return BUS_MASTER
	return bus


func _apply_duck(offset_db: float) -> void:
	var index: int = AudioServer.get_bus_index(String(BUS_SFX))
	if index < 0:
		return
	var target_db: float = float(_base_db.get(BUS_SFX, 0.0)) + offset_db
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_method(
		func(value: float) -> void: AudioServer.set_bus_volume_db(index, value),
		AudioServer.get_bus_volume_db(index), target_db, DUCK_FADE_TIME)
