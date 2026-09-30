extends RefCounted
## Deja los settings de la maquina exactamente como estaban.
##
## SettingsManager es un autoload que al arrancar carga el `user://settings.cfg`
## de quien corre la suite, y varias pantallas lo guardan al cerrarse. Un test que
## toca un valor y lo devuelve solo en memoria le deja al jugador el archivo con
## los valores del test hasta el proximo guardado; uno que rebindea una tecla le
## cambia los controles. Esto guarda las tres cosas -valores, bindings y el
## archivo tal cual- y las devuelve.
##
##     const SettingsGuard = preload("res://tests/settings_guard.gd")
##     var _guard: SettingsGuard = SettingsGuard.new()
##     func before_each(): _guard.take()
##     func after_each(): _guard.restore()
##
## La regla de BACKLOG_ESTADO §5 sigue valiendo ("seteá lo que leas"): esto
## protege la maquina del test, no el test de la maquina.

var _values: Dictionary = {}
var _bindings: Dictionary = {}
var _events: Dictionary = {}
## El archivo tal cual, o null si no existia.
var _file: Variant = null


func take() -> void:
	_values = {}
	for key: String in SettingsManager.DEFAULTS:
		_values[key] = SettingsManager.get_value(key)
	_bindings = SettingsManager._bindings.duplicate(true)
	_events = {}
	for action: StringName in InputMap.get_actions():
		_events[action] = InputMap.action_get_events(action)
	_file = null
	if FileAccess.file_exists(SettingsManager.SETTINGS_PATH):
		_file = FileAccess.get_file_as_string(SettingsManager.SETTINGS_PATH)


func restore() -> void:
	for key: String in _values:
		SettingsManager.set_value(key, _values[key])
	SettingsManager._bindings = _bindings.duplicate(true)
	for action: StringName in _events:
		if not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		for event: InputEvent in _events[action]:
			InputMap.action_add_event(action, event)
	if _file == null:
		if FileAccess.file_exists(SettingsManager.SETTINGS_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SettingsManager.SETTINGS_PATH))
	else:
		var file: FileAccess = FileAccess.open(SettingsManager.SETTINGS_PATH, FileAccess.WRITE)
		file.store_string(String(_file))
		file.close()
	SettingsManager.apply_all()
