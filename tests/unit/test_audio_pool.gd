extends GutTest
## AudioPool: pooled playback, bus volume/ducking. Previously zero test files.

const A_SOUND: String = "res://assets/audio/sfx/world/jump.wav"

var _stream: AudioStream
var _saved_bus_db: Dictionary = {}


func before_each() -> void:
	_stream = load(A_SOUND)
	# Buses this file touches - restore afterward so a test can't leave the
	# real mix (default_bus_layout.tres) altered for whatever runs next.
	for bus: StringName in [AudioPool.BUS_SFX, AudioPool.BUS_MUSIC]:
		var index: int = AudioServer.get_bus_index(String(bus))
		if index >= 0:
			_saved_bus_db[bus] = AudioServer.get_bus_volume_db(index)


func after_each() -> void:
	AudioPool.stop_all()
	while AudioPool._duck_refs > 0:
		AudioPool.pop_duck()
	for bus: StringName in _saved_bus_db:
		var index: int = AudioServer.get_bus_index(String(bus))
		if index >= 0:
			AudioServer.set_bus_volume_db(index, _saved_bus_db[bus])


# play_3d / play_2d

func test_play_3d_with_a_null_stream_returns_null_without_erroring() -> void:
	assert_null(AudioPool.play_3d(null, Vector3.ZERO))


func test_play_2d_with_a_null_stream_returns_null_without_erroring() -> void:
	assert_null(AudioPool.play_2d(null))


func test_play_3d_returns_a_playing_player_at_the_given_position() -> void:
	var position := Vector3(1, 2, 3)
	var player: AudioStreamPlayer3D = AudioPool.play_3d(_stream, position)
	assert_not_null(player)
	assert_true(player.playing)
	assert_eq(player.global_position, position)


func test_play_2d_returns_a_playing_player() -> void:
	var player: AudioStreamPlayer = AudioPool.play_2d(_stream)
	assert_not_null(player)
	assert_true(player.playing)


func test_play_3d_resolves_an_unknown_bus_to_master() -> void:
	var player: AudioStreamPlayer3D = AudioPool.play_3d(_stream, Vector3.ZERO, &"NoSuchBus")
	assert_eq(player.bus, AudioPool.BUS_MASTER)


func test_play_3d_pool_exhaustion_drops_the_sound_and_warns() -> void:
	var players: Array[AudioStreamPlayer3D] = []
	for i: int in AudioPool.POOL_SIZE_3D:
		players.push_back(AudioPool.play_3d(_stream, Vector3.ZERO))
	assert_null(AudioPool.play_3d(_stream, Vector3.ZERO),
		"every 3D voice is busy - the next request must be dropped, not crash")
	assert_push_warning("3D pool exhausted")


func test_stop_all_stops_every_active_player() -> void:
	AudioPool.play_3d(_stream, Vector3.ZERO)
	AudioPool.play_2d(_stream)
	AudioPool.stop_all()
	for player: AudioStreamPlayer3D in AudioPool._players_3d:
		assert_false(player.playing)
	for player: AudioStreamPlayer in AudioPool._players_2d:
		assert_false(player.playing)


# Bus volume

func test_set_bus_volume_linear_converts_to_decibels() -> void:
	AudioPool.set_bus_volume_linear(AudioPool.BUS_SFX, 0.5)
	var index: int = AudioServer.get_bus_index("SFX")
	assert_almost_eq(AudioServer.get_bus_volume_db(index), linear_to_db(0.5), 0.01)


func test_set_bus_volume_linear_clamps_above_unity() -> void:
	AudioPool.set_bus_volume_linear(AudioPool.BUS_SFX, 5.0)
	var index: int = AudioServer.get_bus_index("SFX")
	assert_almost_eq(AudioServer.get_bus_volume_db(index), linear_to_db(1.0), 0.01)


func test_set_bus_volume_linear_clamps_below_zero() -> void:
	AudioPool.set_bus_volume_linear(AudioPool.BUS_SFX, -1.0)
	var index: int = AudioServer.get_bus_index("SFX")
	assert_almost_eq(AudioServer.get_bus_volume_db(index), linear_to_db(0.0), 0.01)


# Ducking - reference counted, moves SFX and Music together

func test_push_duck_lowers_sfx_and_music_together() -> void:
	AudioPool.set_bus_volume_linear(AudioPool.BUS_SFX, 1.0)
	AudioPool.set_bus_volume_linear(AudioPool.BUS_MUSIC, 1.0)
	var sfx_index: int = AudioServer.get_bus_index("SFX")
	var music_index: int = AudioServer.get_bus_index("Music")

	AudioPool.push_duck()
	await wait_seconds(AudioPool.DUCK_FADE_TIME + 0.05)

	assert_almost_eq(AudioServer.get_bus_volume_db(sfx_index),
		AudioPool.DUCK_AMOUNT_DB, 0.5)
	assert_almost_eq(AudioServer.get_bus_volume_db(music_index),
		AudioPool.DUCK_AMOUNT_DB, 0.5)


func test_pop_duck_restores_the_base_volume() -> void:
	AudioPool.set_bus_volume_linear(AudioPool.BUS_SFX, 1.0)
	var index: int = AudioServer.get_bus_index("SFX")

	AudioPool.push_duck()
	await wait_seconds(AudioPool.DUCK_FADE_TIME + 0.05)
	AudioPool.pop_duck()
	await wait_seconds(AudioPool.DUCK_FADE_TIME + 0.05)

	assert_almost_eq(AudioServer.get_bus_volume_db(index), 0.0, 0.5)


func test_overlapping_ducks_only_apply_once() -> void:
	AudioPool.set_bus_volume_linear(AudioPool.BUS_SFX, 1.0)
	var index: int = AudioServer.get_bus_index("SFX")

	AudioPool.push_duck()
	AudioPool.push_duck()
	await wait_seconds(AudioPool.DUCK_FADE_TIME + 0.05)
	var ducked_once: float = AudioServer.get_bus_volume_db(index)

	AudioPool.pop_duck()  # one of the two releases - still one reference held
	await wait_seconds(AudioPool.DUCK_FADE_TIME + 0.05)

	assert_almost_eq(AudioServer.get_bus_volume_db(index), ducked_once, 0.5,
		"a second overlapping duck release must not un-duck early")

	AudioPool.pop_duck()  # the last release
	await wait_seconds(AudioPool.DUCK_FADE_TIME + 0.05)
	assert_almost_eq(AudioServer.get_bus_volume_db(index), 0.0, 0.5)


func test_setting_bus_volume_while_ducked_does_not_undo_the_duck() -> void:
	AudioPool.set_bus_volume_linear(AudioPool.BUS_SFX, 1.0)
	AudioPool.push_duck()
	await wait_seconds(AudioPool.DUCK_FADE_TIME + 0.05)

	# The settings menu can change the user's SFX volume mid-line - the duck
	# has to still be in effect after that, not silently cancelled.
	AudioPool.set_bus_volume_linear(AudioPool.BUS_SFX, 0.5)
	var index: int = AudioServer.get_bus_index("SFX")
	assert_almost_eq(AudioServer.get_bus_volume_db(index),
		linear_to_db(0.5) + AudioPool.DUCK_AMOUNT_DB, 0.5)

	AudioPool.pop_duck()
