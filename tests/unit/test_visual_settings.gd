extends GutTest
## Las opciones que viven en el render y no en un nodo: el ancho del contorno de
## los enemigos (un parametro global de shader) y la SSAO del Environment de la
## arena.

const SettingsGuard = preload("res://tests/settings_guard.gd")

var _guard: SettingsGuard = SettingsGuard.new()


func before_each() -> void:
	_guard.take()


func after_each() -> void:
	_guard.restore()
	SettingsManager.apply_all()


func test_the_outline_default_is_the_token() -> void:
	assert_almost_eq(float(SettingsManager.DEFAULTS["video/enemy_outline_px"]),
		Tokens.ENEMY_OUTLINE_PX, 0.001)


## Lo que llega al shader global. Se lee de SettingsManager y no del
## RenderingServer: el render de la suite (headless) no devuelve los globales.
func test_the_outline_width_is_the_chosen_one() -> void:
	SettingsManager.set_value("video/enemy_outline_px", 2.5)
	assert_almost_eq(SettingsManager.get_enemy_outline_px(), 2.5, 0.001)


func test_the_outline_width_stays_within_its_limits() -> void:
	SettingsManager.set_value("video/enemy_outline_px", 40.0)
	assert_almost_eq(SettingsManager.get_enemy_outline_px(), Tokens.ENEMY_OUTLINE_PX_MAX, 0.001)
	SettingsManager.set_value("video/enemy_outline_px", 0.0)
	assert_almost_eq(SettingsManager.get_enemy_outline_px(), Tokens.ENEMY_OUTLINE_PX_MIN, 0.001)


## El shader lee un global: tiene que estar declarado en project.godot, o el
## contorno no compila y los enemigos se quedan sin borde sin que nada falle.
func test_the_outline_global_is_declared() -> void:
	assert_true(ProjectSettings.has_setting("shader_globals/enemy_outline_px"))


func test_turning_ambient_occlusion_off_reaches_the_arena() -> void:
	var node: WorldEnvironment = add_child_autofree(WorldEnvironment.new())
	var environment := Environment.new()
	environment.ssao_enabled = true
	node.environment = environment
	SettingsManager.set_value("video/ambient_occlusion", true)
	SettingsManager.register_world_environment(node)
	assert_true(node.environment.ssao_enabled)

	SettingsManager.set_value("video/ambient_occlusion", false)
	SettingsManager.apply_all()
	assert_false(node.environment.ssao_enabled)
	assert_true(environment.ssao_enabled,
		"el Environment del tema queda como estaba: se apaga una copia")


func test_the_option_cannot_add_ambient_occlusion_a_theme_did_not_tune() -> void:
	var node: WorldEnvironment = add_child_autofree(WorldEnvironment.new())
	node.environment = Environment.new()
	SettingsManager.set_value("video/ambient_occlusion", true)
	SettingsManager.register_world_environment(node)
	assert_false(node.environment.ssao_enabled)
