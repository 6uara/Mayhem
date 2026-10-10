extends Node
## Las reglas de transmision: desde la oleada 3, el Host sortea una regla para la
## oleada - doble pago por headshot, botas lunares, el publico enloquece. Variedad
## por run sin meta-progresion: nada de esto se arrastra, dura una oleada.
##
## Autoload para que los que pagan y los que miden (KillBonusTracker,
## EconomyManager, CrowdDropDirector, BroadcastRating) puedan preguntar la regla
## activa sin saber de la escena. Pero no sortea por su cuenta: lo enciende
## `MatchDirector` con `broadcast_rules_enabled`, asi que una prueba que emite
## `wave_started` no se encuentra con una regla que nadie pidio.

const POOL_PATH: String = "res://data/broadcast_rules/rule_pool.tres"
## El id con el que la regla se registra como mejora global mientras dura.
const UPGRADE_PREFIX: String = "rule_"

## Sortea en cada oleada solo cuando esto es true.
var enabled: bool = false
var pool: BroadcastRulePool
var active: BroadcastRule

var _used: Array[StringName] = []
var _applied_upgrade: UpgradeData
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	pool = load(POOL_PATH) as BroadcastRulePool
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.wave_completed.connect(_on_wave_completed.unbind(3))
	EventBus.player_died.connect(_on_wave_completed)


# Public API

## Una run nueva: se vale repetir reglas de la run anterior.
func reset() -> void:
	end_rule()
	_used.clear()


func start_rule(rule: BroadcastRule) -> void:
	end_rule()
	if rule == null:
		return
	active = rule
	_used.append(rule.id)
	if not rule.stat_modifiers.is_empty():
		_applied_upgrade = UpgradeData.new()
		_applied_upgrade.id = StringName(UPGRADE_PREFIX + String(rule.id))
		_applied_upgrade.display_name = rule.title
		_applied_upgrade.category = UpgradeData.Category.MOBILITY
		_applied_upgrade.stat_modifiers = rule.stat_modifiers
		UpgradeManager.add_upgrade(_applied_upgrade)
	EventBus.broadcast_rule_started.emit(rule.id, rule.title, rule.description)


func end_rule() -> void:
	if _applied_upgrade != null:
		UpgradeManager.remove_upgrade(_applied_upgrade.id)
		_applied_upgrade = null
	if active != null:
		active = null
		EventBus.broadcast_rule_ended.emit()


## La regla que tocaria a la oleada `wave_index` (0-based), o null. Sin repetir
## dentro de la run mientras queden reglas sin usar.
func pick_for(wave_index: int, wave: WaveData) -> BroadcastRule:
	if pool == null or pool.rules.is_empty():
		return null
	if wave_index + 1 < pool.from_wave:
		return null
	if pool.skip_elite_waves and wave != null and wave.is_elite_wave:
		return null
	var fresh: Array[BroadcastRule] = []
	for rule: BroadcastRule in pool.rules:
		if rule != null and not _used.has(rule.id):
			fresh.append(rule)
	if fresh.is_empty():
		_used.clear()
		for rule: BroadcastRule in pool.rules:
			if rule != null:
				fresh.append(rule)
	return fresh[_rng.randi_range(0, fresh.size() - 1)] if not fresh.is_empty() else null


func bonus_multiplier(bonus_id: StringName) -> float:
	return active.get_bonus_multiplier(bonus_id) if active != null else 1.0


func kill_reward_multiplier() -> float:
	return active.kill_reward_multiplier if active != null else 1.0


func rating_gain_multiplier() -> float:
	return active.rating_gain_multiplier if active != null else 1.0


func drop_interval_multiplier() -> float:
	return active.drop_interval_multiplier if active != null else 1.0


# Private

func _on_wave_started(wave_index: int, wave: WaveData) -> void:
	end_rule()
	if not enabled:
		return
	var rule: BroadcastRule = pick_for(wave_index, wave)
	if rule != null:
		start_rule(rule)


func _on_wave_completed() -> void:
	end_rule()
