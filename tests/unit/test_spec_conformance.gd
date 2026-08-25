extends GutTest
## Guards the values the design handoff fixes, in the places they actually live.
##
## Tokens are only useful if the game agrees with them. These catch the case where
## someone tunes a number in a scene or a .tres and quietly diverges from the spec.


func test_enemies_use_the_spec_colours() -> void:
	# Silhouette is the primary read and colour confirms it, so a wrong colour is a
	# wrong identity: the acid Elite must match the HUD's elite-wave stripe, and the
	# magenta Summoner must match the arena's spawn doors.
	for archetype: String in Tokens.ENEMY_HEIGHT.keys():
		var data: EnemyData = load("res://data/enemies/%s.tres" % archetype)
		var expected: Color = Tokens.get("ENEMY_%s" % archetype.to_upper())
		assert_almost_eq(data.body_color.r, expected.r, 0.01, "%s red" % archetype)
		assert_almost_eq(data.body_color.g, expected.g, 0.01, "%s green" % archetype)
		assert_almost_eq(data.body_color.b, expected.b, 0.01, "%s blue" % archetype)


func test_enemies_use_the_spec_heights() -> void:
	for archetype: String in Tokens.ENEMY_HEIGHT.keys():
		var data: EnemyData = load("res://data/enemies/%s.tres" % archetype)
		assert_almost_eq(data.collision_height, float(Tokens.ENEMY_HEIGHT[archetype]), 0.01,
			"%s height" % archetype)


func test_every_archetype_occupies_a_different_rectangle() -> void:
	# The 40m silhouette test: if two archetypes share proportions, one of them is
	# unreadable at range no matter what colour it is.
	#
	# The halo counts. Ranger and Healer have near-identical bodies by design, and
	# the handoff separates them with the Healer's floating ring rather than with
	# proportions - which is also why that ring is a gameplay requirement and not
	# decoration.
	var rectangles: Array[Vector2] = []
	for archetype: String in Tokens.ENEMY_HEIGHT.keys():
		var data: EnemyData = load("res://data/enemies/%s.tres" % archetype)
		var width: float = data.collision_radius * 2.0
		var height: float = data.collision_height
		if data.has_halo:
			# A thin floating ring raises the silhouette; it does not make the enemy
			# read as a wide mass, so it only extends height.
			height = maxf(height, data.halo_height)
		var rect := Vector2(width, height)
		for other: Vector2 in rectangles:
			assert_gt(rect.distance_to(other), 0.25,
				"%s shares a silhouette rectangle with another archetype" % archetype)
		rectangles.push_back(rect)


func test_the_healer_is_the_only_one_with_a_halo() -> void:
	# It is what makes the priority target visible over cover and through crowds.
	for archetype: String in Tokens.ENEMY_HEIGHT.keys():
		var data: EnemyData = load("res://data/enemies/%s.tres" % archetype)
		assert_eq(data.has_halo, archetype == "healer", "%s halo" % archetype)
		assert_eq(data.has_tether, archetype == "healer", "%s tether" % archetype)


func test_the_elite_shares_the_hazard_accent() -> void:
	# Deliberate reuse: the elite-wave stripe on the HUD is the same acid.
	var elite: EnemyData = load("res://data/enemies/elite.tres")
	assert_almost_eq(elite.body_color.g, Tokens.HAZARD.g, 0.02,
		"the Elite is the HUD's elite-wave colour")


func test_dash_charges_match_the_hud_pip_count() -> void:
	var player: Player = add_child_autofree(
		load("res://scenes/player/player.tscn").instantiate())
	await wait_physics_frames(2)
	assert_eq(player.movement.dash_charges_max, Tokens.DASH_CHARGES,
		"the HUD reserves %d pips, so the player gets %d charges" % [
			Tokens.DASH_CHARGES, Tokens.DASH_CHARGES])


func test_shop_timer_matches_the_spec() -> void:
	var shop: CanvasLayer = add_child_autofree(
		load("res://scenes/ui/shop_screen.tscn").instantiate())
	assert_eq(shop.duration, Tokens.SHOP_TIMER)


func test_leaderboard_uses_the_spec_path_and_size() -> void:
	assert_eq(SaveManager.SAVE_PATH, Tokens.LEADERBOARD_PATH)
	assert_eq(SaveManager.MAX_ENTRIES, Tokens.LEADERBOARD_ENTRIES)


func test_settings_defaults_come_from_the_handoff() -> void:
	assert_eq(SettingsManager.DEFAULTS["video/fov"], float(Tokens.FOV_DEFAULT))
	assert_eq(SettingsManager.DEFAULTS["input/mouse_sensitivity"], Tokens.SENS_DEFAULT)
	assert_eq(SettingsManager.DEFAULTS["input/ads_sensitivity_multiplier"],
		Tokens.ADS_MULT_DEFAULT)


