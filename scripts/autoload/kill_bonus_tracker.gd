extends Node
## Juzga cada kill del jugador y reparte recargos por como la hizo.
##
## Existe porque `kill_credited` solo dice cuanto vale el cuerpo, y un juego que
## paga lo mismo por fusilar a un Rusher parado que por bajarlo girando en el
## aire no tiene ninguna razon para que el jugador intente lo segundo. Lo que
## esto agrega no es dificultad ni vida: es que las cosas que ya se pueden hacer
## empiecen a pagar.
##
## Reparto de responsabilidades, deliberado: esto decide **si** un bono se
## cumplio, y EconomyConfig decide **cuanto** vale. Agregar un bono nuevo es una
## regla aca y un numero alla, nunca un numero aca.
##
## Nada de lo que mide se pregunta al morir el enemigo salvo la posicion: el
## estado del jugador (aire, gancho, dash, cargador, giro de camara) se sigue
## frame a frame, porque en el instante de la kill ya es tarde para reconstruir
## de donde venia.

## Los ids que viajan en `EventBus.kill_payout` y que EconomyConfig
## traduce a plata. StringName y no enum para que un bono nuevo no renumere a
## los que ya estan guardados en una run vieja.
const BONUS_HEADSHOT: StringName = &"headshot"
const BONUS_AIRBORNE: StringName = &"airborne"
const BONUS_SPIN: StringName = &"spin"
const BONUS_GRAPPLE: StringName = &"grapple"
const BONUS_DASH: StringName = &"dash"
const BONUS_LONG_SHOT: StringName = &"long_shot"
const BONUS_POINT_BLANK: StringName = &"point_blank"
const BONUS_LAST_ROUND: StringName = &"last_round"
const BONUS_DOUBLE: StringName = &"double"
const BONUS_TRIPLE: StringName = &"triple"
const BONUS_MAYHEM: StringName = &"mayhem"
const BONUS_PRIORITY: StringName = &"priority"

## Como se llama cada bono en pantalla. Vive aca y no en la HUD porque el nombre
## es parte de la regla: si un bono se renombra, se renombra en un solo lugar.
const BONUS_LABEL: Dictionary = {
	BONUS_HEADSHOT: "HEADSHOT",
	BONUS_AIRBORNE: "EN EL AIRE",
	BONUS_SPIN: "360",
	BONUS_GRAPPLE: "EN EL GANCHO",
	BONUS_DASH: "EN EL DASH",
	BONUS_LONG_SHOT: "A DISTANCIA",
	BONUS_POINT_BLANK: "A QUEMARROPA",
	BONUS_LAST_ROUND: "ULTIMA BALA",
	BONUS_DOUBLE: "DOBLE",
	BONUS_TRIPLE: "TRIPLE",
	BONUS_MAYHEM: "MAYHEM",
	BONUS_PRIORITY: "PRIORIDAD",
}

## Metros desde los que un tiro cuenta como lejano, y hasta los que cuenta como
## a quemarropa. El hueco entre ambos es a proposito: la mayoria de los tiros de
## una run caen ahi y no pagan nada extra, que es lo que deja a los bonos
## significando algo.
const LONG_SHOT_DISTANCE: float = 32.0
const POINT_BLANK_DISTANCE: float = 4.5

## Grados de giro acumulados que cuentan como vuelta completa. Menos de 360
## porque la kill casi nunca cae en el grado exacto en que se cierra el giro, y
## exigir el redondo entero es pedir una precision que ni se ve ni se siente.
const SPIN_DEGREES: float = 330.0
## Quieto mas que esto y el giro acumulado se borra: dos medias vueltas
## separadas por una caminata no son un 360.
const SPIN_IDLE_RESET: float = 0.35
## Por debajo de esto (grados por frame) la camara se considera quieta.
const SPIN_EPSILON: float = 0.05

## Ventana en la que un dash sigue contando como "mate dashando". Un dash dura
## 0.16s: esto cubre el dash mas los pasos que salen de el.
const DASH_WINDOW: float = 0.55
## Ventana en la que varias kills cuentan como una sola racha.
const MULTI_WINDOW: float = 1.5

## Cuanto despues de que entre una cura sigue contando como "lo mataste mientras
## curaba".
##
## Es una aproximacion declarada, no una medicion: lo que llega en la kill es el
## id del arquetipo y donde cayo, no que Healer era ni a quien estaba curando.
## Con varios Healers vivos esto puede acreditarle a uno la cura del otro - y es
## aceptable, porque lo que el bono premia no es la identidad del cuerpo sino
## haber cortado la cura que estaba sosteniendo a la oleada, que en ese caso
## tambien es cierto.
const PRIORITY_WINDOW: float = 3.0
## El arquetipo que cura. Coincide con el `id` de data/enemies/healer.tres.
const HEALER_ID: StringName = &"healer"

## La kill mas alta de la escala de multikill. Cuatro o mas caen todas aca: a
## partir de ahi lo que importa es que fue enorme, no el numero exacto.
const MAYHEM_KILLS: int = 4

var _player: Player

## Grados girados sin frenar ni cambiar de sentido, con signo. Ver _tick_spin().
var _spin_accum: float = 0.0
var _spin_idle_time: float = 0.0
var _last_yaw: float = 0.0
var _has_yaw: bool = false

## Cuando se gasto el ultimo dash, en segundos de reloj del juego.
var _last_dash_time: float = -999.0
## Cuando entro la ultima cura a cualquier enemigo.
var _last_heal_time: float = -999.0
## Momento de la kill anterior y cuantas van en esta racha.
var _last_kill_time: float = -999.0
var _streak: int = 0


