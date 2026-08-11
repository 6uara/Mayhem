extends GutTest
## GameManager: the match state machine and pause. Previously zero test files.
##
## Deliberately never calls restart_run() / return_to_menu() here - both call
## get_tree().change_scene_to_file(), which would swap out GUT's own test
## runner scene mid-suite. start_run() is safe (state/timer/mouse capture
## only, no scene change) and is exercised directly.


func before_each() -> void:
	GameManager.state = GameManager.State.MENU
	GameManager.is_paused = false
	get_tree().paused = false


func after_each() -> void:
	GameManager.state = GameManager.State.MENU
	GameManager.is_paused = false
	get_tree().paused = false


# state

func test_setting_the_same_state_twice_does_not_re_emit() -> void:
	GameManager.state = GameManager.State.PLAYING
	watch_signals(EventBus)
	GameManager.state = GameManager.State.PLAYING
	assert_signal_not_emitted(EventBus, "game_state_changed")


func test_changing_state_emits_game_state_changed_with_the_new_value() -> void:
	watch_signals(EventBus)
	GameManager.state = GameManager.State.PLAYING
	assert_signal_emitted_with_parameters(EventBus, "game_state_changed",
		[int(GameManager.State.PLAYING)])


func test_start_run_lands_in_the_playing_state() -> void:
	GameManager.start_run()
	assert_eq(GameManager.state, GameManager.State.PLAYING)
	assert_false(GameManager.is_paused, "a fresh run must not start paused")
	assert_false(get_tree().paused)


# pause

func test_set_paused_true_pauses_the_tree() -> void:
	GameManager.set_paused(true)
	assert_true(GameManager.is_paused)
	assert_true(get_tree().paused)


func test_set_paused_false_unpauses_the_tree() -> void:
	GameManager.set_paused(true)
	GameManager.set_paused(false)
	assert_false(GameManager.is_paused)
	assert_false(get_tree().paused)


func test_set_paused_to_its_current_value_is_a_no_op() -> void:
	watch_signals(EventBus)
	GameManager.set_paused(false)  # already false
	assert_signal_not_emitted(EventBus, "game_paused")


func test_set_paused_emits_game_paused_with_the_new_value() -> void:
	watch_signals(EventBus)
	GameManager.set_paused(true)
	assert_signal_emitted_with_parameters(EventBus, "game_paused", [true])


func test_toggle_pause_flips_is_paused() -> void:
	assert_false(GameManager.is_paused)
	GameManager.toggle_pause()
	assert_true(GameManager.is_paused)
	GameManager.toggle_pause()
	assert_false(GameManager.is_paused)


# run time

func test_run_time_is_zero_while_in_the_menu() -> void:
	assert_eq(GameManager.get_run_time(), 0.0)


func test_run_time_advances_once_a_run_has_started() -> void:
	# get_run_time() reads real OS wall-clock time (Time.get_ticks_msec()), not
	# simulated frame delta - give it a real gap to measure rather than a tight
	# one that a fast/decoupled headless frame loop could race past.
	GameManager.start_run()
	await wait_seconds(0.3)
	assert_gt(GameManager.get_run_time(), 0.0)


# player death

func test_player_dying_sets_game_over() -> void:
	GameManager.start_run()
	EventBus.player_died.emit()
	assert_eq(GameManager.state, GameManager.State.GAME_OVER)


func test_player_dying_twice_is_harmless() -> void:
	GameManager.start_run()
	EventBus.player_died.emit()
	watch_signals(EventBus)
	EventBus.player_died.emit()
	assert_signal_not_emitted(EventBus, "game_state_changed",
		"already in GAME_OVER - a second death must not re-fire the transition")
