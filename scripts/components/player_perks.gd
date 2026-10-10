class_name PlayerPerks
extends Node
## Las mejoras que agregan una regla en vez de mover un numero, del lado del
## jugador: regeneracion, Slide Loader, Ram Dash, Headhunter, Momentum Plating y
## Second Wind.
##
## Cada una es un stat con base neutra (0, o 1 en un multiplicador), asi que con
## la mejora sin comprar la regla esta apagada sin un solo `if` por id de mejora:
## comprarla mueve el numero, y el numero enciende la regla. Las otras dos raras
## viven donde ya vive su regla: Air Ace en `WeaponComponent.get_damage()`, Pad
## Charger en `BouncePad`, Showman en `EconomyManager.get_style_multiplier()`.
##
## La crea `Player` en su `_ready()`. Un componente aparte y no mas codigo en
## `player.gd` porque el jugador ya es look + armas + muerte, y estas reglas no son
## ninguna de las tres.

## Segundos sin recibir daño antes de que la regeneracion arranque. Sin esto la
## mejora seria armadura con otro nombre: se curaria en medio de la pelea.
const REGEN_DELAY: float = 3.0
## Alcance del Ram Dash alrededor del cuerpo, en metros.
const RAM_RADIUS: float = 1.9
const RAM_HEIGHT: float = 2.2
## Cuanto queda aturdido lo que se atropella.
const RAM_STUN: float = 0.6
## La ventana sin daño que da el Second Wind al salvarte.
const SECOND_WIND_GRACE: float = 2.0

var player: Player

var _since_damage: float = 999.0
## Fraccion de bala acumulada mientras se desliza: a 30 % del cargador por
## segundo, un frame mete bastante menos que una bala entera.
var _slide_carry: float = 0.0
## Lo que ya se atropello en este dash: cada dash pega una vez a cada uno.
var _rammed: Dictionary = {}
var _second_winds_used: int = 0
var _grace_left: float = 0.0
## stat_key -> valor, recalculado cuando cambian las mejoras.
var _cache: Dictionary = {}


func _ready() -> void:
	UpgradeManager.upgrades_changed.connect(_refresh)
	EventBus.kill_scored.connect(_on_kill_scored)
	if player != null and player.health != null:
		player.health.incoming_scale = _incoming_scale
		player.health.death_guard = _death_guard
		player.health.damaged.connect(_on_damaged.unbind(2))
	_refresh()


func _physics_process(delta: float) -> void:
	if player == null or player.is_dead:
		return
	_since_damage += delta
	_tick_grace(delta)
	_tick_regen(delta)
	_tick_slide_loader(delta)
	_tick_ram()


# Public API

func get_value(stat_key: StringName, base_value: float = 0.0) -> float:
	return float(_cache.get(stat_key, base_value))


func get_second_winds_left() -> int:
	return maxi(int(get_value(StatsComponent.SECOND_WIND_CHARGES)) - _second_winds_used, 0)


# Private

func _refresh() -> void:
	_cache.clear()
	for key: StringName in [StatsComponent.HEALTH_REGEN, StatsComponent.SLIDE_RELOAD_RATE,
			StatsComponent.DASH_RAM_DAMAGE, StatsComponent.HEADSHOT_KILL_REFUND,
			StatsComponent.SPEED_DAMAGE_REDUCTION, StatsComponent.SECOND_WIND_CHARGES]:
		_cache[key] = UpgradeManager.get_stat(key, 0.0)


func _tick_regen(delta: float) -> void:
	var rate: float = get_value(StatsComponent.HEALTH_REGEN)
	if rate <= 0.0 or _since_damage < REGEN_DELAY or player.health == null:
		return
	player.health.heal(rate * delta)


func _tick_slide_loader(delta: float) -> void:
	var rate: float = get_value(StatsComponent.SLIDE_RELOAD_RATE)
	var weapon: WeaponComponent = player.weapon
	if rate <= 0.0 or weapon == null or player.movement == null \
			or player.movement.state != MovementComponent.State.SLIDING:
		_slide_carry = 0.0
		return
	_slide_carry += rate * float(weapon.get_magazine_size()) * delta
	var whole: int = int(_slide_carry)
	if whole <= 0:
		return
	_slide_carry -= float(whole)
	weapon.load_rounds(whole, true)


func _tick_ram() -> void:
	var damage: float = get_value(StatsComponent.DASH_RAM_DAMAGE)
	if damage <= 0.0 or player.movement == null \
			or player.movement.state != MovementComponent.State.DASHING:
		_rammed.clear()
		return
	var here: Vector3 = player.global_position
	for node: Node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := node as Enemy
		if enemy == null or not enemy.is_active or enemy.health == null \
				or enemy.health.is_dead or _rammed.has(enemy.get_instance_id()):
			continue
		var offset: Vector3 = enemy.global_position - here
		if absf(offset.y) > RAM_HEIGHT or Vector2(offset.x, offset.z).length() > RAM_RADIUS:
			continue
		_rammed[enemy.get_instance_id()] = true
		var applied: float = enemy.health.apply_damage(damage, player)
		enemy.apply_stun(RAM_STUN)
		EventBus.damage_dealt.emit(enemy, applied, false)


func _tick_grace(delta: float) -> void:
	if _grace_left <= 0.0:
		return
	_grace_left -= delta
	if _grace_left <= 0.0 and player.health != null:
		player.health.is_invulnerable = false


## Headhunter: una kill por headshot devuelve balas al cargador, gratis.
func _on_kill_scored(_enemy_type: StringName, _position: Vector3, was_headshot: bool,
		_reward: int) -> void:
	var refund: int = int(get_value(StatsComponent.HEADSHOT_KILL_REFUND))
	if not was_headshot or refund <= 0 or player == null or player.weapon == null:
		return
	player.weapon.load_rounds(refund, false)


func _on_damaged() -> void:
	_since_damage = 0.0


## Momentum Plating: a toda velocidad, el golpe entra reducido por el valor del
## stat; parado, entra entero.
func _incoming_scale() -> float:
	var reduction: float = get_value(StatsComponent.SPEED_DAMAGE_REDUCTION)
	if reduction <= 0.0 or player == null or player.movement == null:
		return 1.0
	var speed: float = Vector3(player.velocity.x, 0.0, player.velocity.z).length()
	var share: float = clampf(speed / maxf(player.movement.bhop_max_speed, 0.01), 0.0, 1.0)
	return 1.0 - clampf(reduction, 0.0, 0.9) * share


## Second Wind: el golpe que mataria deja al jugador en 1, una vez por carga, y
## da una ventana corta sin daño para salir de ahi.
func _death_guard() -> bool:
	if get_second_winds_left() <= 0 or player == null or player.health == null:
		return false
	_second_winds_used += 1
	_grace_left = SECOND_WIND_GRACE
	player.health.is_invulnerable = true
	NarratorManager.say(&"second_wind")
	return true
