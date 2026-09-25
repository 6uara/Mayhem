extends GutTest
## Nothing on the HUD may sit on top of anything else.
##
## Overlap is not a cosmetic complaint: two readouts sharing pixels means one of them
## is unreadable exactly when the player needs it, and the handoff judges anything
## read mid-combat on legibility first.

## The design resolution, but the test runner's viewport is not it - clusters anchor
## to whatever they are actually given, so measurements come from the live viewport.
const DESIGN_SCREEN := Vector2(1920, 1080)

## The clusters that actually draw content, by the name the HUD scene gives them.
const CLUSTERS: Array[String] = [
	"WaveCluster", "TimerCluster", "CurrencyCluster",
	"VitalsCluster", "AbilityBar", "WeaponCluster",
	"SubtitleBox", "AnnounceLayer",
]

## El cartel de ayuda no esta arriba y no puede estarlo: comparte la banda con el
## aviso de oleada a proposito, y lo que lo hace legible no es donde esta sino
## que los dos nunca se dibujan juntos. Eso se prueba abajo, por comportamiento.
const HINT: String = "TutorialHintBox"

var _hud: CanvasLayer
var _player: Player


func before_each() -> void:
	_player = add_child_autofree(load("res://scenes/player/player.tscn").instantiate())
	_hud = add_child_autofree(load("res://scenes/ui/hud.tscn").instantiate())
	# Everything visible at once is the worst case, and the worst case is the one
	# that has to hold.
	_hud.get_node("Root/SubtitleBox").visible = true
	_hud.get_node("Root/AnnounceLayer").visible = true
	await wait_physics_frames(4)


func _rect(name: String) -> Rect2:
	var control: Control = _hud.get_node("Root/%s" % name)
	return Rect2(control.global_position, control.size)


func test_no_two_clusters_overlap() -> void:
	for i: int in CLUSTERS.size():
		for j: int in range(i + 1, CLUSTERS.size()):
			var a: Rect2 = _rect(CLUSTERS[i])
			var b: Rect2 = _rect(CLUSTERS[j])
			assert_false(a.intersects(b),
				"%s %s overlaps %s %s" % [CLUSTERS[i], a, CLUSTERS[j], b])


func _screen() -> Rect2:
	return get_tree().root.get_visible_rect()


func test_every_cluster_stays_on_screen() -> void:
	var screen: Rect2 = _screen()
	for name: String in CLUSTERS:
		var rect: Rect2 = _rect(name)
		assert_true(screen.encloses(rect), "%s %s runs off screen" % [name, rect])


## Rule 3 of the five: the centre belongs to the crosshair and the action.
func test_nothing_enters_the_no_ui_zone() -> void:
	var screen: Rect2 = _screen()
	var forbidden := Rect2(screen.position + (screen.size - Tokens.NO_UI_ZONE) * 0.5,
		Tokens.NO_UI_ZONE)
	for name: String in CLUSTERS:
		assert_false(_rect(name).intersects(forbidden),
			"%s enters the no-UI zone" % name)


func test_the_broadcast_bug_does_not_sit_on_the_wave_cluster() -> void:
	# The bug spans the full width by design; only its tag row draws content.
	var tag: Control = _hud.get_node("Root/BroadcastBug").get_child(0)
	var tag_rect := Rect2(tag.global_position, tag.size)
	for name: String in ["WaveCluster", "TimerCluster", "CurrencyCluster"]:
		assert_false(tag_rect.intersects(_rect(name)),
			"the LIVE tag overlaps %s" % name)


