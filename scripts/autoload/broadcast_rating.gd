extends Node
## El rating de la transmision: cuanto le gusta al publico lo que esta viendo.
##
## Sube con las kills con estilo, y la velocidad y el ritmo lo amplifican: una
## kill en el aire a toda velocidad en medio de una racha vale mucho mas que la
## misma kill quieto. Baja solo con el tiempo de pelea, y baja de golpe con cada
## kill sin estilo - una oleada entera de kills planas lo tira abajo aunque la
## anterior lo hubiera dejado arriba. Es un estado, no un acumulado.
##
## Para que sirve: multiplica los bonos de estilo, en plata y en puntaje (ver
## EconomyManager.get_style_multiplier), y acorta la espera entre regalos del
## publico (CrowdDropDirector). El estilo paga dos veces, y la fantasia del show
## transmitido deja de ser ambientacion para ser sistema.
##
## Autoload y no nodo del arena por lo mismo que KillBonusTracker: escucha
## EventBus y no le importa que arena esta cargada. Va despues de EconomyManager y
## RunRecord en el orden de autoloads, asi que una kill paga con el rating que
## habia antes de esa kill: el estilo de esta kill sube el de la proxima.

signal changed(value: float, tier: int)

const CONFIG_PATH: String = "res://data/economy/rating_config.tres"
const MAX_VALUE: float = 100.0

var config: RatingConfig
var value: float = 0.0
## Solo mide mientras hay una partida: lo enciende `MatchDirector.start_match()`.
## Fuera de una run (menus, pruebas que emiten kills sueltas) el rating queda en
## cero y no multiplica nada.
var tracking: bool = false

var _tier: int = 0
var _recent_kills: Array[float] = []
var _is_live: bool = false


func _ready() -> void:
	config = load(CONFIG_PATH) as RatingConfig
	if config == null:
		config = RatingConfig.new()
	EventBus.kill_payout.connect(_on_kill_payout)
	EventBus.wave_started.connect(_on_wave_started.unbind(2))
	EventBus.wave_completed.connect(_on_wave_completed.unbind(3))
	EventBus.player_died.connect(_on_wave_completed)


func _process(delta: float) -> void:
	if not _is_live or value <= 0.0:
		return
	_set_value(value - config.decay_per_second * delta)


# Public API

func reset() -> void:
	_recent_kills.clear()
	_is_live = false
	_set_value(0.0)


## Multiplicador de los bonos de estilo, de 1 a `max_multiplier`.
func get_multiplier() -> float:
	return 1.0 + (value / MAX_VALUE) * (config.max_multiplier - 1.0)


## Por cuanto se multiplica la espera entre regalos del publico: 1 con el rating
## en cero, `1 - max_drop_speedup` en cien.
func get_drop_interval_scale() -> float:
	return 1.0 - (value / MAX_VALUE) * config.max_drop_speedup


func get_tier() -> int:
	return _tier


func get_tier_name(tier: int = -1) -> String:
	var index: int = _tier if tier < 0 else tier
	if index >= 0 and index < config.tier_names.size():
		return config.tier_names[index]
	return ""


## Cuanto sube una kill con `bonus_count` bonos, a `speed` m/s, ahora. Publico y
## sin efectos para poder probarlo con numeros puestos a mano.
func gain_for(bonus_count: int, speed: float, recent_kills: int) -> float:
	if bonus_count <= 0:
		return 0.0
	var max_speed: float = 24.0
	var player := Players.local() as Player
	if player != null and player.movement != null:
		max_speed = maxf(player.movement.bhop_max_speed, 0.01)
	var speed_factor: float = 1.0 + config.speed_amplifier * clampf(speed / max_speed, 0.0, 1.0)
	var pace_factor: float = 1.0 + config.pace_per_kill * float(mini(recent_kills, config.pace_cap))
	return config.gain_per_bonus * float(bonus_count) * speed_factor * pace_factor 		* BroadcastRules.rating_gain_multiplier()


# Private

func _on_kill_payout(_reward: int, bonus_ids: Array, _bonus_total: int,
		_position: Vector3) -> void:
	if not tracking:
		return
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	while not _recent_kills.is_empty() and now - _recent_kills[0] > config.pace_window:
		_recent_kills.pop_front()
	var recent: int = _recent_kills.size()
	_recent_kills.push_back(now)
	if bonus_ids.is_empty():
		_set_value(value - config.plain_kill_drop)
		return
	_set_value(value + gain_for(bonus_ids.size(), _player_speed(), recent))


func _on_wave_started() -> void:
	_is_live = tracking


## Entre oleadas no hay pelea que mirar: el rating se congela en la tienda.
func _on_wave_completed() -> void:
	_is_live = false


func _player_speed() -> float:
	var player := Players.local() as Player
	if player == null:
		return 0.0
	return Vector3(player.velocity.x, 0.0, player.velocity.z).length()


func _set_value(next: float) -> void:
	var clamped: float = clampf(next, 0.0, MAX_VALUE)
	if is_equal_approx(clamped, value) and _tier == _tier_for(clamped):
		return
	value = clamped
	var tier: int = _tier_for(value)
	if tier != _tier:
		var went_up: bool = tier > _tier
		_tier = tier
		EventBus.rating_tier_changed.emit(tier, went_up)
	changed.emit(value, _tier)


func _tier_for(rating: float) -> int:
	var tier: int = 0
	for i: int in config.tier_thresholds.size():
		if rating >= config.tier_thresholds[i]:
			tier = i
	return tier
