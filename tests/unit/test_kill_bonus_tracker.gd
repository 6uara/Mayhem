extends GutTest
## Los recargos por kill y lo que cuesta recibir un golpe.
##
## Todo lo que se prueba aca sale por señal, sin jugador y sin arena: el tracker
## que **juzga** la kill necesita un Player vivo para saber si estabas en el
## aire, pero la cuenta - que bonos existen, cuanto pagan, que se acredita - es
## del EconomyConfig y del EconomyManager, y esos se pueden interrogar solos.


func before_each() -> void:
	EconomyManager.reset()
	EconomyManager.begin_wave()
	KillBonusTracker.reset()


func after_each() -> void:
	EconomyManager.reset()
	KillBonusTracker.reset()


# Tabla de pagos

func test_every_bonus_id_has_a_price() -> void:
	var config := EconomyConfig.new()
	for id: StringName in [
			KillBonusTracker.BONUS_HEADSHOT, KillBonusTracker.BONUS_AIRBORNE,
			KillBonusTracker.BONUS_SPIN, KillBonusTracker.BONUS_GRAPPLE,
			KillBonusTracker.BONUS_DASH, KillBonusTracker.BONUS_LONG_SHOT,
			KillBonusTracker.BONUS_POINT_BLANK, KillBonusTracker.BONUS_LAST_ROUND,
			KillBonusTracker.BONUS_DOUBLE, KillBonusTracker.BONUS_TRIPLE,
			KillBonusTracker.BONUS_MAYHEM]:
		assert_gt(config.get_kill_bonus(id), 0,
			"%s no paga nada, asi que no es un bono" % id)


func test_every_bonus_id_has_a_name_on_screen() -> void:
	for id: StringName in KillBonusTracker.BONUS_LABEL.keys():
		assert_ne(KillBonusTracker.get_label(id), "",
			"%s no tiene como anunciarse" % id)


## Un id que la tabla no conoce no puede devolver vacio: la HUD lo escribe tal
## cual sin preguntar.
func test_an_unknown_bonus_still_has_something_to_print() -> void:
	assert_eq(KillBonusTracker.get_label(&"no_existe"), "NO_EXISTE")


func test_an_unknown_bonus_pays_nothing() -> void:
	assert_eq(EconomyConfig.new().get_kill_bonus(&"no_existe"), 0)


# Acreditacion

func test_a_bonus_pays_into_the_wave_total_like_a_kill_does() -> void:
	EventBus.kill_payout.emit(10, [KillBonusTracker.BONUS_SPIN], 40, Vector3.ZERO)
	assert_eq(EconomyManager.currency, 40,
		"el bono entra solo: la recompensa base la cobra kill_credited")
	assert_eq(EconomyManager.get_wave_kill_income(), 40)


## La kill sin recargo tambien emite kill_payout - es el unico evento que cierra
## la cuenta - y no puede acreditar nada de mas por eso.
func test_a_kill_with_no_bonus_credits_nothing_extra() -> void:
	EventBus.kill_payout.emit(10, [], 0, Vector3.ZERO)
	assert_eq(EconomyManager.currency, 0)


# Penalidad por daño

func test_taking_damage_costs_money() -> void:
	EconomyManager.currency = 500
	EventBus.player_damaged.emit(20.0, 80.0)
	assert_eq(EconomyManager.currency, 480)
	assert_eq(EconomyManager.get_wave_damage_loss(), 20)


## Un golpe enorme no puede vaciar la billetera entera: la tienda de la proxima
## oleada tiene que seguir existiendo.
func test_the_loss_is_capped_per_hit() -> void:
	EconomyManager.currency = 1000
	EventBus.player_damaged.emit(500.0, 1.0)
	assert_eq(EconomyManager.currency,
		1000 - EconomyManager.config.currency_loss_max_per_hit)


## Cero no es deuda. Un jugador sin plata recibiendo golpes no puede quedar
## debiendo ni anunciar perdidas que no ocurrieron.
func test_a_broke_player_loses_nothing_and_announces_nothing() -> void:
	EconomyManager.currency = 0
	watch_signals(EventBus)
	EventBus.player_damaged.emit(30.0, 70.0)
	assert_eq(EconomyManager.currency, 0)
	assert_signal_emit_count(EventBus, "currency_lost", 0)