func _ready() -> void:
	EventBus.local_player_spawned.connect(_on_player_spawned)
	EventBus.dash_used.connect(_on_dash_used.unbind(1))
	EventBus.kill_scored.connect(_on_kill_scored)
	EventBus.healed.connect(_on_healed.unbind(2))
	EventBus.wave_started.connect(_on_wave_started.unbind(2))
	EventBus.player_died.connect(reset)


func _process(delta: float) -> void:
	_tick_spin(delta)


# Public API

## Como se llama un bono en pantalla, o el id crudo si es uno que esta tabla no
## conoce - nunca vacio, para que la HUD no tenga que defenderse.
static func get_label(bonus_id: StringName) -> String:
	return String(BONUS_LABEL.get(bonus_id, String(bonus_id).to_upper()))


func reset() -> void:
	_spin_accum = 0.0
	_spin_idle_time = 0.0
	_has_yaw = false
	_last_dash_time = -999.0
	_last_heal_time = -999.0
	_last_kill_time = -999.0
	_streak = 0


# Private

func _on_player_spawned(player: Node3D) -> void:
	_player = player as Player
	_has_yaw = false
	reset()


func _on_dash_used() -> void:
	_last_dash_time = _now()


func _on_healed() -> void:
	_last_heal_time = _now()


## Cada oleada empieza con la racha en cero: una kill de la oleada pasada y la
## primera de esta no son un doble, aunque el reloj diga que pasaron 1.2s.
func _on_wave_started() -> void:
	_last_kill_time = -999.0
	_streak = 0


## Giro acumulado de la camara, con signo y sin historial.
##
## Un buffer de los ultimos N frames seria mas exacto y no vale lo que cuesta:
## lo unico que hay que distinguir es "giro seguido para el mismo lado" de
## "movio la camara de un lado a otro", y para eso alcanza con borrar el
## acumulado cuando cambia el sentido o cuando la camara se queda quieta.
func _tick_spin(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var yaw: float = rad_to_deg(_player.global_rotation.y)
	if not _has_yaw:
		_last_yaw = yaw
		_has_yaw = true
		return
	# Por el salto de +180 a -180 al cruzar la vuelta.
	var step: float = rad_to_deg(angle_difference(deg_to_rad(_last_yaw), deg_to_rad(yaw)))
	_last_yaw = yaw

	if absf(step) < SPIN_EPSILON:
		_spin_idle_time += delta
		if _spin_idle_time >= SPIN_IDLE_RESET:
			_spin_accum = 0.0
		return
	_spin_idle_time = 0.0
	if signf(step) != signf(_spin_accum) and _spin_accum != 0.0:
		_spin_accum = step
	else:
		_spin_accum += step


## Siempre emite `kill_payout`, con bonos o sin ellos: es el unico evento que
## cierra la cuenta de una kill, y quien muestra la plata ganada tiene que poder
## colgarse de uno solo. Ver EventBus.kill_payout.
func _on_kill_scored(enemy_type: StringName, position: Vector3, was_headshot: bool,
		reward: int) -> void:
	var bonuses: Array = _evaluate(enemy_type, position, was_headshot)
	var config: EconomyConfig = EconomyManager.config
	var total: int = 0
	for id: StringName in bonuses:
		total += config.get_kill_bonus(id)
	EventBus.kill_payout.emit(reward, bonuses, total, position)


## Los bonos que cumple esta kill, en el orden en que se leen mejor: primero lo
## que hizo el jugador, al final la racha.
func _evaluate(enemy_type: StringName, position: Vector3, was_headshot: bool) -> Array:
	var bonuses: Array = []
	if was_headshot:
		bonuses.append(BONUS_HEADSHOT)

	var now: float = _now()
	if enemy_type == HEALER_ID and now - _last_heal_time <= PRIORITY_WINDOW:
		bonuses.append(BONUS_PRIORITY)
	if _player != null and is_instance_valid(_player):
		if _player.grapple != null and _player.grapple.is_grappling:
			bonuses.append(BONUS_GRAPPLE)
		elif not _player.is_on_floor():
			# Excluyente con el gancho a proposito: colgado tambien se esta en el
			# aire, y cobrar los dos por la misma situacion paga dos veces lo
			# mismo.
			bonuses.append(BONUS_AIRBORNE)
		if now - _last_dash_time <= DASH_WINDOW:
			bonuses.append(BONUS_DASH)
		if absf(_spin_accum) >= SPIN_DEGREES:
			bonuses.append(BONUS_SPIN)
			# Se consume: la misma vuelta no paga dos kills.
			_spin_accum = 0.0

		var distance: float = _player.global_position.distance_to(position)
		if distance >= LONG_SHOT_DISTANCE:
			bonuses.append(BONUS_LONG_SHOT)
		elif distance <= POINT_BLANK_DISTANCE:
			bonuses.append(BONUS_POINT_BLANK)

		var weapon: WeaponComponent = _player.weapon
		if weapon != null and weapon.get_ammo() <= 0:
			bonuses.append(BONUS_LAST_ROUND)

	var streak_bonus: StringName = _advance_streak(now)
	if streak_bonus != &"":
		bonuses.append(streak_bonus)
	return bonuses


## Mueve la racha y devuelve el bono que le toca a esta kill, o vacio.
##
## Paga por escalon y no acumulado: la segunda kill cobra DOBLE, la tercera
## TRIPLE y la cuarta en adelante MAYHEM. Sumar los tres en una racha de cuatro
## pagaria el doble por la misma racha.
func _advance_streak(now: float) -> StringName:
	if now - _last_kill_time > MULTI_WINDOW:
		_streak = 0
	_last_kill_time = now
	_streak += 1
	match _streak:
		2: return BONUS_DOUBLE
		3: return BONUS_TRIPLE
	if _streak >= MAYHEM_KILLS:
		return BONUS_MAYHEM
	return &""


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
