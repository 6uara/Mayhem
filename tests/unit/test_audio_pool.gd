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
	_fill_3d_with(AudioPool.BUS_SFX)
	assert_null(AudioPool.play_3d(_stream, Vector3.ZERO),
		"every 3D voice is busy and none is worth less - dropped, not crash")
	assert_push_warning("3D pool exhausted")


# ------------------------------------------------------------ prioridad de voces
#
# El pool se satura de verdad: una ola elite son 27 enemigos, mas una SMG a 15
# balas por segundo, mas un impacto por bala. Sin prioridad la unica regla era el
# orden de llegada, y lo que se caia podia ser el disparo del jugador - el pilar 1
# perdiendo contra el paso de un bicho. Con tres facciones va a ser peor.

func test_the_bus_decides_the_priority_so_no_call_site_has_to() -> void:
	assert_eq(AudioPool._resolve_priority(AudioPool.BUS_WEAPONS, -1),
		AudioPool.Priority.CRITICAL as int, "el arma del jugador nunca se cae")
	assert_eq(AudioPool._resolve_priority(AudioPool.BUS_VO, -1),
		AudioPool.Priority.CRITICAL as int, "la voz del Host tampoco")
	assert_eq(AudioPool._resolve_priority(AudioPool.BUS_IMPACTS, -1),
		AudioPool.Priority.AMBIENT as int, "los impactos son el sacrificio barato")
	assert_eq(AudioPool._resolve_priority(AudioPool.BUS_ENEMIES, -1),
		AudioPool.Priority.NORMAL as int, "el resto es normal")


func test_an_explicit_priority_beats_the_bus() -> void:
	assert_eq(AudioPool._resolve_priority(AudioPool.BUS_WORLD, AudioPool.Priority.TELEGRAPH),
		AudioPool.Priority.TELEGRAPH as int,
		"los avisos viven repartidos entre buses y por eso se piden a mano")


## El caso que motiva todo esto: el pool lleno de impactos y el jugador dispara.
func test_the_players_gunshot_steals_a_voice_instead_of_being_dropped() -> void:
	_fill_3d_with(AudioPool.BUS_IMPACTS)
	var shot: AudioStreamPlayer3D = AudioPool.play_3d(_stream, Vector3.ZERO,
		AudioPool.BUS_WEAPONS)
	assert_not_null(shot, "el disparo del jugador nunca se cae")
	assert_true(shot.playing, "y suena")


func test_a_telegraph_steals_a_voice_too() -> void:
	_fill_3d_with(AudioPool.BUS_IMPACTS)
	var warning: AudioStreamPlayer3D = AudioPool.play_3d(_stream, Vector3.ZERO,
		AudioPool.BUS_WORLD, 0.0, 1.0, AudioPool.Priority.TELEGRAPH)
	assert_not_null(warning, "un aviso que no suena es dano sin telegrafia")


## Al reves: lo barato no le saca la voz a lo caro. Sin esta mitad, la prioridad
## no ordena nada - solo cambia quien pisa a quien.
func test_an_impact_does_not_steal_from_the_gun() -> void:
	_fill_3d_with(AudioPool.BUS_WEAPONS)
	assert_null(AudioPool.play_3d(_stream, Vector3.ZERO, AudioPool.BUS_IMPACTS),
		"un impacto no calla un disparo")
	assert_push_warning("3D pool exhausted")


## Igual prioridad no roba, y esto importa mas de lo que parece: con "menor o
## igual" una rafaga se cortaria a si misma en el segundo tiro.
func test_a_sound_never_steals_from_its_own_kind() -> void:
	_fill_3d_with(AudioPool.BUS_WEAPONS)
	assert_null(AudioPool.play_3d(_stream, Vector3.ZERO, AudioPool.BUS_WEAPONS),
		"el segundo disparo no corta al primero")
	assert_push_warning("3D pool exhausted")


## La voz robada es la que menos se extrana: a igual prioridad, la mas lejana.
func test_the_stolen_voice_is_the_farthest_one() -> void:
	var far: AudioStreamPlayer3D = AudioPool.play_3d(_stream, Vector3(500, 0, 0),
		AudioPool.BUS_IMPACTS)
	var near: AudioStreamPlayer3D = AudioPool.play_3d(_stream, Vector3(1, 0, 0),
		AudioPool.BUS_IMPACTS)
	for i: int in AudioPool.POOL_SIZE_3D - 2:
		AudioPool.play_3d(_stream, Vector3(5, 0, 0), AudioPool.BUS_WEAPONS)

	var stolen: AudioStreamPlayer3D = AudioPool.play_3d(_stream, Vector3.ZERO,
		AudioPool.BUS_WEAPONS)
	assert_eq(stolen, far, "se calla el impacto lejano, no el de al lado")
	assert_true(near.playing, "el cercano sigue sonando")


func test_the_2d_pool_steals_by_priority_as_well() -> void:
	for i: int in AudioPool.POOL_SIZE_2D:
		AudioPool.play_2d(_stream, AudioPool.BUS_UI)
	assert_not_null(AudioPool.play_2d(_stream, AudioPool.BUS_VO),
		"la voz del Host se queda con una voz del pool 2D")


func _fill_3d_with(bus: StringName) -> void:
	for i: int in AudioPool.POOL_SIZE_3D:
		AudioPool.play_3d(_stream, Vector3.ZERO, bus)


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


func test_enemies_are_not_the_loudest_thing_in_the_mix() -> void:
	# The enemy SFX are mastered hotter than the weapons (-18.6 dBFS RMS against
	# -24.1), so at equal bus gain a rusher swinging drowns out the gun you are
	# holding. The layout compensates; this pins that it stays compensated.
	var enemies: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Enemies"))
	var weapons: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Weapons"))
	assert_lt(enemies, weapons, "the horde sits under the player's own gun")
	assert_lt(enemies, 0.0, "and under the SFX bus it feeds")


func test_music_sits_under_the_sound_effects() -> void:
	var music: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	var sfx: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))
	assert_lt(music, sfx, "the bed never competes with what the player has to hear")
