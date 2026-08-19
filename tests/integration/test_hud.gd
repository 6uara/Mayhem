extends GutTest
## The HUD is all signal-driven, so a renamed node or a broken connection fails
## silently in play. These assert the tree the script expects actually exists, that
## the layout law holds, and that state changes reach the widgets.

var _player: Player
var _hud: CanvasLayer


func before_each() -> void:
	EconomyManager.reset()
	UpgradeManager.reset()
	_player = add_child_autofree(load("res://scenes/player/player.tscn").instantiate())
	_hud = add_child_autofree(load("res://scenes/ui/hud.tscn").instantiate())
	await wait_physics_frames(3)


func after_each() -> void:
	EconomyManager.reset()
	UpgradeManager.reset()


func _node(path: String) -> Node:
	return _hud.get_node_or_null(path)


func test_every_cluster_the_script_reads_exists() -> void:
	for path: String in [
			"Root/Reticle",
			"Root/WaveCluster/WaveRow/Value", "Root/WaveCluster/EnemiesRow/Count",
			"Root/TimerCluster/TimeRow/Elapsed", "Root/TimerCluster/ParBar",
			"Root/TimerCluster/NoDamageRow/Mark", "Root/TimerCluster/NoDamageRow/Text",
			"Root/CurrencyCluster/CurrencyRow/Amount", "Root/CurrencyCluster/PowerUpList",
			"Root/VitalsCluster/HealthRow/Value", "Root/VitalsCluster/HealthRow/CriticalTag",
			"Root/VitalsCluster/HealthSegments", "Root/VitalsCluster/DashRow/Pips",
			"Root/AbilityBar",
			"Root/WeaponCluster/AmmoRow/Magazine", "Root/WeaponCluster/AmmoRow/Reserve",
			"Root/WeaponCluster/AmmoRow/ReloadPrompt", "Root/WeaponCluster/AmmoPips",
			"Root/WeaponCluster/WeaponList",
			"Root/SubtitleBox/Row/Tag", "Root/SubtitleBox/Row/Body",
			"Root/AnnounceLayer/TagPill/Tag", "Root/AnnounceLayer/Title",
			"Root/DamageIndicators", "Root/StateOverlays",
			"Root/StateOverlays/DamageVignette", "Root/StateOverlays/LowHealthFrame",
			"Root/StateOverlays/EliteStripe"]:
		assert_not_null(_node(path), "missing HUD node: %s" % path)


func test_custom_widgets_kept_their_scripts() -> void:
	assert_true(_node("Root/Reticle") is Reticle, "reticle script")
	assert_true(_node("Root/VitalsCluster/HealthSegments") is SegmentStrip, "health strip")
	assert_true(_node("Root/VitalsCluster/DashRow/Pips") is SegmentStrip, "dash pips")
	assert_true(_node("Root/CurrencyCluster/CurrencyRow/Ring") is MayhemIcon, "currency ring")
	assert_true(_node("Root/StateOverlays/EliteStripe") is StripeBar, "elite stripe")


## The centre 900x500 belongs to the crosshair. Nothing else may enter it.
func test_no_cluster_intrudes_on_the_no_ui_zone() -> void:
	var screen := Vector2(1920, 1080)
	var forbidden := Rect2((screen - Tokens.NO_UI_ZONE) * 0.5, Tokens.NO_UI_ZONE)
	for name: String in ["WaveCluster", "TimerCluster", "CurrencyCluster",
			"VitalsCluster", "AbilityBar", "WeaponCluster", "AnnounceLayer"]:
		var cluster: Control = _node("Root/%s" % name)
		var rect := Rect2(cluster.position, cluster.size)
		assert_false(forbidden.intersects(rect),
			"%s enters the no-UI zone (%s vs %s)" % [name, rect, forbidden])


func test_health_reaches_the_number_and_the_segments() -> void:
	var value: Label = _node("Root/VitalsCluster/HealthRow/Value")
	var segments: SegmentStrip = _node("Root/VitalsCluster/HealthSegments")
	assert_eq(segments.count, Tokens.HEALTH_SEGMENTS)

	_player.health.apply_damage(50.0)
	await wait_physics_frames(2)
	assert_eq(value.text, "50", "the number follows health")
	assert_eq(segments.filled, 5, "half the segments remain")


## Low health is three signals at once: colour, a tag and the frame.
func test_low_health_raises_every_signal() -> void:
	var critical: Control = _node("Root/VitalsCluster/HealthRow/CriticalTag")
	var frame: Control = _node("Root/StateOverlays/LowHealthFrame")
	assert_false(critical.visible, "not critical at full health")

	_player.health.apply_damage(_player.health.max_health * 0.8)
	await wait_physics_frames(2)
	assert_true(critical.visible, "CRITICAL tag")
	assert_true(frame.visible, "screen frame")
	assert_eq(_node("Root/VitalsCluster/HealthRow/Value").get_theme_color("font_color"),
		Tokens.ENEMY, "the number turns crimson")


