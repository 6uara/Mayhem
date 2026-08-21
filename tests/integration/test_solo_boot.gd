extends GutTest
## Arranca la escena de juego real en una sesion solo y verifica que todo quede
## acoplado.
##
## Existe porque `game.tscn` no lleva un nodo `Player` puesto a mano: lo
## instancia PlayerSpawnController en runtime. Todo lo
## que antes podia dar por sentado que el jugador ya existia al cargar la escena
## -el HUD, la camara, el grupo local_player- pasa a depender de un orden de
## inicializacion, y eso no falla en un test unitario: falla al abrir el juego,
## con una pantalla negra o un HUD en cero.
##
## El resto de la suite stubea al jugador o instancia player.tscn suelto, asi
## que ninguno de esos caminos toca este. Aca se carga la escena entera, sin
## reemplazar nada.

const GAME_SCENE: String = "res://scenes/main/game.tscn"

var _game: Node


func before_each() -> void:
	WaveManager.reset()
	EconomyManager.reset()
	UpgradeManager.reset()
	_game = add_child_autofree(load(GAME_SCENE).instantiate())
	# El spawn es un add_child diferido dentro del _ready del controller, y el
	# HUD se engancha con call_deferred despues de eso.
	await wait_physics_frames(10)


func after_each() -> void:
	WaveManager.reset()
	WaveManager.spawner = null
	WaveManager.setup([])
	EconomyManager.reset()
	UpgradeManager.reset()


func test_a_solo_run_puts_exactly_one_player_in_the_arena() -> void:
	assert_eq(Players.all().size(), 1, "una sesion sin peers es una sesion de uno")


func test_the_spawned_body_is_the_local_player() -> void:
	var local: Node3D = Players.local()
	assert_not_null(local, "sin local_player el HUD no tiene a que engancharse")
	assert_eq(local, Players.all()[0], "el unico jugador tiene que ser el local")


func test_the_local_player_is_alive() -> void:
	var local := Players.local() as Player
	assert_not_null(local)
	assert_true(Players.is_alive(local), "arranca vivo")


## El sintoma de que esto falle es una pantalla negra: la escena carga, no hay
## camara activa, y no hay ningun error que lo diga.
func test_the_local_player_owns_the_view() -> void:
	var local := Players.local() as Player
	assert_not_null(local)
	assert_not_null(local.camera, "camera")
	assert_true(local.camera.current, "la camara del jugador local tiene que estar activa")


func test_the_hud_bound_to_the_spawned_player() -> void:
	var hud: Node = _game.get_node_or_null("HUD")
	assert_not_null(hud, "HUD")
	# El HUD guarda el jugador en _player al enlazarse; si quedo null es que el
	# spawn le llego tarde y la señal local_player_spawned no lo desperto.
	assert_eq(hud.get("_player"), Players.local(),
		"el HUD tiene que quedar enganchado al jugador que spawneo")


func test_the_enemies_can_find_a_target() -> void:
	var local: Node3D = Players.local()
	assert_not_null(local)
	assert_eq(Players.nearest(local.global_position), local,
		"la IA busca objetivo por Players.nearest, no por el grupo player")


func test_the_match_is_running_after_boot() -> void:
	var director: MatchDirector = _game.get_node_or_null("MatchDirector")
	assert_not_null(director, "MatchDirector")
	assert_true(director.is_running, "el run solo tiene que arrancar sin esperar peers")


## La plata dejo de pagarse por enemy_killed y pasa por kill_credited. En solo
## el resultado tiene que ser identico al de antes del merge.
func test_a_kill_still_pays_the_wallet_in_solo() -> void:
	var before: int = EconomyManager.currency
	EventBus.kill_credited.emit(10)
	await wait_physics_frames(2)
	assert_gt(EconomyManager.currency, before, "una kill en solo tiene que pagar")


