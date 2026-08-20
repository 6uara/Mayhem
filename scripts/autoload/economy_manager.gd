extends Node
## Currency, income calculation and purchase validation. Never draws UI.

enum PurchaseResult { OK, INSUFFICIENT_FUNDS, MAX_STACKS, INVALID }

const CONFIG_PATH: String = "res://data/economy/economy_config.tres"

var config: EconomyConfig

var currency: int = 0:
	set(value):
		var clamped: int = maxi(value, 0)
		if currency == clamped:
			return
		currency = clamped
		EventBus.currency_changed.emit(currency)

## Per-wave accumulators, reset by WaveManager at wave start.
var _wave_kill_income: int = 0


func _ready() -> void:
	config = load(CONFIG_PATH) as EconomyConfig
	if config == null:
		# Degrade gracefully: a missing resource must never crash the run.
		push_warning("EconomyManager: %s missing, using defaults" % CONFIG_PATH)
		config = EconomyConfig.new()
	# Deliberately not enemy_killed: in coop that fires on the host for every
	# death in the arena, including the ones a client shot. kill_credited is the
	# same event narrowed to "and this wallet gets it" - see EventBus.
	EventBus.kill_credited.connect(_on_kill_credited)
	EventBus.player_died.connect(reset)
	reset()


# Public API

func reset() -> void:
	currency = config.starting_currency
	_wave_kill_income = 0


func begin_wave() -> void:
	_wave_kill_income = 0


func get_wave_kill_income() -> int:
	return _wave_kill_income


## Awards the end-of-wave bonuses and returns the itemised breakdown so the
## wave-complete screen can show all three income sources explicitly.
func award_wave_bonuses(wave: WaveData, duration: float, took_damage: bool) -> Dictionary:
	var speed_bonus: int = _scale(config.get_speed_bonus(duration, wave.par_time))
	var no_damage_bonus: int = 0 if took_damage else _scale(config.no_damage_bonus)
	var completion_bonus: int = _scale(wave.completion_bonus)
	currency += speed_bonus + no_damage_bonus + completion_bonus
	return {
		"kills": _wave_kill_income,
		"speed_bonus": speed_bonus,
		"no_damage_bonus": no_damage_bonus,
		"completion_bonus": completion_bonus,
	}


func can_afford(cost: int) -> bool:
	return currency >= cost


## `weapon_id` is required when `data.category == UpgradeData.Category.WEAPON` -
## it scopes the purchase to the weapon currently equipped (see UpgradeManager).
## Ignored for MOBILITY/SURVIVABILITY upgrades, which stay global.
func try_purchase_upgrade(data: UpgradeData, weapon_id: StringName = &"") -> PurchaseResult:
	if data == null:
		return PurchaseResult.INVALID
	if not UpgradeManager.can_add(data, weapon_id):
		return PurchaseResult.MAX_STACKS
	if not can_afford(data.cost):
		return PurchaseResult.INSUFFICIENT_FUNDS
	if not UpgradeManager.add_upgrade(data, weapon_id):
		return PurchaseResult.INVALID
	currency -= data.cost
	EventBus.purchase_made.emit(data.id, data.cost)
	return PurchaseResult.OK


## Generic spend for non-upgrade items (weapons, utility restocks).
func try_spend(item_id: StringName, cost: int) -> PurchaseResult:
	if cost < 0:
		return PurchaseResult.INVALID
	if not can_afford(cost):
		return PurchaseResult.INSUFFICIENT_FUNDS
	currency -= cost
	EventBus.purchase_made.emit(item_id, cost)
	return PurchaseResult.OK


# Private

func _on_kill_credited(reward: int) -> void:
	var scaled: int = _scale(reward)
	_wave_kill_income += scaled
	currency += scaled


func _scale(amount: int) -> int:
	return int(round(float(amount) * config.currency_multiplier))
