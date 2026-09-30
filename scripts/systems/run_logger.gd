class_name RunLogger
extends Node
## Escribe lo que paso en cada run a `user://runs/`, un JSON por run.
##
## Para el playtest (G3) y el balance (G4). Sin esto, lo que vuelve de una sesion
## de prueba son impresiones - "la ola 7 estaba dificil" - y el balance se hace
## contra el recuerdo de alguien. Con esto vuelve en que ola murio, cuanto tardo
## cada una contra su par, cuanto daño entro, que mato a quien y que se compro.
##
## Solo local: el juego no habla con ningun servidor (README) y esto no lo
## cambia. El playtester manda el archivo si quiere; `get_log_dir()` dice donde
## esta para que la pantalla de feedback lo pueda nombrar.
##
## No mide nada propio: todo llega por EventBus, igual que RunRecord.

const LOG_DIR: String = "user://runs"
## Cuantas runs se guardan. Las mas viejas se borran: esto es para la sesion de
## prueba de la semana, no un historial.
const MAX_LOGS: int = 30
const FORMAT_VERSION: int = 1

## Donde se escribe. Variable y no solo la constante para que un test escriba en
## su propia carpeta y no entre las runs de quien juega en esa maquina.
var log_dir: String = LOG_DIR

var _log: Dictionary = {}
var _wave: Dictionary = {}
var _run_start_msec: int = 0


func _ready() -> void:
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.wave_completed.connect(_on_wave_completed)
	EventBus.kill_scored.connect(_on_kill_scored)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.purchase_made.connect(_on_purchase_made)
	EventBus.weapon_fired.connect(_on_weapon_fired)
	EventBus.run_finished.connect(_on_run_finished)


# Public API

func get_log_dir() -> String:
	return ProjectSettings.globalize_path(log_dir)


## La run en curso tal como se escribiria ahora. Para los tests.
func get_current_log() -> Dictionary:
	return _log


# Private

func _begin_run() -> void:
	_run_start_msec = Time.get_ticks_msec()
	_log = {
		"format": FORMAT_VERSION,
		"version": String(ProjectSettings.get_setting("application/config/version", "")),
		"started": Time.get_datetime_string_from_system(false, true),
		"waves": [],
		"purchases": [],
		"shots": {},
	}


func _on_wave_started(wave_index: int, config: WaveData) -> void:
	# La primera ola abre una run nueva: MatchDirector resetea todo junto antes
	# de lanzarla, asi que no queda nada de la anterior que arrastrar.
	if wave_index == 0 or _log.is_empty():
		_begin_run()
	_wave = {
		"index": wave_index,
		"par_time": config.par_time if config != null else 0.0,
		"duration": 0.0,
		"damage_taken": 0.0,
		"hits_taken": 0,
		"kills": {},
		"headshots": 0,
		"currency_at_start": EconomyManager.currency,
		"cleared": false,
	}
	(_log["waves"] as Array).append(_wave)


func _on_wave_completed(_wave_index: int, duration: float, damage_taken: float) -> void:
	if _wave.is_empty():
		return
	_wave["duration"] = snappedf(duration, 0.01)
	_wave["damage_taken"] = snappedf(damage_taken, 0.1)
	_wave["cleared"] = true


func _on_kill_scored(enemy_type: StringName, _position: Vector3, was_headshot: bool,
		_reward: int) -> void:
	if _wave.is_empty():
		return
	var kills: Dictionary = _wave["kills"]
	kills[String(enemy_type)] = int(kills.get(String(enemy_type), 0)) + 1
	if was_headshot:
		_wave["headshots"] = int(_wave["headshots"]) + 1


func _on_player_damaged(amount: float, _remaining: float) -> void:
	if _wave.is_empty():
		return
	_wave["hits_taken"] = int(_wave["hits_taken"]) + 1
	# Mientras la ola corre; al cerrarse, wave_completed trae el total oficial.
	if not bool(_wave["cleared"]):
		_wave["damage_taken"] = snappedf(float(_wave["damage_taken"]) + amount, 0.1)


func _on_purchase_made(item_id: StringName, cost: int) -> void:
	if _log.is_empty():
		return
	var after_wave: int = int(_wave.get("index", -1))
	(_log["purchases"] as Array).append({
		"item": String(item_id), "cost": cost, "after_wave": after_wave})


func _on_weapon_fired(weapon_id: StringName) -> void:
	if _log.is_empty():
		return
	var shots: Dictionary = _log["shots"]
	shots[String(weapon_id)] = int(shots.get(String(weapon_id), 0)) + 1


func _on_run_finished(score: int, total_time: float, waves_cleared: int,
		victory: bool) -> void:
	if _log.is_empty():
		return
	_log["score"] = score
	_log["total_time"] = snappedf(total_time, 0.01)
	_log["waves_cleared"] = waves_cleared
	_log["victory"] = victory
	_log["currency_left"] = EconomyManager.currency
	# Donde termino, cuando no fue una victoria: la ola que estaba abierta.
	_log["died_in_wave"] = -1 if victory else int(_wave.get("index", -1))
	_write()
	_log = {}
	_wave = {}


func _write() -> void:
	if DirAccess.make_dir_recursive_absolute(get_log_dir()) != OK:
		push_warning("RunLogger: cannot create %s" % log_dir)
		return
	var stamp: String = Time.get_datetime_string_from_system(false, false) \
		.replace(":", "-").replace("T", "_")
	var path: String = "%s/run_%s.json" % [log_dir, stamp]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("RunLogger: cannot write %s" % path)
		return
	file.store_string(JSON.stringify(_log, "\t"))
	file.close()
	_prune()


func _prune() -> void:
	var files: PackedStringArray = DirAccess.get_files_at(log_dir)
	var logs: Array[String] = []
	for file_name: String in files:
		if file_name.begins_with("run_") and file_name.ends_with(".json"):
			logs.append(file_name)
	# El nombre lleva la fecha en ISO, asi que el orden alfabetico es el temporal.
	logs.sort()
	while logs.size() > MAX_LOGS:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(
			"%s/%s" % [log_dir, logs.pop_front()]))
