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
## 2: origen del daño, semilla y modo, reglas y contratos, rating, pedidos del
## publico, ofertas de la tienda y donde se murio.
## 3: presion de retirada por oleada (`retreat_avg`, `retreat_peak`), para ajustar
## `data/combat/retreat_pressure.tres` con datos.
const FORMAT_VERSION: int = 3
## Cada cuanto se muestrean el rating y la retirada durante una oleada, en segundos.
const RATING_SAMPLE_INTERVAL: float = 1.0

## Donde se escribe. Variable y no solo la constante para que un test escriba en
## su propia carpeta y no entre las runs de quien juega en esa maquina.
var log_dir: String = LOG_DIR

var _log: Dictionary = {}
var _wave: Dictionary = {}
## Las reglas ofrecidas para la proxima oleada, hasta que empiece.
var _pending_offer: Array = []
var _run_start_msec: int = 0
var _rating_samples: int = 0
var _rating_sum: float = 0.0
var _rating_timer: float = 0.0
var _retreat_sum: float = 0.0


func _ready() -> void:
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.wave_completed.connect(_on_wave_completed)
	EventBus.kill_scored.connect(_on_kill_scored)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.player_hit.connect(_on_player_hit)
	EventBus.player_died.connect(_on_player_died)
	EventBus.shop_offers_rolled.connect(_on_shop_offers_rolled)
	EventBus.broadcast_rules_offered.connect(_on_rules_offered)
	EventBus.broadcast_rule_started.connect(_on_rule_started.unbind(2))
	EventBus.broadcast_contract_started.connect(_on_contract_started.unbind(3))
	EventBus.broadcast_contract_settled.connect(_on_contract_settled)
	EventBus.crowd_request_ended.connect(_on_crowd_request_ended)
	EventBus.purchase_made.connect(_on_purchase_made)
	EventBus.weapon_fired.connect(_on_weapon_fired)
	EventBus.run_finished.connect(_on_run_finished)


## El rating se muestrea solo con una oleada abierta: en la tienda no se mueve y
## promediarlo ahi diluiria lo que paso en la pelea.
func _process(delta: float) -> void:
	if _wave.is_empty() or bool(_wave["cleared"]):
		return
	_rating_timer -= delta
	if _rating_timer > 0.0:
		return
	_rating_timer = RATING_SAMPLE_INTERVAL
	var value: float = BroadcastRating.value
	_rating_samples += 1
	_rating_sum += value
	_wave["rating_peak"] = snappedf(maxf(float(_wave["rating_peak"]), value), 0.1)
	_wave["rating_avg"] = snappedf(_rating_sum / float(_rating_samples), 0.1)
	# La presion medida, de 0 a 1, no lo que contesto la horda: la respuesta ya
	# depende de la oleada, y lo que hay que saber es cuanto se retrocede.
	var retreat: float = CombatDirector.retreat.value if CombatDirector.retreat != null else 0.0
	_retreat_sum += retreat
	_wave["retreat_peak"] = snappedf(maxf(float(_wave["retreat_peak"]), retreat), 0.01)
	_wave["retreat_avg"] = snappedf(_retreat_sum / float(_rating_samples), 0.01)


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
		# La semilla en el formato del codigo para compartir: con ella y el modo
		# se vuelve a jugar la misma tienda, las mismas reglas y los mismos regalos.
		"seed": RunSeed.get_seed_text(),
		"mode": GameManager.mode_label(GameManager.run_mode),
		"weapon": String(GameManager.get_starting_weapon_id()),
		"attachments": Armory.get_loadout_ids(),
		"waves": [],
		"purchases": [],
		"shop_offers": [],
		"shots": {},
		"damage_by_cause": {},
		"killed_by": "",
		"death_position": [],
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
		"damage_by_cause": {},
		"rules_offered": [],
		"rule": "",
		"contract": "",
		"contract_paid": 0,
		"rating_peak": 0.0,
		"rating_avg": 0.0,
		"retreat_peak": 0.0,
		"retreat_avg": 0.0,
		"crowd_requests": [],
	}
	# La oferta se arma en la tienda, antes de que la oleada exista: queda
	# guardada hasta que esta la reclama.
	if not _pending_offer.is_empty():
		_wave["rules_offered"] = _pending_offer
		_pending_offer = []
	_rating_samples = 0
	_rating_sum = 0.0
	_rating_timer = 0.0
	_retreat_sum = 0.0
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


func _on_player_hit(amount: float, cause: StringName) -> void:
	if _log.is_empty():
		return
	var key: String = String(cause)
	var totals: Dictionary = _log["damage_by_cause"]
	totals[key] = snappedf(float(totals.get(key, 0.0)) + amount, 0.1)
	if not _wave.is_empty():
		var wave_totals: Dictionary = _wave["damage_by_cause"]
		wave_totals[key] = snappedf(float(wave_totals.get(key, 0.0)) + amount, 0.1)
	# El ultimo golpe hasta ahora. Si la run termina en victoria se borra.
	_log["killed_by"] = key


## Donde se murio, para saber si hay un rincon de la arena que mata.
func _on_player_died() -> void:
	if _log.is_empty():
		return
	var player: Node3D = Players.local()
	if player != null:
		var at: Vector3 = player.global_position
		_log["death_position"] = [snappedf(at.x, 0.1), snappedf(at.y, 0.1), snappedf(at.z, 0.1)]


func _on_shop_offers_rolled(offers: Array) -> void:
	if _log.is_empty():
		return
	var entries: Array = []
	for offer: Variant in offers:
		var item: Dictionary = offer
		entries.append({"id": String(item.get("id", "")), "rare": bool(item.get("rare", false))})
	(_log["shop_offers"] as Array).append({
		"after_wave": int(_wave.get("index", -1)), "offers": entries})


func _on_rules_offered(rule_ids: Array, contract_id: StringName) -> void:
	_pending_offer = []
	for id: Variant in rule_ids:
		_pending_offer.append(String(id))
	if contract_id != &"":
		_pending_offer.append("contract:%s" % contract_id)


func _on_rule_started(rule_id: StringName) -> void:
	if not _wave.is_empty():
		_wave["rule"] = String(rule_id)


func _on_contract_started(contract_id: StringName) -> void:
	if not _wave.is_empty():
		_wave["contract"] = String(contract_id)


func _on_contract_settled(_contract_id: StringName, paid: int) -> void:
	if not _wave.is_empty():
		_wave["contract_paid"] = paid


func _on_crowd_request_ended(request_id: StringName, success: bool) -> void:
	if not _wave.is_empty():
		(_wave["crowd_requests"] as Array).append({"id": String(request_id), "success": success})


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
	# Se va anotando el ultimo golpe; solo queda si de verdad fue el ultimo.
	if victory:
		_log["killed_by"] = ""
	_write()
	_log = {}
	_wave = {}
	_pending_offer = []


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
