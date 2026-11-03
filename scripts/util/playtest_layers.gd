class_name PlaytestLayers
extends RefCounted
## Lee que capas del show estan encendidas: el `.tres`, pisado por la linea de
## comandos, pisada a su vez por lo que se fije en runtime (tests, consola).
##
## La linea de comandos existe porque el playtest se juega con un build
## exportado: ahi no se edita un `.tres`, pero un acceso directo con
##
##     Mayhem.exe -- --layers=-rating,-contracts
##
## si se arma en un minuto. `-capa` apaga, `+capa` (o `capa`) enciende, y
## `--layers=none` apaga las cuatro para jugar la pelea pelada.
##
## Estatica y no autoload: no tiene estado de juego ni escucha nada, y la leen
## tres autoloads que arrancan antes que cualquier autoload nuevo.

const CONFIG_PATH: String = "res://data/playtest/playtest_layers.tres"
const ARG_PREFIX: String = "--layers="

const RATING: StringName = &"rating"
const RULES: StringName = &"rules"
const CONTRACTS: StringName = &"contracts"
const CROWD_REQUESTS: StringName = &"crowd_requests"
const ALL: Array[StringName] = [RATING, RULES, CONTRACTS, CROWD_REQUESTS]

## capa -> bool. Lo que se fijo en runtime; gana sobre todo lo demas.
static var _overrides: Dictionary = {}
## capa -> bool, de la linea de comandos. Se lee una vez.
static var _cmdline: Dictionary = {}
static var _cmdline_read: bool = false
static var _config: PlaytestLayersConfig


static func is_on(layer: StringName) -> bool:
	if _overrides.has(layer):
		return bool(_overrides[layer])
	var from_cmdline: Dictionary = _read_cmdline()
	if from_cmdline.has(layer):
		return bool(from_cmdline[layer])
	var config: PlaytestLayersConfig = _get_config()
	match layer:
		RATING:
			return config.rating
		RULES:
			return config.rules
		CONTRACTS:
			return config.contracts
		CROWD_REQUESTS:
			return config.crowd_requests
	return true


## Fija una capa hasta `clear_overrides()`. Para los tests y la consola de dev.
static func set_override(layer: StringName, on: bool) -> void:
	_overrides[layer] = on


static func clear_overrides() -> void:
	_overrides.clear()


## Las capas apagadas, en orden fijo. Lo que anota el log de la run: una run
## jugada sin rating no se compara con una que lo tuvo.
static func get_disabled() -> Array[String]:
	var off: Array[String] = []
	for layer: StringName in ALL:
		if not is_on(layer):
			off.append(String(layer))
	return off


## `--layers=` ya separado en capas. Publico para poder probarlo sin lanzar el
## juego con argumentos.
static func parse(spec: String) -> Dictionary:
	var result: Dictionary = {}
	var text: String = spec.strip_edges().to_lower()
	if text == "none":
		for layer: StringName in ALL:
			result[layer] = false
		return result
	if text == "all":
		for layer: StringName in ALL:
			result[layer] = true
		return result
	for raw: String in text.split(",", false):
		var token: String = raw.strip_edges()
		var on: bool = not token.begins_with("-")
		token = token.trim_prefix("-").trim_prefix("+")
		var layer := StringName(token)
		if ALL.has(layer):
			result[layer] = on
		else:
			push_warning("PlaytestLayers: unknown layer '%s'" % token)
	return result


static func _read_cmdline() -> Dictionary:
	if _cmdline_read:
		return _cmdline
	_cmdline_read = true
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(ARG_PREFIX):
			_cmdline = parse(arg.substr(ARG_PREFIX.length()))
	return _cmdline


static func _get_config() -> PlaytestLayersConfig:
	if _config == null:
		_config = load(CONFIG_PATH) as PlaytestLayersConfig
		if _config == null:
			_config = PlaytestLayersConfig.new()
	return _config