func test_fov_default_sits_inside_the_allowed_range() -> void:
	var fov: float = float(SettingsManager.DEFAULTS["video/fov"])
	assert_between(fov, Tokens.FOV_RANGE.x, Tokens.FOV_RANGE.y)


## `SettingsManager` is an autoload that loaded this machine's `user://settings.cfg`
## at boot, so anything it reads is whatever the person running the suite last set
## in the options screen. These tests are about the **spec defaults**, so they put
## every key they read back to its default first, and hand the machine's own
## settings back when they are done.
##
## This is not hypothetical: the ADS test below failed on a dev box that had the
## slider at 2.0, which is a legal position the settings screen offers.
const _SENS_KEYS: Array[String] = [
	"input/mouse_sensitivity",
	"input/ads_sensitivity_multiplier",
]

var _saved_sens: Dictionary = {}


func before_each() -> void:
	for key: String in _SENS_KEYS:
		_saved_sens[key] = SettingsManager.get_value(key)
		SettingsManager.set_value(key, SettingsManager.DEFAULTS[key])


func after_each() -> void:
	for key: String in _saved_sens:
		SettingsManager.set_value(key, _saved_sens[key])
	_saved_sens.clear()


## The slider is the handoff's 0.1-10 scale, but the feel at its default position is
## pinned to 0.25 degrees per pixel - the value the project has used since Phase 0.
func test_default_sensitivity_feels_like_the_original() -> void:
	assert_almost_eq(SettingsManager.get_mouse_sensitivity(false),
		SettingsManager.SENS_DEGREES_AT_DEFAULT, 0.0001,
		"the slider default must feel like 0.25 degrees per pixel")


func test_ads_sensitivity_scales_off_the_same_base() -> void:
	var hip: float = SettingsManager.get_mouse_sensitivity(false)
	var ads: float = SettingsManager.get_mouse_sensitivity(true)
	assert_almost_eq(ads, hip * float(Tokens.ADS_MULT_DEFAULT), 0.0001)


## Out of the box, aiming slows the look. The player may raise the multiplier past
## 1.0 - the settings screen goes to 2.0 and that is deliberate - so this is a claim
## about the default we ship, not an invariant of the setting.
func test_aiming_slows_the_look_by_default() -> void:
	assert_lt(float(Tokens.ADS_MULT_DEFAULT), 1.0,
		"the shipped ADS multiplier must not speed the look up")
	assert_lt(SettingsManager.get_mouse_sensitivity(true),
		SettingsManager.get_mouse_sensitivity(false))


# ------------------------------------------------- la perilla de trazadoras

## La perilla que ralea trazadoras es para cadencia alta, no para muchos
## perdigones, y esa distincion se descubrio rompiendola: la escopeta quedo
## dibujando tres de sus nueve perdigones.
##
## El motivo es que el ojo rellena el hueco *a lo largo del tiempo*. A quince
## disparos por segundo, una bala de cada tres se sigue leyendo como una linea
## continua porque vienen las siguientes. Los nueve perdigones salen todos en el
## mismo instante: ahi el patron de dispersion es el visual entero y no hay nada
## despues que lo complete. Ralearlo se ve como una escopeta mas floja.
##
## Es una regla sobre datos, no sobre codigo, asi que se rompe editando un .tres
## y no falla nada. Por eso vive aca.
func test_no_multi_pellet_weapon_thins_its_tracers() -> void:
	for path: String in _weapon_paths():
		# La carpeta tiene tambien los patrones de retroceso, que son otro recurso.
		# Tipar la variable como WeaponData hace que asignarle uno sea un error de
		# runtime, asi que se castea y se descarta lo que no sea un arma.
		var data := load(path) as WeaponData
		if data == null or data.projectiles_per_shot <= 1:
			continue
		assert_eq(data.tracer_every_n_shots, 1,
			"%s tira %d perdigones de una: tienen que dibujarse todos" % [
				data.id, data.projectiles_per_shot])


## Una trazadora es un proyectil pooleado. Un arma hitscan sin escena de
## proyectil resuelve el impacto y no dibuja absolutamente nada - el disparo
## pega, pero en pantalla no salio ninguna bala.
func test_every_hitscan_weapon_can_still_draw_a_bullet() -> void:
	for path: String in _weapon_paths():
		var data := load(path) as WeaponData
		if data == null or not data.is_hitscan:
			continue
		assert_not_null(data.projectile_scene,
			"%s es hitscan y sin projectile_scene no dibuja la trazadora" % data.id)


func _weapon_paths() -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open("res://data/weapons/")
	if dir == null:
		return found
	for file: String in dir.get_files():
		var name: String = file.trim_suffix(".remap")
		if name.ends_with(".tres"):
			found.append("res://data/weapons/" + name)
	return found
