extends Node
## Las reglas de transmision: desde la oleada 3, el Host trae reglas para la
## oleada - doble pago por headshot, botas lunares, el piso arde. Variedad por run
## sin meta-progresion: nada de esto se arrastra, dura una oleada.
##
## Ya no se sortean a ciegas. En la tienda, el Host **ofrece** dos reglas para la
## oleada que viene y el jugador elige una (`prepare_offer` / `choose_rule`); a
## veces trae ademas un **contrato**: una restriccion opcional -sin
## gancho, cargadores cortos- que paga plata si se limpia la oleada con ella. Una
## loteria pasa a ser una decision, que es la fantasia del game show.
##
## Si no hubo oferta (no hubo tienda: la primera oleada, una prueba que emite
## `wave_started`), la regla se sortea como antes.
##
## Autoload para que los que pagan y los que miden (KillBonusTracker,
## EconomyManager, CrowdDropDirector, BroadcastRating, Enemy) puedan preguntar la
## regla activa sin saber de la escena. Pero no hace nada por su cuenta: lo
## enciende `MatchDirector` con `broadcast_rules_enabled`, asi que una prueba que
## emite `wave_started` no se encuentra con una regla que nadie pidio.

const POOL_PATH: String = "res://data/broadcast_rules/rule_pool.tres"
## El id con el que la regla se registra como mejora global mientras dura.
const UPGRADE_PREFIX: String = "rule_"
const CONTRACT_PREFIX: String = "contract_"
## El charco de "el piso arde". El mismo que deja el Environmental: el jugador ya
## aprendio a leerlo.
const KILL_HAZARD_SCENE: PackedScene = preload("res://scenes/arena/hazard_zone.tscn")
## Hasta donde se busca el piso bajo una kill para apoyar el charco. Un Flyer
## muere en el aire, y un charco flotando no se lee.
const KILL_HAZARD_FLOOR_PROBE: float = 30.0

## Hace algo solo cuando esto es true.
var enabled: bool = false
var pool: BroadcastRulePool
var active: BroadcastRule
## El contrato firmado para esta oleada, o null.
var contract: BroadcastRule

var _used: Array[StringName] = []
var _used_contracts: Array[StringName] = []
var _applied_upgrades: Array[StringName] = []
## La oleada (0-based) para la que hay una oferta armada, o -1.
var _offer_wave: int = -1
var _offer_rules: Array[BroadcastRule] = []
var _offer_contract: BroadcastRule
var _chosen_rule: BroadcastRule
var _contract_signed: bool = false
## Cacería: cuantos enemigos aparecieron y cuantos se marcaron en esta oleada.
var _spawned_this_wave: int = 0
var _marked_this_wave: int = 0
## La kill que se esta juzgando era de un marcado. Ver `note_marked_kill()`.
var _pending_marked_kill: bool = false
var _wave_index: int = -1
var _rng: RandomNumberGenerator:
	get:
		return RunSeed.rng(&"broadcast_rules")


func _ready() -> void:
	pool = load(POOL_PATH) as BroadcastRulePool
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.wave_completed.connect(_on_wave_completed.unbind(3))
	EventBus.player_died.connect(_on_player_died)
	EventBus.enemy_killed.connect(_on_enemy_killed)


# Public API

## Una run nueva: se vale repetir reglas de la run anterior.
func reset() -> void:
	end_rule()
	_used.clear()
	_used_contracts.clear()
	_clear_offer()
	_wave_index = -1


func start_rule(rule: BroadcastRule) -> void:
	_end_active()
	if rule == null:
		return
	active = rule
	_used.append(rule.id)
	_apply_modifiers(rule, UPGRADE_PREFIX)
	EventBus.broadcast_rule_started.emit(rule.id, rule.title, rule.description)


## Firma `rule` como contrato de la oleada que corre.
func start_contract(rule: BroadcastRule) -> void:
	_end_contract(false)
	if rule == null:
		return
	contract = rule
	_used_contracts.append(rule.id)
	_apply_modifiers(rule, CONTRACT_PREFIX)
	EventBus.broadcast_contract_started.emit(rule.id, rule.title, rule.description,
		rule.get_contract_payout(_wave_index))


func end_rule() -> void:
	_end_active()
	_end_contract(false)


## La regla que tocaria a la oleada `wave_index` (0-based), o null. Sin repetir
## dentro de la run mientras queden reglas sin usar.
func pick_for(wave_index: int, wave: WaveData) -> BroadcastRule:
	var picked: Array[BroadcastRule] = pick_many(wave_index, wave, 1)
	return picked[0] if not picked.is_empty() else null