func test_the_loss_never_exceeds_what_there_was() -> void:
	EconomyManager.currency = 5
	EventBus.player_damaged.emit(30.0, 70.0)
	assert_eq(EconomyManager.currency, 0)
	assert_eq(EconomyManager.get_wave_damage_loss(), 5,
		"se perdieron 5, no los 30 que valia el golpe")


func test_what_was_lost_is_announced() -> void:
	EconomyManager.currency = 100
	watch_signals(EventBus)
	EventBus.player_damaged.emit(10.0, 90.0)
	assert_signal_emitted_with_parameters(EventBus, "currency_lost", [10, &"damage"])


## Apagar la penalidad tiene que apagarla entera, no dejarla en un peso.
func test_a_zero_rate_turns_the_penalty_off() -> void:
	var config := EconomyConfig.new()
	config.currency_loss_per_damage = 0.0
	assert_eq(config.get_damage_penalty(100.0), 0)


func test_the_wave_breakdown_reports_what_damage_cost() -> void:
	var wave := WaveData.new()
	wave.par_time = 60.0
	EconomyManager.currency = 300
	EventBus.player_damaged.emit(15.0, 85.0)
	var breakdown: Dictionary = EconomyManager.award_wave_bonuses(wave, 20.0, true)
	assert_eq(int(breakdown["damage_loss"]), 15)


# Racha

## Paga por escalon y no acumulado: cuatro kills seguidas son DOBLE, TRIPLE y
## MAYHEM, no las tres sumadas cada vez.
func test_a_streak_pays_one_step_at_a_time() -> void:
	var seen: Array = []
	var handler := func(_reward: int, ids: Array, _total: int, _at: Vector3) -> void:
		seen.append(ids.duplicate())
	EventBus.kill_payout.connect(handler)
	for i: int in 4:
		EventBus.kill_scored.emit(&"rusher", Vector3.ZERO, false, 10)
	EventBus.kill_payout.disconnect(handler)

	assert_eq(seen.size(), 4, "cada kill cierra su cuenta")
	assert_false(seen[0].has(KillBonusTracker.BONUS_DOUBLE), "la primera no es racha")
	assert_true(seen[1].has(KillBonusTracker.BONUS_DOUBLE))
	assert_true(seen[2].has(KillBonusTracker.BONUS_TRIPLE))
	assert_true(seen[3].has(KillBonusTracker.BONUS_MAYHEM))


## Una oleada nueva empieza sin racha: la ultima kill de la anterior y la
## primera de esta no son un doble aunque el reloj diga que pasaron milisegundos.
func test_a_new_wave_breaks_the_streak() -> void:
	EventBus.kill_scored.emit(&"rusher", Vector3.ZERO, false, 10)
	EventBus.wave_started.emit(1, null)
	var seen: Array = []
	var handler := func(_reward: int, ids: Array, _total: int, _at: Vector3) -> void:
		seen.append(ids.duplicate())
	EventBus.kill_payout.connect(handler)
	EventBus.kill_scored.emit(&"rusher", Vector3.ZERO, false, 10)
	EventBus.kill_payout.disconnect(handler)
	assert_false(seen[0].has(KillBonusTracker.BONUS_DOUBLE))


func test_a_headshot_kill_is_paid_as_one() -> void:
	# Se llena con append y no con una asignacion: una lambda de GDScript captura
	# la variable por valor, asi que reasignarla adentro no se ve desde afuera.
	var seen: Array = []
	var handler := func(_reward: int, ids: Array, total: int, _at: Vector3) -> void:
		seen.append({"ids": ids, "total": total})
	EventBus.kill_payout.connect(handler)
	EventBus.kill_scored.emit(&"rusher", Vector3.ZERO, true, 10)
	EventBus.kill_payout.disconnect(handler)
	assert_eq(seen.size(), 1)
	assert_true((seen[0]["ids"] as Array).has(KillBonusTracker.BONUS_HEADSHOT))
	assert_gt(int(seen[0]["total"]), 0, "y paga")
