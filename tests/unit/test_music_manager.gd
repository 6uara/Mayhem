extends GutTest
## MusicManager: follows GameManager's state machine, keeps playing across the
## shop door, and ducks alongside SFX under Host VO via the same AudioPool
## mechanism (not a second one).


func before_each() -> void:
	GameManager.state = GameManager.State.MENU
	AudioPool.set_bus_volume_linear(AudioPool.BUS_MUSIC, 1.0)


func after_each() -> void:
	GameManager.state = GameManager.State.MENU
	while AudioPool._duck_refs > 0:
		AudioPool.pop_duck()
	AudioPool.set_bus_volume_linear(AudioPool.BUS_MUSIC, 1.0)


func test_the_playlist_ships_with_tracks_for_every_phase() -> void:
	assert_not_null(MusicManager.playlist, "the manager loads a playlist")
	assert_false(MusicManager.playlist.is_empty())
	for phase: StringName in [&"menu", &"run", &"game_over"]:
		assert_gt(MusicManager.playlist.tracks_for_phase(phase).size(), 0,
			"%s has something to play" % phase)


func test_music_follows_the_match_state() -> void:
	GameManager.state = GameManager.State.PLAYING
	assert_eq(MusicManager.get_phase(), &"run")
	assert_true(MusicManager.is_playing())


func test_the_shop_keeps_the_track_the_wave_was_playing() -> void:
	GameManager.state = GameManager.State.PLAYING
	var track: AudioStream = MusicManager._current_stream
	var player: AudioStreamPlayer = MusicManager._active

	GameManager.state = GameManager.State.SHOPPING
	assert_eq(MusicManager._current_stream, track,
		"walking into the armoury is not a change of mood")
	assert_eq(MusicManager._active, player, "and not a new player either")

	GameManager.state = GameManager.State.PLAYING
	assert_eq(MusicManager._current_stream, track, "nor is walking back out")


func test_leaving_the_menu_for_a_run_does_change_the_track() -> void:
	GameManager.state = GameManager.State.MENU
	assert_eq(MusicManager.get_phase(), &"menu")
	var menu_track: AudioStream = MusicManager._current_stream

	GameManager.state = GameManager.State.PLAYING
	assert_eq(MusicManager.get_phase(), &"run")
	assert_ne(MusicManager._current_stream, menu_track)


func test_the_same_state_does_not_restart_the_crossfade() -> void:
	GameManager.state = GameManager.State.PLAYING
	var active_before: AudioStreamPlayer = MusicManager._active
	# Setting the identical value is a no-op on GameManager.state's own setter,
	# so this call never reaches _on_game_state_changed - drive it directly to
	# prove MusicManager's own guard holds even if something ever did re-emit.
	MusicManager._on_game_state_changed(int(GameManager.State.PLAYING))
	assert_eq(MusicManager._active, active_before,
		"the same state must not tear down and restart the current track")


func test_a_finished_track_hands_over_to_the_next_one() -> void:
	GameManager.state = GameManager.State.PLAYING
	var first: AudioStream = MusicManager._current_stream
	MusicManager._on_track_finished(MusicManager._active)
	assert_eq(MusicManager.get_phase(), &"run", "still the same phase")
	assert_ne(MusicManager._current_stream, first,
		"a song ending mid-run moves to another one, it does not repeat itself")


func test_a_track_that_finished_fading_out_says_nothing() -> void:
	GameManager.state = GameManager.State.PLAYING
	var playing: AudioStream = MusicManager._current_stream
	var idle: AudioStreamPlayer = MusicManager._next_player()
	MusicManager._on_track_finished(idle)
	assert_eq(MusicManager._current_stream, playing,
		"the outgoing player finishes too, and it is not the bed any more")


func test_the_bed_is_well_under_the_rest_of_the_game() -> void:
	assert_lt(MusicManager.playlist.bed_volume_db, -6.0,
		"music is a floor, not a layer over the sounds that carry information")
	GameManager.state = GameManager.State.PLAYING
	await wait_seconds(MusicManager.playlist.crossfade_time + 0.2)
	assert_almost_eq(MusicManager._active.volume_db,
		MusicManager.playlist.bed_volume_db, 0.5,
		"and the fade lands on exactly that level")


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
