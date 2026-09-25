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
## Lo que se perdio por recibir golpes en esta oleada, en positivo. Se lleva
## aparte del ingreso por kills para que la pantalla de fin de oleada pueda
## mostrarlo como una fila propia - ver Tokens.INCOME_COLOR, que ya reserva un
## color para "lost".
var _wave_damage_loss: int = 0


func _ready() -> void:
	config = load(CONFIG_PATH) as EconomyConfig
	if config == null:
		# Degrade gracefully: a missing resource must never crash the run.
		push_warning("EconomyManager: %s missing, using defaults" % CONFIG_PATH)
		config = EconomyConfig.new()
	# Deliberately not enemy_killed: that one announces a death, kill_credited
	# is the same event narrowed to "and this wallet gets it" - see EventBus.
	EventBus.kill_credited.connect(_on_kill_credited)
	EventBus.kill_payout.connect(_on_kill_payout)
	EventBus.player_damaged.connect(_on_player_damaged.unbind(1))
	EventBus.player_died.connect(reset)
	reset()


# Public API

func reset() -> void:
	currency = config.starting_currency
	_wave_kill_income = 0
	_wave_damage_loss = 0


func begin_wave() -> void:
	_wave_kill_income = 0
	_wave_damage_loss = 0


func get_wave_kill_income() -> int:
	return _wave_kill_income


## Lo perdido por daño en esta oleada, en positivo.
func get_wave_damage_loss() -> int:
	return _wave_damage_loss


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
		"damage_loss": _wave_damage_loss,
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

## El recargo por como se hizo la kill entra por el mismo camino que la
## recompensa base -escalado y sumado al ingreso de la oleada- porque para la
## economia es la misma plata: lo que cambia es por que se pago, y eso ya lo
## cuenta quien emitio la señal.
func _on_kill_payout(_reward: int, _bonus_ids: Array, bonus_total: int,
		_position: Vector3) -> void:
	var total: int = bonus_total
	if total <= 0:
		return
	var scaled: int = _scale(total)
	_wave_kill_income += scaled
	currency += scaled


## Recibir un golpe cuesta plata.
##
## Se cobra sobre el daño efectivamente aplicado, no sobre el nominal: una
## reduccion de daño comprada en la tienda tiene que abaratar tambien esto, o
## seria una mejora que protege la vida y no el bolsillo.
##
## Nunca se cobra mas de lo que hay: `currency` ya se clampea en cero, pero el
## aviso tiene que decir lo que realmente se perdio o la HUD cantaria descuentos
## imaginarios sobre una billetera vacia.
func _on_player_damaged(amount: float) -> void:
	var loss: int = config.get_damage_penalty(amount)
	if loss <= 0 or currency <= 0:
		return
	loss = mini(loss, currency)
	currency -= loss
	_wave_damage_loss += loss
	EventBus.currency_lost.emit(loss, &"damage")


func _on_kill_credited(reward: int) -> void:
	var scaled: int = _scale(reward)
	_wave_kill_income += scaled
	currency += scaled


func _scale(amount: int) -> int:
	return int(round(float(amount) * config.currency_multiplier))
