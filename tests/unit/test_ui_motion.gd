extends GutTest
## UiMotion: cada animacion termina en el estado de reposo, y ninguna deja al
## control en un lugar o un tamaño que no es el suyo.

const SettingsGuard = preload("res://tests/settings_guard.gd")

var _guard: SettingsGuard = SettingsGuard.new()
var _holder: Control
var _box: Control


func before_each() -> void:
	_guard.take()
	SettingsManager.set_value("accessibility/reduce_flashing", false)
	_holder = add_child_autofree(Control.new())
	_box = Control.new()
	_box.size = Vector2(120, 40)
	_box.position = Vector2(50, 60)
	_holder.add_child(_box)


func after_each() -> void:
	_guard.restore()


func test_a_punch_swells_and_settles_back() -> void:
	UiMotion.punch(_box, Tokens.REWARD)
	assert_gt(_box.scale.x, 1.0, "arranca hinchado")
	assert_ne(_box.modulate, Color.WHITE, "y teñido")
	await wait_seconds(maxf(Tokens.UI_PUNCH_TIME, Tokens.UI_FLASH_TIME) + 0.1)
	assert_almost_eq(_box.scale.x, 1.0, 0.001, "vuelve a su tamaño")
	assert_eq(_box.modulate, Color.WHITE, "y a su color")


func test_a_punch_does_not_tint_with_reduced_flashing() -> void:
	SettingsManager.set_value("accessibility/reduce_flashing", true)
	UiMotion.punch(_box, Tokens.ENEMY)
	assert_eq(_box.modulate, Color.WHITE, "se hincha igual, pero sin destello")


func test_an_entering_panel_lands_where_it_was() -> void:
	UiMotion.enter(_box)
	assert_ne(_box.position, Vector2(50, 60), "arranca corrido")
	await wait_seconds(Tokens.UI_ENTER_TIME + 0.1)
	assert_eq(_box.position, Vector2(50, 60), "y termina en su lugar")
	assert_almost_eq(_box.modulate.a, 1.0, 0.001)


func test_a_pop_in_stops_at_the_alpha_it_was_asked_for() -> void:
	UiMotion.pop_in(_box, 0.9, 0.0, Tokens.UI_ENTER_TIME, 0.45)
	await wait_seconds(Tokens.UI_ENTER_TIME + 0.1)
	assert_almost_eq(_box.modulate.a, 0.45, 0.001, "una carta que no se puede pagar llega apagada")
	assert_almost_eq(_box.scale.x, 1.0, 0.001)


func test_a_shake_ends_where_it_started() -> void:
	UiMotion.shake(_box)
	await wait_seconds(Tokens.UI_SHAKE_TIME + 0.1)
	assert_eq(_box.position, Vector2(50, 60))


## Un cartel que vuelve a entrar mientras se iba no puede quedar oculto por el
## final de la salida vieja.
func test_coming_back_in_cancels_the_exit() -> void:
	var hidden: Array[bool] = []
	UiMotion.exit(_box, func() -> void: hidden.append(true))
	UiMotion.pop_in(_box, 1.2)
	await wait_seconds(Tokens.UI_ENTER_TIME + 0.1)
	assert_true(hidden.is_empty(), "el callback de la salida no corrio")
	assert_almost_eq(_box.modulate.a, 1.0, 0.001)


func test_every_one_shot_respects_the_settle_ceiling() -> void:
	for duration: float in [Tokens.UI_PUNCH_TIME, Tokens.UI_FLASH_TIME, Tokens.UI_ENTER_TIME,
			Tokens.UI_EXIT_TIME, Tokens.UI_SHAKE_TIME, Tokens.RARE_SHEEN_TIME]:
		assert_lte(duration, Tokens.STATE_SETTLE_MAX)
