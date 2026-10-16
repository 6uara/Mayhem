extends GutTest
## Leer un `settings.cfg` que no escribio el juego.
##
## El archivo es texto en `user://` y cualquiera lo puede tocar. Un valor del tipo
## equivocado entraba tal cual: un `fov = "ancho"` llegaba a la camara como 0.

const SettingsGuard = preload("res://tests/settings_guard.gd")

var _guard: SettingsGuard = SettingsGuard.new()


func before_each() -> void:
	_guard.take()


func after_each() -> void:
	_guard.restore()


func _load(text: String) -> void:
	var file: FileAccess = FileAccess.open(SettingsManager.SETTINGS_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	SettingsManager.load_settings()


func test_a_value_of_the_wrong_type_falls_back_instead_of_loading() -> void:
	SettingsManager.set_value("video/fov", 95.0)
	SettingsManager.set_value("input/invert_y", false)
	_load('[video]\nfov="ancho"\n[input]\ninvert_y="si"\n')
	assert_eq(SettingsManager.get_value("video/fov"), 95.0, "queda el que habia")
	assert_eq(SettingsManager.get_value("input/invert_y"), false)


func test_an_int_where_a_float_goes_is_read_as_a_number() -> void:
	_load("[video]\nfov=100\nrender_scale=80.0\n")
	var fov: Variant = SettingsManager.get_value("video/fov")
	assert_eq(typeof(fov), TYPE_FLOAT)
	assert_eq(fov, 100.0)
	var scale: Variant = SettingsManager.get_value("video/render_scale")
	assert_eq(typeof(scale), TYPE_INT, "y al reves tambien, al tipo del default")
	assert_eq(scale, 80)


func test_values_of_the_right_type_load_untouched() -> void:
	_load("[video]\nfov=90.0\n[hud]\ncrosshair_color=Color(1, 0, 0, 1)\n")
	assert_eq(SettingsManager.get_value("video/fov"), 90.0)
	assert_eq(SettingsManager.get_value("hud/crosshair_color"), Color(1, 0, 0, 1))


## Iterar un entero en GDScript recorre un rango: un binding `jump=3` borraba los
## eventos de la accion y no ponia ninguno.
func test_a_binding_that_is_not_a_list_is_ignored() -> void:
	SettingsManager._bindings.erase("jump")
	var before: Array[InputEvent] = InputMap.action_get_events(&"jump")
	_load("[bindings]\njump=3\n")
	assert_eq(InputMap.action_get_events(&"jump").size(), before.size(),
		"la accion conserva lo que tenia")
	assert_false(SettingsManager._bindings.has("jump"))