## Hasta `count` reglas distintas para la oleada `wave_index`, sin repetir las ya
## usadas en la run mientras queden.
func pick_many(wave_index: int, wave: WaveData, count: int) -> Array[BroadcastRule]:
	var out: Array[BroadcastRule] = []
	if pool == null or pool.rules.is_empty():
		return out
	if wave_index + 1 < pool.from_wave:
		return out
	if pool.skip_elite_waves and wave != null and wave.is_elite_wave:
		return out
	var fresh: Array[BroadcastRule] = _fresh(pool.rules, _used)
	if fresh.size() < count:
		# Se acabo el pozo: se vuelve a empezar, pero sin repetir las que ya
		# salieron de esta tanda.
		_used.clear()
		fresh = _fresh(pool.rules, _used)
	while out.size() < count and not fresh.is_empty():
		out.append(fresh.pop_at(_rng.randi_range(0, fresh.size() - 1)))
	return out


## El contrato que el Host ofreceria para la oleada `wave_index`, o null.
func pick_contract(wave_index: int, wave: WaveData) -> BroadcastRule:
	if pool == null or pool.contracts.is_empty():
		return null
	if wave_index + 1 < pool.contracts_from_wave:
		return null
	if not pool.contracts_on_elite_waves and wave != null and wave.is_elite_wave:
		return null
	if _rng.randf() >= pool.contract_chance:
		return null
	var fresh: Array[BroadcastRule] = _fresh(pool.contracts, _used_contracts)
	if fresh.is_empty():
		_used_contracts.clear()
		fresh = _fresh(pool.contracts, _used_contracts)
	return fresh[_rng.randi_range(0, fresh.size() - 1)] if not fresh.is_empty() else null


## Arma la oferta de la oleada `wave_index`: las reglas para elegir y el contrato
## opcional. La llama MatchDirector al abrir la tienda; la tienda la muestra.
func prepare_offer(wave_index: int, wave: WaveData) -> void:
	_clear_offer()
	if not enabled:
		return
	_offer_wave = wave_index
	_offer_rules = pick_many(wave_index, wave, pool.offer_size if pool != null else 1)
	_offer_contract = pick_contract(wave_index, wave)
	_chosen_rule = _offer_rules[0] if not _offer_rules.is_empty() else null
	var ids: Array = []
	for rule: BroadcastRule in _offer_rules:
		ids.append(rule.id)
	EventBus.broadcast_rules_offered.emit(ids,
		_offer_contract.id if _offer_contract != null else &"")


func has_offer() -> bool:
	return _offer_wave >= 0 and (not _offer_rules.is_empty() or _offer_contract != null)


func get_offer_wave() -> int:
	return _offer_wave


func get_offered_rules() -> Array[BroadcastRule]:
	return _offer_rules.duplicate()


func get_offered_contract() -> BroadcastRule:
	return _offer_contract


func get_chosen_rule() -> BroadcastRule:
	return _chosen_rule


## Elige una de las reglas ofrecidas. Una que no esta en la oferta se ignora: la
## UI no puede colar una regla que el Host no trajo.
func choose_rule(rule: BroadcastRule) -> void:
	if rule != null and _offer_rules.has(rule):
		_chosen_rule = rule


func set_contract_signed(signed: bool) -> void:
	_contract_signed = signed and _offer_contract != null


func is_contract_signed() -> bool:
	return _contract_signed


## El pago del contrato si la oleada se limpia ahora. Lo suma
## `EconomyManager.award_wave_bonuses()`, antes de que la oleada se cierre.
func get_contract_payout() -> int:
	return contract.get_contract_payout(_wave_index) if contract != null else 0


func bonus_multiplier(bonus_id: StringName) -> float:
	return _product(func(rule: BroadcastRule) -> float: return rule.get_bonus_multiplier(bonus_id))


func kill_reward_multiplier() -> float:
	return _product(func(rule: BroadcastRule) -> float: return rule.kill_reward_multiplier)


func rating_gain_multiplier() -> float:
	return _product(func(rule: BroadcastRule) -> float: return rule.rating_gain_multiplier)


func drop_interval_multiplier() -> float:
	return _product(func(rule: BroadcastRule) -> float: return rule.drop_interval_multiplier)


## Vida, velocidad y daño para un enemigo que sale ahora, como Vector3. Lo lee
## `Enemy.setup()`.
func enemy_multipliers(enemy_id: StringName) -> Vector3:
	var result := Vector3.ONE
	for rule: BroadcastRule in _actives():
		result *= rule.get_enemy_multipliers(enemy_id)
	return result


## Si el enemigo que acaba de salir va marcado (Cacería). Cuenta el spawn: se
## llama una vez por enemigo, desde `Enemy.setup()`.
func should_mark_spawn() -> bool:
	_spawned_this_wave += 1
	for rule: BroadcastRule in _actives():
		if rule.mark_every <= 0 or _marked_this_wave >= rule.mark_limit:
			continue
		if _spawned_this_wave % rule.mark_every == 0:
			_marked_this_wave += 1
			return true
	return false


