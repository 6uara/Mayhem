extends Node
## La maestria de cada arma y los attachments que desbloquea: lo unico que se
## arrastra de una run a la siguiente.
##
## Jugar con un arma le da experiencia -por kill, por estilo, por oleada limpia,
## por ganar-, la experiencia sube su nivel, y cada nivel desbloquea un
## attachment para esa arma. Lo que el jugador se pone en la Armeria (desde el
## menu de modo) entra a cada run como una mejora de arma mas.
##
## Esto rompe a proposito el "sin meta-progresion" del brief original (DISENO
## §1), por decision del dueño del proyecto (2026-10-16). Lo que lo mantiene
## cerca del espiritu: los attachments son de costado, no para arriba -cada uno
## cobra algo por lo que da (AttachmentData)-, asi que una run con todo
## desbloqueado no es una run mas facil sino una run armada distinto.
##
## Se guarda en su propio archivo, como los perfiles y los hints: "borrame los
## puntajes" no tiene por que borrar lo que el jugador desbloqueo, ni al reves.

signal changed()

const CATALOG_PATH: String = "res://data/attachments/attachment_catalog.tres"
const SAVE_PATH: String = "user://armory.json"
## Donde guarda cuando corre la suite de pruebas. Ver `_ready()`.
const TEST_SAVE_PATH: String = "user://armory_test.json"
## Con que id entra un attachment al UpgradeManager.
const UPGRADE_PREFIX: String = "att_"

## Donde se guarda. Variable para que un test escriba en su propio archivo.
var save_path: String = SAVE_PATH
var catalog: AttachmentCatalog

## id de arma -> experiencia total.
var _xp: Dictionary = {}
## id de arma -> Array de ids de attachment puestos.
var _equipped: Dictionary = {}
## Lo ganado en la run en curso, por arma. Se suma al terminar: una run que se
## abandona a la mitad (cerrar el juego) no guarda nada a medias.
var _run_xp: Dictionary = {}
var _tracking: bool = false
## Lo que dejo la ultima run, para la pantalla de fin. Ver `get_last_report()`.
var _last_report: Array[Dictionary] = []
## id de attachment -> UpgradeData con que se aplica. Hecho una vez por pieza.
var _upgrades: Dictionary = {}


func _ready() -> void:
	catalog = load(CATALOG_PATH) as AttachmentCatalog
	if catalog == null:
		catalog = AttachmentCatalog.new()
	# Bajo GUT, un archivo propio y vacio. Las pruebas que cargan `game.tscn`
	# arrancan runs de verdad, y con la armeria de quien corre la suite puesta
	# medirian un cargador tambor en vez del de serie: el mismo problema que
	# `settings.cfg` le daba a las pruebas de opciones (tests/settings_guard.gd).
	if _running_under_gut():
		save_path = TEST_SAVE_PATH
		reset_progress()
	load_progress()
	EventBus.kill_scored.connect(_on_kill_scored.unbind(4))
	EventBus.kill_payout.connect(_on_kill_payout)
	EventBus.wave_completed.connect(_on_wave_completed.unbind(3))
	EventBus.run_finished.connect(_on_run_finished)


# Public API - progreso

func get_xp(weapon_id: StringName) -> int:
	return int(_xp.get(String(weapon_id), 0))


func get_level(weapon_id: StringName) -> int:
	return catalog.level_for(get_xp(weapon_id))


## La experiencia que pide el proximo nivel, o -1 si el arma ya esta al maximo.
func get_next_threshold(weapon_id: StringName) -> int:
	var level: int = get_level(weapon_id)
	if level >= catalog.level_thresholds.size():
		return -1
	return catalog.level_thresholds[level]


func get_attachments(weapon_id: StringName) -> Array[AttachmentData]:
	return catalog.get_for_weapon(weapon_id)


func is_unlocked(attachment: AttachmentData) -> bool:
	return attachment != null and get_level(attachment.weapon_id) >= attachment.unlock_level


