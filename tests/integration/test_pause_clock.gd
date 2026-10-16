extends GutTest
## La pausa congela el juego, y tambien tiene que congelar sus relojes.
##
## Los relojes de la oleada, la partida y la run son de pared (Time.get_ticks_msec)
## y los timers de spawn se creaban con `process_always`. Con el menu de pausa
## abierto -o despues de un alt-tab, que pausa solo- el PAR de la oleada seguia
## corriendo, se perdia el bono de velocidad, el tiempo de la run podia costar el
## trofeo RELAMPAGO, y la oleada seguia largando enemigos detras del menu.


class FakeSpawner:
	extends Node
	var spawned: int = 0

	func spawn(_enemy_data: EnemyData, _door_ids: Array[StringName]) -> Node:
		spawned += 1
		return self


var _spawner: FakeSpawner
var _previous_state: GameManager.State


func before_each() -> void:
	_previous_state = GameManager.state
	_spawner = FakeSpawner.new()
	add_child_autofree(_spawner)
	WaveManager.reset()
	WaveManager.spawner = _spawner


func after_each() -> void:
	GameManager.set_paused(false)
	GameManager.clear_freezes()
	GameManager.state = _previous_state
	WaveManager.reset()
	WaveManager.spawner = null
	WaveManager.setup([])


func _wave(count: int, interval: float) -> WaveData:
	var enemy := EnemyData.new()
	enemy.id = &"test_enemy"
	var group := SpawnGroup.new()
	group.enemy_data = enemy
	group.count = count
	group.interval = interval
	group.spawn_door_ids = [&"door_01"] as Array[StringName]
	var wave := WaveData.new()
	wave.spawn_groups = [group]
	return wave


## Con el arbol en pausa `wait_seconds()` de GUT no avanza. Para los relojes de
## pared alcanza con dormir: `OS.delay_msec()` pasa tiempo real sin frames.
func _pause_for(msec: int) -> void:
	GameManager.set_paused(true)
	OS.delay_msec(msec)
	GameManager.set_paused(false)


func test_the_pause_clock_counts_the_pause_in_progress() -> void:
	var before: float = GameManager.get_paused_seconds()
	GameManager.set_paused(true)
	OS.delay_msec(300)
	assert_gt(GameManager.get_paused_seconds() - before, 0.25, "mientras dura")
	GameManager.set_paused(false)
	var after: float = GameManager.get_paused_seconds()
	OS.delay_msec(200)
	assert_eq(GameManager.get_paused_seconds(), after, "y deja de contar al despausar")


func test_the_shop_freeze_is_not_pause_time() -> void:
	var before: float = GameManager.get_paused_seconds()
	GameManager.set_freeze(GameManager.FREEZE_SHOP, true)
	OS.delay_msec(200)
	GameManager.set_freeze(GameManager.FREEZE_SHOP, false)
	assert_eq(GameManager.get_paused_seconds(), before,
		"comprar es parte de la run: solo el menu de pausa para el reloj")


func test_paused_time_does_not_count_toward_the_wave_clock() -> void:
	WaveManager.setup([_wave(2, 30.0)])
	WaveManager.start_next_wave()
	_pause_for(500)
	assert_lt(WaveManager.get_wave_duration(), 0.3,
		"medio segundo en pausa no puede comerse el PAR")


## Este si necesita frames: lo que se prueba es el timer de spawn. Los frames de
## fisica de GUT corren con el arbol en pausa (ver test_pause_in_a_run.gd).
func test_the_wave_does_not_keep_spawning_behind_the_pause_menu() -> void:
	WaveManager.setup([_wave(3, 0.2)])
	WaveManager.start_next_wave()
	assert_eq(_spawner.spawned, 1, "el primero sale enseguida")
	GameManager.set_paused(true)
	await wait_physics_frames(40)
	assert_eq(_spawner.spawned, 1, "con el juego en pausa no sale nadie mas")
	GameManager.set_paused(false)
	await wait_seconds(0.8)
	assert_eq(_spawner.spawned, 3, "y al volver sigue donde estaba")


func test_the_run_clock_skips_the_pause() -> void:
	GameManager.start_run()
	_pause_for(500)
	assert_lt(GameManager.get_run_time(), 0.3)


func test_starting_a_run_while_paused_closes_the_pause_clock() -> void:
	GameManager.set_paused(true)
	GameManager.start_run()
	var paused_at_start: float = GameManager.get_paused_seconds()
	OS.delay_msec(300)
	assert_eq(GameManager.get_paused_seconds(), paused_at_start,
		"start_run baja la pausa, y su reloj con ella")
	assert_gt(GameManager.get_run_time(), 0.25)


## Las ventanas cortas -la racha de kills, el ritmo del rating, el dash reciente-
## se miden con el reloj de juego. Con el de pared, un Esc en medio de una racha
## la cortaba: la kill siguiente caia afuera de la ventana.
func test_the_game_clock_stands_still_while_paused() -> void:
	GameManager.set_paused(true)
	var at_pause: float = GameManager.get_game_clock()
	OS.delay_msec(300)
	assert_almost_eq(GameManager.get_game_clock(), at_pause, 0.05)
	GameManager.set_paused(false)
	OS.delay_msec(200)
	assert_gt(GameManager.get_game_clock() - at_pause, 0.15, "y al volver sigue")


func test_a_pause_does_not_break_a_kill_streak() -> void:
	KillBonusTracker._streak = 0
	KillBonusTracker._last_kill_time = -1000.0
	assert_eq(KillBonusTracker._advance_streak(KillBonusTracker._now()), &"")
	_pause_for(int((KillBonusTracker.MULTI_WINDOW + 0.3) * 1000.0))
	assert_eq(KillBonusTracker._advance_streak(KillBonusTracker._now()),
		KillBonusTracker.BONUS_DOUBLE, "la segunda kill despues de la pausa sigue la racha")
	KillBonusTracker._streak = 0
	KillBonusTracker._last_kill_time = -999.0
