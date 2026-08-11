extends GutTest
## MusicManager: follows GameManager's state machine, and ducks alongside SFX
## under Host VO via the same AudioPool mechanism (not a second one).


func before_each() -> void:
	GameManager.state = GameManager.State.MENU
	AudioPool.set_bus_volume_linear(AudioPool.BUS_MUSIC, 1.0)


func after_each() -> void:
	GameManager.state = GameManager.State.MENU
	while AudioPool._duck_refs > 0:
		AudioPool.pop_duck()
	AudioPool.set_bus_volume_linear(AudioPool.BUS_MUSIC, 1.0)


func test_music_follows_the_match_state() -> void:
	GameManager.state = GameManager.State.PLAYING
	assert_true(MusicManager._current_path.contains("combat.wav"))
	assert_not_null(MusicManager._active)
	assert_true(MusicManager._active.playing)

	GameManager.state = GameManager.State.SHOPPING
	assert_true(MusicManager._current_path.contains("shop.wav"))


func test_the_same_state_does_not_restart_the_crossfade() -> void:
	GameManager.state = GameManager.State.PLAYING
	var active_before: AudioStreamPlayer = MusicManager._active
	# Setting the identical value is a no-op on GameManager.state's own setter,
	# so this call never reaches _on_game_state_changed - drive it directly to
	# prove MusicManager's own guard holds even if something ever did re-emit.
	MusicManager._on_game_state_changed(int(GameManager.State.PLAYING))
	assert_eq(MusicManager._active, active_before,
		"the same state must not tear down and restart the current track")


func test_music_ducks_under_the_host() -> void:
	var index: int = AudioServer.get_bus_index("Music")
	var before_db: float = AudioServer.get_bus_volume_db(index)

	AudioPool.push_duck()
	await wait_seconds(AudioPool.DUCK_FADE_TIME + 0.05)
	assert_almost_eq(AudioServer.get_bus_volume_db(index),
		before_db + AudioPool.DUCK_AMOUNT_DB, 0.5,
		"Music must duck by the same amount SFX does")

	AudioPool.pop_duck()
	await wait_seconds(AudioPool.DUCK_FADE_TIME + 0.05)
	assert_almost_eq(AudioServer.get_bus_volume_db(index), before_db, 0.5,
		"releasing the duck must restore Music's volume")