func is_equipped(attachment: AttachmentData) -> bool:
	if attachment == null:
		return false
	return (_equipped.get(String(attachment.weapon_id), []) as Array).has(String(attachment.id))


## Pone o saca un attachment. Uno por ranura: poner uno saca el que hubiera en la
## misma. Devuelve false si no se pudo (bloqueado).
func set_equipped(attachment: AttachmentData, on: bool) -> bool:
	if attachment == null or (on and not is_unlocked(attachment)):
		return false
	var key: String = String(attachment.weapon_id)
	var worn: Array = (_equipped.get(key, []) as Array).duplicate()
	worn.erase(String(attachment.id))
	if on:
		for other: AttachmentData in get_attachments(attachment.weapon_id):
			if other.slot == attachment.slot:
				worn.erase(String(other.id))
		worn.append(String(attachment.id))
	_equipped[key] = worn
	save_progress()
	changed.emit()
	return true


func get_equipped(weapon_id: StringName) -> Array[AttachmentData]:
	var out: Array[AttachmentData] = []
	for id: Variant in _equipped.get(String(weapon_id), []):
		var attachment: AttachmentData = catalog.find(StringName(String(id)))
		if attachment != null and is_unlocked(attachment):
			out.append(attachment)
	return out


## Todos los attachments puestos, en todas las armas, como ids. Para el log de
## la run: una run con attachments no se juega igual que una sin.
func get_loadout_ids() -> Array:
	var out: Array = []
	for weapon_id: String in _equipped:
		for attachment: AttachmentData in get_equipped(StringName(weapon_id)):
			out.append(String(attachment.id))
	out.sort()
	return out


# Public API - la run

## Arranca una run: aplica lo puesto como mejoras de arma y empieza a contar
## experiencia. La llama MatchDirector despues de vaciar el UpgradeManager.
func begin_run() -> void:
	_run_xp.clear()
	_last_report.clear()
	_tracking = true
	apply_loadout()


func apply_loadout() -> void:
	for weapon_id: String in _equipped:
		for attachment: AttachmentData in get_equipped(StringName(weapon_id)):
			UpgradeManager.add_upgrade(_as_upgrade(attachment), attachment.weapon_id)
	# Si el jugador ya estaba en la arena, sus armas se cargaron con los numeros
	# de antes: un cargador tambor que arranca con el cargador de serie no es lo
	# que se eligio.
	var player := Players.local() as Player
	if player != null and player.weapon_holder != null:
		for weapon: WeaponComponent in player.weapon_holder.get_all():
			weapon.reset()
		# Cada reset anuncia su municion por el bus; la ultima palabra tiene que
		# ser la del arma en la mano, o la HUD muestra la de otra.
		if player.weapon != null:
			player.weapon.notify_equipped()


## Lo que dejo la ultima run terminada, un diccionario por arma que gano algo:
## `{ "weapon_id", "gained", "level", "unlocked": Array[AttachmentData] }`.
func get_last_report() -> Array[Dictionary]:
	return _last_report.duplicate()


## Experiencia ganada en la run en curso con `weapon_id`.
func get_run_xp(weapon_id: StringName) -> int:
	return int(_run_xp.get(String(weapon_id), 0))


## Suma experiencia a la run en curso. Publica para las pruebas y la consola.
func add_run_xp(weapon_id: StringName, amount: int) -> void:
	if not _tracking or weapon_id == &"" or amount <= 0:
		return
	var key: String = String(weapon_id)
	_run_xp[key] = int(_run_xp.get(key, 0)) + amount


# Public API - disco

