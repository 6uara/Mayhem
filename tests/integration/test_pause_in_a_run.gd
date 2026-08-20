extends GutTest
## "Jugando singleplayer poner pausa debe pausar el juego" - el reporte del
## playtest, y las dos cosas que estaban atras.
##
## La primera: la tecla solo se escuchaba en State.PLAYING, y una run pasa la
## mitad del tiempo en SHOPPING. Entre oleada y oleada no hacia nada.
##
## La segunda: el arbol tenia dos dueños. El menu de pausa y la tienda escribian
## `get_tree().paused` sin saber uno del otro, asi que el ultimo en cerrar
## descongelaba el juego abajo del que seguia abierto.

const GAME_SCENE: String = "res://scenes/main/game.tscn"

var _game: Node


func before_each() -> void:
	WaveManager.reset()
	EconomyManager.reset()
	GameManager.clear_freezes()
	GameManager.is_paused = false
	GameManager.state = GameManager.State.PLAYING
	_game = add_child_autofree(load(GAME_SCENE).instantiate())
	await wait_physics_frames(10)


func after_each() -> void:
	GameManager.set_paused(false)
	GameManager.clear_freezes()
	GameManager.state = GameManager.State.MENU
	WaveManager.reset()
	WaveManager.spawner = null
	WaveManager.setup([])
	EconomyManager.reset()


func _press_pause() -> void:
	var event := InputEventAction.new()
	event.action = &"pause"
	event.pressed = true
	Input.parse_input_event(event)
	await wait_physics_frames(4)


func test_pressing_pause_during_a_solo_run_freezes_the_game() -> void:
	await _press_pause()
	assert_true(GameManager.is_paused, "GameManager se da por pausado")
	assert_true(get_tree().paused, "y el arbol esta efectivamente congelado")


func test_the_pause_panel_is_up_while_paused() -> void:
	await _press_pause()
	var menu: Node = _game.get_node_or_null("PauseMenu")
	assert_not_null(menu, "PauseMenu")
	assert_true(menu.get_node("Root").visible, "el panel se ve")


func test_pausing_again_resumes() -> void:
	await _press_pause()
	await _press_pause()
	assert_false(GameManager.is_paused, "la segunda vez despausa")
	assert_false(get_tree().paused, "y el arbol vuelve a correr")


## Lo que no andaba: entre oleadas la tecla era letra muerta.
func test_pause_works_during_the_shop_break_too() -> void:
	GameManager.state = GameManager.State.SHOPPING
	await _press_pause()
	assert_true(GameManager.is_paused, "la pausa vale en toda la run, no solo disparando")


# ------------------------------------------------- un solo dueño del arbol

func test_the_shop_freezes_the_tree_on_its_own_account() -> void:
	GameManager.set_freeze(GameManager.FREEZE_SHOP, true)
	assert_true(get_tree().paused, "la tienda congela")
	assert_false(GameManager.is_paused, "pero eso no es el menu de pausa")


## El bug concreto: pausa encima de la tienda, cerrar la pausa, y el juego
## corriendo abajo de una tienda todavia abierta.
func test_closing_the_pause_menu_leaves_the_shops_freeze_standing() -> void:
	GameManager.set_freeze(GameManager.FREEZE_SHOP, true)
	GameManager.set_paused(true)
	GameManager.set_paused(false)

	assert_false(GameManager.is_paused, "el menu de pausa se fue")
	assert_true(get_tree().paused, "la tienda sigue congelando lo suyo")


func test_the_tree_runs_again_once_the_last_reason_lets_go() -> void:
	GameManager.set_freeze(GameManager.FREEZE_SHOP, true)
	GameManager.set_paused(true)
	GameManager.set_paused(false)
	GameManager.set_freeze(GameManager.FREEZE_SHOP, false)

	assert_false(get_tree().paused, "sin motivos, el juego corre")