## El feed de recargos vive dentro del cluster de plata y crece hacia abajo, asi
## que su tope no es una decision estetica: lleno tiene que seguir sin tocar
## nada. Con el cluster de plata arriba a la derecha y el de arma abajo a la
## derecha, ese es el choque posible.
func test_the_payout_feed_stays_clear_when_it_is_full() -> void:
	var feed: PayoutFeed = _hud.get_node("Root/CurrencyCluster/PayoutFeed")
	for i: int in PayoutFeed.MAX_ROWS + 2:
		EventBus.kill_payout.emit(20, [KillBonusTracker.BONUS_SPIN,
			KillBonusTracker.BONUS_AIRBORNE, KillBonusTracker.BONUS_MAYHEM],
			130, Vector3.ZERO)
	await wait_physics_frames(4)

	assert_lt(feed.get_child_count(), PayoutFeed.MAX_ROWS + 1,
		"el feed no puede crecer sin tope")
	var currency: Rect2 = _rect("CurrencyCluster")
	assert_false(currency.intersects(_rect("WeaponCluster")),
		"el feed lleno empuja el cluster de plata sobre el del arma")
	assert_true(_screen().encloses(currency), "el feed lleno se sale de pantalla")


# ------------------------------------------------------- el cartel de ayuda

## La regla que reemplaza a "cada uno en su lugar": se turnan.
##
## Existe porque durante un tiempo el cartel se dibujo adentro de la banda del
## aviso, los dos centrados arriba, uno encima del otro - y nadie lo vio porque
## este archivo no lo miraba.
func test_a_hint_waits_while_a_wave_announce_is_up() -> void:
	var wave := WaveData.new()
	wave.par_time = 60.0
	EventBus.wave_started.emit(3, wave)
	await wait_physics_frames(2)
	var announce: Control = _hud.get_node("Root/AnnounceLayer")
	assert_true(announce.visible, "el aviso de oleada tiene que estar en pantalla")

	TutorialHintManager.hint_shown.emit("MANTENE [E] PARA EL GANCHO", 3.0)
	await wait_physics_frames(2)
	assert_false(_hud.get_node("Root/%s" % HINT).visible,
		"la ayuda no puede dibujarse encima del aviso")


func test_the_hint_takes_the_band_once_the_announce_is_gone() -> void:
	var hint: Control = _hud.get_node("Root/%s" % HINT)
	TutorialHintManager.hint_shown.emit("MANTENE [E] PARA EL GANCHO", 3.0)
	await wait_physics_frames(2)
	assert_true(hint.visible, "sin aviso, la ayuda entra de una")


## Una ayuda que caduco mientras esperaba no puede aparecer despues.
func test_a_hint_that_expired_while_waiting_never_shows() -> void:
	var wave := WaveData.new()
	wave.par_time = 60.0
	EventBus.wave_started.emit(3, wave)
	await wait_physics_frames(2)
	TutorialHintManager.hint_shown.emit("TARDE", 3.0)
	TutorialHintManager.hint_hidden.emit()
	await wait_seconds(Tokens.ANNOUNCE_LIFE + 0.2)
	assert_false(_hud.get_node("Root/%s" % HINT).visible)


## Donde sea que este, tiene que estar en pantalla y fuera del centro.
func test_the_hint_stays_on_screen_and_out_of_the_no_ui_zone() -> void:
	TutorialHintManager.hint_shown.emit("MANTENE [E] PARA EL GANCHO", 3.0)
	await wait_physics_frames(2)
	var rect: Rect2 = _rect(HINT)
	var screen: Rect2 = _screen()
	assert_true(screen.encloses(rect), "el cartel de ayuda se sale de pantalla")
	var forbidden := Rect2(screen.position + (screen.size - Tokens.NO_UI_ZONE) * 0.5,
		Tokens.NO_UI_ZONE)
	assert_false(rect.intersects(forbidden), "el cartel de ayuda entra en la zona sin UI")


## Y no puede pisar al cluster de tiempo, que es su otro vecino de banda - el
## choque que aparecio la primera vez que se intento moverlo mas arriba.
func test_the_hint_does_not_sit_on_the_timer() -> void:
	TutorialHintManager.hint_shown.emit("MANTENE [E] PARA EL GANCHO", 3.0)
	await wait_physics_frames(2)
	assert_false(_rect(HINT).intersects(_rect("TimerCluster")))