func load_progress() -> void:
	_xp.clear()
	_equipped.clear()
	if not FileAccess.file_exists(save_path):
		return
	# JSON.new() y no parse_string(): el estatico grita un error del motor por un
	# archivo roto, y un archivo roto aca es un caso esperado, no un bug.
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(save_path)) != OK:
		push_warning("Armory: %s is not valid JSON, starting fresh" % save_path)
		return
	var parsed: Variant = json.data
	if not parsed is Dictionary:
		push_warning("Armory: %s is not a JSON object, starting fresh" % save_path)
		return
	var data: Dictionary = parsed
	# Un archivo editado a mano o de otra version: se toma lo que tiene forma y se
	# ignora el resto, como hace SaveManager con la tabla.
	var xp: Variant = data.get("xp", {})
	if xp is Dictionary:
		for key: Variant in xp:
			if (xp[key] is float or xp[key] is int) and float(xp[key]) >= 0.0:
				_xp[String(key)] = int(xp[key])
	var equipped: Variant = data.get("equipped", {})
	if equipped is Dictionary:
		for key: Variant in equipped:
			if equipped[key] is Array:
				var ids: Array = []
				for id: Variant in equipped[key]:
					if id is String:
						ids.append(id)
				_equipped[String(key)] = ids


func save_progress() -> void:
	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Armory: cannot write %s" % save_path)
		return
	file.store_string(JSON.stringify({"xp": _xp, "equipped": _equipped}, "\t"))
	file.close()


## Borra todo lo desbloqueado. Para las pruebas y para el que quiera empezar de
## cero.
func reset_progress() -> void:
	_xp.clear()
	_equipped.clear()
	_run_xp.clear()
	_last_report.clear()
	_tracking = false
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	changed.emit()


# Private

static func _running_under_gut() -> bool:
	for arg: String in OS.get_cmdline_args():
		if arg.contains("gut_cmdln") or arg.contains("res://addons/gut/"):
			return true
	return false


func _as_upgrade(attachment: AttachmentData) -> UpgradeData:
	var upgrade: UpgradeData = _upgrades.get(attachment.id)
	if upgrade == null:
		upgrade = UpgradeData.new()
		upgrade.id = StringName(UPGRADE_PREFIX + String(attachment.id))
		upgrade.display_name = attachment.display_name
		upgrade.description = attachment.description
		upgrade.category = UpgradeData.Category.WEAPON
		upgrade.stat_modifiers = attachment.stat_modifiers
		upgrade.max_stacks = 1
		_upgrades[attachment.id] = upgrade
	return upgrade


func _equipped_weapon() -> StringName:
	var player := Players.local() as Player
	if player == null or player.weapon == null or player.weapon.data == null:
		return &""
	return player.weapon.data.id


func _on_kill_scored() -> void:
	add_run_xp(_equipped_weapon(), catalog.xp_per_kill)


func _on_kill_payout(_reward: int, bonus_ids: Array, _bonus_total: int,
		_position: Vector3) -> void:
	add_run_xp(_equipped_weapon(), catalog.xp_per_style_bonus * bonus_ids.size())


func _on_wave_completed() -> void:
	add_run_xp(_equipped_weapon(), catalog.xp_per_wave)


func _on_run_finished(_score: int, _total_time: float, _waves_cleared: int,
		victory: bool) -> void:
	if not _tracking:
		return
	if victory:
		add_run_xp(_equipped_weapon(), catalog.xp_victory)
	_tracking = false
	_last_report.clear()
	for key: String in _run_xp:
		var weapon_id := StringName(key)
		var gained: int = int(_run_xp[key])
		var before: int = get_level(weapon_id)
		_xp[key] = get_xp(weapon_id) + gained
		var after: int = get_level(weapon_id)
		var unlocked: Array[AttachmentData] = []
		for attachment: AttachmentData in get_attachments(weapon_id):
			if attachment.unlock_level > before and attachment.unlock_level <= after:
				unlocked.append(attachment)
		_last_report.append({
			"weapon_id": weapon_id, "gained": gained, "level": after, "unlocked": unlocked,
		})
	_run_xp.clear()
	if not _last_report.is_empty():
		save_progress()
		changed.emit()
