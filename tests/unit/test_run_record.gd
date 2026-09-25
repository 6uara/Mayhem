extends GutTest
## Los trofeos de una run y como quedan guardados con ella.
##
## `evaluate()` es publico y sin estado justamente para esto: se le ponen los
## numeros a mano y se pregunta que trofeos dan, sin jugar diez oleadas.


func before_each() -> void:
	RunRecord.reset()


func after_each() -> void:
	RunRecord.reset()


# --------------------------------------------------------------- el catalogo

func test_every_trophy_says_what_it_is_and_how_to_get_it() -> void:
	for id: StringName in RunRecord.TROPHY_INFO.keys():
		assert_ne(RunRecord.get_label(id), "", "%s no tiene nombre" % id)
		assert_ne(RunRecord.get_description(id), "", "%s no dice como se gana" % id)


## Una run guardada por una version futura no puede romper la tabla de esta.
func test_an_unknown_trophy_still_prints_something() -> void:
	assert_eq(RunRecord.get_label(&"no_existe"), "NO_EXISTE")
	assert_eq(RunRecord.get_description(&"no_existe"), "")


# --------------------------------------------------------------- la evaluacion

func test_a_run_that_did_nothing_wins_nothing() -> void:
	assert_eq(RunRecord.evaluate(600.0, false), [] as Array[StringName])


func test_winning_the_ten_waves_is_a_trophy() -> void:
	RunRecord.kills = 50
	RunRecord.hits_taken = 5
	assert_true(RunRecord.evaluate(900.0, true).has(RunRecord.CHAMPION))


func test_losing_is_never_a_champion() -> void:
	RunRecord.kills = 50
	assert_false(RunRecord.evaluate(100.0, false).has(RunRecord.CHAMPION))


## Terminar sin un rasguño y limpiar varias oleadas son dos cosas distintas, y
## la primera no puede anular a la segunda.
func test_an_untouched_run_wins_both_cleanliness_trophies() -> void:
	RunRecord.kills = 40
	RunRecord.hits_taken = 0
	RunRecord.flawless_waves = RunRecord.UNTOUCHABLE_WAVES
	var won: Array[StringName] = RunRecord.evaluate(600.0, false)
	assert_true(won.has(RunRecord.FLAWLESS))
	assert_true(won.has(RunRecord.UNTOUCHABLE))


## Sin kills no hubo run, y una pantalla de inicio abandonada no es una partida
## impecable.
func test_a_run_with_no_kills_is_not_flawless() -> void:
	RunRecord.hits_taken = 0
	assert_false(RunRecord.evaluate(10.0, false).has(RunRecord.FLAWLESS))


func test_one_hit_costs_the_flawless() -> void:
	RunRecord.kills = 40
	RunRecord.hits_taken = 1
	assert_false(RunRecord.evaluate(600.0, false).has(RunRecord.FLAWLESS))


## Tres de cinco a la cabeza no es puntería de nadie: la proporcion sola, sin un
## minimo de kills, regalaria el trofeo en la primera oleada.
func test_a_high_ratio_on_few_kills_is_not_marksmanship() -> void:
	RunRecord.kills = 5
	RunRecord.headshots = 5
	assert_false(RunRecord.evaluate(600.0, false).has(RunRecord.MARKSMAN))


func test_marksmanship_over_the_minimum() -> void:
	RunRecord.kills = RunRecord.MARKSMAN_MIN_KILLS
	RunRecord.headshots = int(ceil(RunRecord.MARKSMAN_MIN_KILLS * RunRecord.MARKSMAN_RATIO))
	assert_true(RunRecord.evaluate(600.0, false).has(RunRecord.MARKSMAN))