func test_low_ammo_raises_the_reload_prompt() -> void:
	var prompt: Control = _node("Root/WeaponCluster/AmmoRow/ReloadPrompt")
	assert_false(prompt.visible, "hidden on a full magazine")

	var weapon: WeaponComponent = _player.weapon
	EventBus.ammo_changed.emit(1, 100)
	await wait_physics_frames(2)
	assert_true(prompt.visible, "one round left is low ammo")
	assert_eq(_node("Root/WeaponCluster/AmmoRow/Magazine").text, "1")
	assert_not_null(weapon)


func test_currency_reaches_the_cluster() -> void:
	EconomyManager.currency = 1480
	await wait_physics_frames(2)
	assert_eq(_node("Root/CurrencyCluster/CurrencyRow/Amount").text, "1480")


func test_dash_pips_track_the_movement_component() -> void:
	var pips: SegmentStrip = _node("Root/VitalsCluster/DashRow/Pips")
	await wait_physics_frames(2)
	assert_eq(pips.count, _player.movement.get_dash_charges_max(),
		"one pip per charge, however many upgrades granted")
	assert_eq(pips.filled, pips.count, "all charges start ready")


func test_elite_wave_raises_the_stripe() -> void:
	var stripe: Control = _node("Root/StateOverlays/EliteStripe")
	assert_false(stripe.visible)

	var wave := WaveData.new()
	wave.is_elite_wave = true
	EventBus.wave_started.emit(4, wave)
	await wait_physics_frames(2)
	assert_true(stripe.visible, "elite waves carry the acid stripe")
	assert_eq(_node("Root/WaveCluster/WaveRow/Value").get_theme_color("font_color"),
		Tokens.HAZARD, "the wave number turns acid")


func test_ability_bar_holds_three_utilities_a_divider_and_the_grapple() -> void:
	var bar: HBoxContainer = _node("Root/AbilityBar")
	assert_eq(bar.get_child_count(), UtilityComponent.SLOT_COUNT + 2,
		"three utility slots, a divider and the grapple")


# ------------------------------------------- los contadores que ya no se reescriben

## El HUD dejo de reescribir los dos contadores de oleada en cada frame y ahora
## recuerda el valor que mostro. Eso es rendimiento, pero introduce un riesgo
## peor que el que resuelve: una cache desincronizada no se ve lenta, se ve
## mintiendo. Estos tests son sobre lo segundo.
##
## Se espera con wait_process_frames y no con frames de fisica: _tick_wave corre
## en _process, y esperar el tick equivocado lee el label antes de que se pinte.
##
## Los contadores se fijan a mano en vez de dejar que la oleada los mueva: con un
## spawner nulo el agendado resuelve los spawns en frames impredecibles, y el
## test terminaba midiendo eso en vez de la cache. Lo que se quiere clavar es
## "cuando el numero cambia, el label cambia", y para eso el numero tiene que ser
## una decision del test.
func _open_wave(alive: int, par: float = 60.0) -> void:
	var wave := WaveData.new()
	wave.par_time = par
	# Sin start_next_wave(): esa agenda spawns en corrutinas que siguen tocando
	# los contadores en frames impredecibles, y el test terminaba midiendo el
	# agendador en vez de la cache del HUD. Aca se pone el estado que el HUD lee
	# y nada mas se mueve.
	WaveManager.waves = [wave]
	WaveManager.current_index = 0
	WaveManager.is_wave_active = true
	WaveManager._pending_spawns = 0
	WaveManager._alive_enemies = alive
	WaveManager._wave_start_time = float(Time.get_ticks_msec()) / 1000.0


func test_the_enemy_counter_follows_the_wave() -> void:
	_open_wave(5)
	await wait_process_frames(3)
	var label: Label = _node("Root/WaveCluster/EnemiesRow/Count")
	assert_eq(label.text, "5", "lo que muestra es lo que queda")

	WaveManager._alive_enemies = 3
	await wait_process_frames(3)
	assert_eq(label.text, "3", "y sigue al numero cuando cambia")
	WaveManager.reset()


## El caso que la cache podia arruinar y que no da error: una oleada nueva que
## abre con el mismo numero con el que cerro la anterior. Si el HUD recuerda "ya
## mostre 3" de la oleada pasada, no vuelve a escribir el 3 - y el label se queda
## con lo que hubiera quedado de antes.
func test_a_new_wave_that_opens_on_the_same_numbers_still_paints_them() -> void:
	_open_wave(3)
	await wait_process_frames(3)
	var label: Label = _node("Root/WaveCluster/EnemiesRow/Count")
	assert_eq(label.text, "3", "primera oleada pintada")

	label.text = "basura"
	_open_wave(3)
	await wait_process_frames(3)
	assert_eq(label.text, "3", "oleada nueva con el mismo numero: se repinta igual")
	WaveManager.reset()


## El PAR se formatea una sola vez por oleada porque no se mueve mientras corre.
## Que no se mueva no significa que no tenga que aparecer al cambiar de oleada.
func test_the_par_label_follows_a_change_of_wave() -> void:
	_open_wave(2, 30.0)
	await wait_process_frames(3)
	var par: Label = _node("Root/TimerCluster/TimeRow/Par")
	var first: String = par.text

	_open_wave(2, 90.0)
	await wait_process_frames(3)
	assert_ne(par.text, first, "otra par_time, otro texto")
	WaveManager.reset()
