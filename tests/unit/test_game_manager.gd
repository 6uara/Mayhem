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


# ------------------------------------------------- el cambio de escena

## change_scene_to_file() encola el reemplazo y lo aplica al final del frame, no
## en el momento. Fadear de vuelta antes de eso mostraba la escena vieja: al
## apretar Play se veia el menu abrirse de nuevo y recien despues la partida.
func test_the_swap_wait_returns_once_the_scene_is_another_one() -> void:
	# Corriendo tests no hay escena actual, asi que se pone una: la espera mira
	# justamente eso, y con null tiene que seguir esperando (es el hueco entre
	# que se descarta la vieja y aparece la nueva).
	var previous := Node.new()
	add_child_autofree(previous)
	# Colgado de la raiz y no del test: current_scene solo acepta un nodo cuyo
	# padre sea la raiz del arbol, y asignarle cualquier otro no hace nada.
	var arrived := Node.new()
	get_tree().root.add_child(arrived)
	var original: Node = get_tree().current_scene
	get_tree().current_scene = arrived

	var started: int = Time.get_ticks_msec()
	await GameManager._await_scene_swap(previous, 2.0)
	var elapsed: int = Time.get_ticks_msec() - started

	get_tree().current_scene = original
	arrived.queue_free()
	assert_lt(elapsed, 500, "con la escena nueva ya puesta, no espera nada")


## Y si la escena nueva nunca llega, se rinde: mejor mostrar lo que haya que
## dejar al jugador mirando una pantalla negra para siempre.
func test_the_swap_wait_gives_up_instead_of_hanging() -> void:
	# Sin escena puesta la espera nunca se satisface, que es justo el caso que
	# el tope tiene que cortar.
	var started: int = Time.get_ticks_msec()
	await GameManager._await_scene_swap(get_tree().current_scene, 0.2)
	var elapsed: int = Time.get_ticks_msec() - started
	assert_gt(elapsed, 100, "espero de verdad")
	assert_lt(elapsed, 2000, "pero no para siempre")