## Un enemigo marcado murio a manos del jugador. Lo avisa el enemigo justo antes
## de `kill_scored`, y KillBonusTracker lo consume al juzgar esa misma kill: la
## señal de la kill no lleva el cuerpo, y esto es sincronico en el mismo frame.
func note_marked_kill() -> void:
	_pending_marked_kill = true


func take_marked_kill() -> bool:
	var was: bool = _pending_marked_kill
	_pending_marked_kill = false
	return was


# Private

func _actives() -> Array[BroadcastRule]:
	var out: Array[BroadcastRule] = []
	if active != null:
		out.append(active)
	if contract != null:
		out.append(contract)
	return out


func _product(read: Callable) -> float:
	var result: float = 1.0
	for rule: BroadcastRule in _actives():
		result *= float(read.call(rule))
	return result


func _fresh(source: Array[BroadcastRule], used: Array[StringName]) -> Array[BroadcastRule]:
	var out: Array[BroadcastRule] = []
	for rule: BroadcastRule in source:
		if rule != null and not used.has(rule.id):
			out.append(rule)
	return out


func _apply_modifiers(rule: BroadcastRule, prefix: String) -> void:
	if rule.stat_modifiers.is_empty():
		return
	var upgrade := UpgradeData.new()
	upgrade.id = StringName(prefix + String(rule.id))
	upgrade.display_name = rule.title
	upgrade.category = UpgradeData.Category.MOBILITY
	upgrade.stat_modifiers = rule.stat_modifiers
	if UpgradeManager.add_upgrade(upgrade):
		_applied_upgrades.append(upgrade.id)


func _remove_modifiers(rule: BroadcastRule, prefix: String) -> void:
	var id := StringName(prefix + String(rule.id))
	if _applied_upgrades.has(id):
		UpgradeManager.remove_upgrade(id)
		_applied_upgrades.erase(id)


func _end_active() -> void:
	if active != null:
		_remove_modifiers(active, UPGRADE_PREFIX)
		active = null
		EventBus.broadcast_rule_ended.emit()


## `cleared` dice si el contrato se cumplio: el pago ya lo sumo EconomyManager
## al cerrar la oleada, esto solo lo anuncia.
func _end_contract(cleared: bool) -> void:
	if contract == null:
		return
	var paid: int = get_contract_payout() if cleared else 0
	var id: StringName = contract.id
	_remove_modifiers(contract, CONTRACT_PREFIX)
	contract = null
	EventBus.broadcast_contract_settled.emit(id, paid)


func _clear_offer() -> void:
	_offer_wave = -1
	_offer_rules.clear()
	_offer_contract = null
	_chosen_rule = null
	_contract_signed = false


func _on_wave_started(wave_index: int, wave: WaveData) -> void:
	end_rule()
	_wave_index = wave_index
	_spawned_this_wave = 0
	_marked_this_wave = 0
	_pending_marked_kill = false
	if not enabled:
		_clear_offer()
		return
	if _offer_wave == wave_index:
		var rule: BroadcastRule = _chosen_rule
		var signed: BroadcastRule = _offer_contract if _contract_signed else null
		_clear_offer()
		if rule != null:
			start_rule(rule)
		if signed != null:
			start_contract(signed)
		return
	_clear_offer()
	var picked: BroadcastRule = pick_for(wave_index, wave)
	if picked != null:
		start_rule(picked)


func _on_wave_completed() -> void:
	_end_active()
	_end_contract(true)


func _on_player_died() -> void:
	_end_active()
	_end_contract(false)
	_clear_offer()


## El piso arde: cada muerte deja un charco donde cayo el cuerpo.
func _on_enemy_killed(_type: StringName, position: Vector3, _reward: int) -> void:
	for rule: BroadcastRule in _actives():
		if rule.kill_hazard_damage > 0.0:
			_spawn_kill_hazard(rule, position)
			return


func _spawn_kill_hazard(rule: BroadcastRule, position: Vector3) -> void:
	var zone := ObjectPool.acquire(KILL_HAZARD_SCENE) as HazardZone
	if zone == null:
		return
	zone.global_position = _floor_under(position)
	# Sin dueño: es una trampa de la transmision, y quema a todos por igual.
	zone.setup(rule.kill_hazard_damage, rule.kill_hazard_radius, rule.kill_hazard_duration)


func _floor_under(position: Vector3) -> Vector3:
	var viewport: Viewport = get_viewport()
	if viewport == null or viewport.get_world_3d() == null:
		return position
	var space: PhysicsDirectSpaceState3D = viewport.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(position + Vector3.UP * 0.5,
		position + Vector3.DOWN * KILL_HAZARD_FLOOR_PROBE, PhysicsLayers.WORLD)
	var hit: Dictionary = space.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else position