func test_the_bonus_trophies_read_the_bonus_counters() -> void:
	RunRecord.bonus_counts = {
		KillBonusTracker.BONUS_AIRBORNE: RunRecord.ACROBAT_KILLS,
		KillBonusTracker.BONUS_SPIN: RunRecord.SPINNER_KILLS,
		KillBonusTracker.BONUS_MAYHEM: 1,
		KillBonusTracker.BONUS_PRIORITY: RunRecord.SURGEON_KILLS,
		KillBonusTracker.BONUS_LONG_SHOT: RunRecord.SNIPER_KILLS,
	}
	var won: Array[StringName] = RunRecord.evaluate(600.0, false)
	for id: StringName in [RunRecord.ACROBAT, RunRecord.SPINNER, RunRecord.EXECUTIONER,
			RunRecord.SURGEON, RunRecord.SNIPER]:
		assert_true(won.has(id), "falta %s" % id)


func test_buying_nothing_only_counts_when_you_win() -> void:
	RunRecord.kills = 50
	assert_true(RunRecord.evaluate(900.0, true).has(RunRecord.ASCETIC))
	assert_false(RunRecord.evaluate(900.0, false).has(RunRecord.ASCETIC),
		"perder sin comprar nada no es ascetismo, es haber muerto temprano")


func test_one_purchase_costs_the_ascetic() -> void:
	RunRecord.kills = 50
	RunRecord.purchases = 1
	assert_false(RunRecord.evaluate(900.0, true).has(RunRecord.ASCETIC))


func test_a_fast_victory_is_a_blitz() -> void:
	assert_true(RunRecord.evaluate(RunRecord.BLITZ_SECONDS - 1.0, true).has(RunRecord.BLITZ))
	assert_false(RunRecord.evaluate(RunRecord.BLITZ_SECONDS + 1.0, true).has(RunRecord.BLITZ))


# --------------------------------------------------------------- lo que cuenta

func test_kills_and_headshots_come_off_the_signal() -> void:
	EventBus.kill_scored.emit(&"rusher", Vector3.ZERO, true, 10)
	EventBus.kill_scored.emit(&"rusher", Vector3.ZERO, false, 10)
	assert_eq(RunRecord.kills, 2)
	assert_eq(RunRecord.headshots, 1)


## Cuantas veces te tocaron y cuanto dolio son dos preguntas: INTOCABLE necesita
## la primera, y un solo golpe de 1 de daño tiene que costarlo igual.
func test_hits_are_counted_apart_from_damage() -> void:
	EventBus.player_damaged.emit(1.0, 99.0)
	EventBus.player_damaged.emit(40.0, 59.0)
	assert_eq(RunRecord.hits_taken, 2)
	assert_eq(RunRecord.damage_taken, 41.0)


func test_a_clean_wave_is_counted_and_a_dirty_one_is_not() -> void:
	EventBus.wave_completed.emit(0, 30.0, 0.0)
	EventBus.wave_completed.emit(1, 30.0, 12.0)
	assert_eq(RunRecord.flawless_waves, 1)


func test_bonuses_are_tallied_by_id() -> void:
	EventBus.kill_payout.emit(10, [KillBonusTracker.BONUS_SPIN], 40, Vector3.ZERO)
	EventBus.kill_payout.emit(10, [KillBonusTracker.BONUS_SPIN,
		KillBonusTracker.BONUS_AIRBORNE], 55, Vector3.ZERO)
	assert_eq(RunRecord.get_bonus_count(KillBonusTracker.BONUS_SPIN), 2)
	assert_eq(RunRecord.get_bonus_count(KillBonusTracker.BONUS_AIRBORNE), 1)


func test_a_finished_run_leaves_its_trophies_ready_to_save() -> void:
	RunRecord.kills = 50
	EventBus.run_finished.emit(4000, 300.0, 10, true)
	assert_true(RunRecord.get_trophies().has(RunRecord.CHAMPION))


func test_a_new_run_starts_with_nothing() -> void:
	RunRecord.kills = 50
	EventBus.run_finished.emit(4000, 300.0, 10, true)
	RunRecord.reset()
	assert_eq(RunRecord.kills, 0)
	assert_eq(RunRecord.get_trophies(), [] as Array[StringName],
		"los trofeos de la run anterior no pueden anotarse en la siguiente")
