extends Node
## Lo que paso en esta run, y los trofeos que eso se gano.
##
## Existe porque la tabla guardaba tres numeros -puntaje, tiempo, oleadas- y
## esos tres no distinguen una run de otra: dos filas con 4200 puntos pueden ser
## una partida impecable y una carnicería con media vida perdida, y la tabla las
## muestra igual. Los trofeos son lo que hace que una fila cuente **como** fue,
## no solo cuanto.
##
## Se guardan junto a la run y no en un perfil aparte, a proposito: MAYHEM no
## tiene meta-progresion - nada se desbloquea, nada se acumula entre partidas- y
## un archivo de logros global seria exactamente eso. Un trofeo aca es la marca
## de **esa** run, y se va con ella cuando la fila cae de la tabla.
##
## No mide nada por su cuenta: todo lo que sabe llega por señal, del mismo
## EventBus que ya usan la economia y el Host.

## Los ids que se escriben en el archivo de la tabla. StringName y estables: una
## run vieja guardada con un id que despues se renombra tiene que seguir
## mostrando algo.
const FLAWLESS: StringName = &"flawless"
const UNTOUCHABLE: StringName = &"untouchable"
const CHAMPION: StringName = &"champion"
const MARKSMAN: StringName = &"marksman"
const ACROBAT: StringName = &"acrobat"
const SPINNER: StringName = &"spinner"
const EXECUTIONER: StringName = &"executioner"
const SURGEON: StringName = &"surgeon"
const SNIPER: StringName = &"sniper"
const TYCOON: StringName = &"tycoon"
const ASCETIC: StringName = &"ascetic"
const BLITZ: StringName = &"blitz"

## Como se llama cada trofeo y que hay que hacer para ganarlo. El texto vive con
## la regla, no en la pantalla que lo muestra: un trofeo que se retoca tiene que
## retocar tambien lo que dice de si mismo.
const TROPHY_INFO: Dictionary = {
	FLAWLESS: ["INTOCABLE", "Toda la run sin recibir un solo golpe"],
	UNTOUCHABLE: ["IMPECABLE", "Cinco oleadas limpias"],
	CHAMPION: ["CAMPEON", "Las diez oleadas"],
	MARKSMAN: ["TIRADOR", "Cuatro de cada diez kills a la cabeza"],
	ACROBAT: ["ACROBATA", "Diez kills sin tocar el piso"],
	SPINNER: ["TROMPO", "Tres kills girando"],
	EXECUTIONER: ["VERDUGO", "Cuatro kills en un segundo y medio"],
	SURGEON: ["CIRUJANO", "Cinco Healers cortados mientras curaban"],
	SNIPER: ["FRANCOTIRADOR", "Diez kills a mas de treinta metros"],
	TYCOON: ["MAGNATE", "Tres mil monedas en una run"],
	ASCETIC: ["ASCETA", "Ganar sin comprar nada"],
	BLITZ: ["RELAMPAGO", "Ganar en menos de ocho minutos"],
}

## Umbrales. Aca arriba y no enterrados en los `if` de abajo, por el mismo
## motivo que los pagos de los bonos viven en EconomyConfig: el que balancea
## tiene que poder leerlos todos juntos.
const UNTOUCHABLE_WAVES: int = 5
const MARKSMAN_RATIO: float = 0.4
## Debajo de esto la proporcion de headshots no significa nada: tres de cinco es
## puntería de nadie.
const MARKSMAN_MIN_KILLS: int = 30
const ACROBAT_KILLS: int = 10
const SPINNER_KILLS: int = 3
const SURGEON_KILLS: int = 5
const SNIPER_KILLS: int = 10
const TYCOON_EARNINGS: int = 3000
const BLITZ_SECONDS: float = 480.0

var kills: int = 0
var headshots: int = 0
var damage_taken: float = 0.0
var hits_taken: int = 0
var flawless_waves: int = 0
var purchases: int = 0
## Todo lo que entro a la billetera, recompensas y recargos. No es la plata que
## quedo: gastarla en la tienda es lo que hay que hacer con ella.
var earned: int = 0
## Cuantas veces se cumplio cada bono de kill, por id.
var bonus_counts: Dictionary = {}

## Las tres partes del puntaje. Ver `EconomyConfig` grupo Score: todo lo que
## suma se gano jugando, y morir solo deja de sumar.
## En que arena se juega. No lo borra `reset()`: lo pone ArenaHost al cargar la
## arena, antes de que el director arranque la run y resetee lo demas.
var arena_id: String = ""
var arena_name: String = ""

var kill_points: int = 0
var style_points: int = 0
var wave_points: int = 0

## Los trofeos de la run terminada. Vacio mientras se juega.
var _trophies: Array[StringName] = []


func _ready() -> void:
	EventBus.kill_scored.connect(_on_kill_scored)
	EventBus.kill_payout.connect(_on_kill_payout)
	EventBus.kill_credited.connect(_on_kill_credited)
	EventBus.player_damaged.connect(_on_player_damaged.unbind(1))
	EventBus.wave_completed.connect(_on_wave_completed)
	EventBus.purchase_made.connect(_on_purchase_made.unbind(2))
	EventBus.run_finished.connect(_on_run_finished)


# Public API

## Nombre y descripcion de un trofeo, o el id crudo si no es uno conocido - una
## run guardada por una version futura no puede romper la tabla de esta.
static func get_info(trophy_id: StringName) -> Array:
	return TROPHY_INFO.get(trophy_id, [String(trophy_id).to_upper(), ""])


static func get_label(trophy_id: StringName) -> String:
	return String(get_info(trophy_id)[0])


static func get_description(trophy_id: StringName) -> String:
	return String(get_info(trophy_id)[1])


## Los trofeos de la run que acaba de terminar, para que los guarde quien anota
## la fila. Vacio mientras se esta jugando: un trofeo se gana al final o no se
## gano.
func get_trophies() -> Array[StringName]:
	return _trophies.duplicate()


## Cuantas veces se cumplio un bono de kill en esta run.
func get_bonus_count(bonus_id: StringName) -> int:
	return int(bonus_counts.get(bonus_id, 0))


## Arranca una run nueva. Lo llama MatchDirector junto con los otros resets, en
## vez de adivinarlo desde una señal: "empezo una partida" es una decision del
## director, no un efecto de que se haya abierto la primera oleada.
func reset() -> void:
	kills = 0
	headshots = 0
	damage_taken = 0.0
	hits_taken = 0
	flawless_waves = 0
	purchases = 0
	earned = 0
	bonus_counts.clear()
	kill_points = 0
	style_points = 0
	wave_points = 0
	_trophies.clear()


func set_arena(id: String, display_name: String) -> void:
	arena_id = id
	arena_name = display_name


## El puntaje de la run: kills + estilo + oleadas, mas el premio por ganarla.
##
## No depende del tiempo total ni de la plata en mano. Las dos cosas estaban en
## la formula vieja y las dos premiaban lo contrario de lo que el juego pide:
## morir temprano dejaba casi entero el bono de tiempo, y comprar bajaba el
## puntaje.
func get_score(victory: bool = false) -> int:
	var total: int = kill_points + style_points + wave_points
	if victory:
		total += _config().score_victory_bonus
	return total


## Los trofeos que la run terminada se gano, evaluados de una sola vez.
##
## Publico y sin estado propio para que se pueda probar con numeros puestos a
## mano, sin jugar una partida entera.
func evaluate(total_time: float, victory: bool) -> Array[StringName]:
	var won: Array[StringName] = []

	if victory:
		won.append(CHAMPION)
		if purchases == 0:
			won.append(ASCETIC)
		if total_time <= BLITZ_SECONDS:
			won.append(BLITZ)
	# Terminar sin un rasguño y terminar con varias oleadas limpias son dos
	# cosas distintas, y la segunda no deja de valer porque pase la primera:
	# quien no recibio un solo golpe limpio todas las oleadas que jugo.
	if hits_taken == 0 and kills > 0:
		won.append(FLAWLESS)
	if flawless_waves >= UNTOUCHABLE_WAVES:
		won.append(UNTOUCHABLE)
	if kills >= MARKSMAN_MIN_KILLS and float(headshots) / float(kills) >= MARKSMAN_RATIO:
		won.append(MARKSMAN)
	if get_bonus_count(KillBonusTracker.BONUS_AIRBORNE) >= ACROBAT_KILLS:
		won.append(ACROBAT)
	if get_bonus_count(KillBonusTracker.BONUS_SPIN) >= SPINNER_KILLS:
		won.append(SPINNER)
	if get_bonus_count(KillBonusTracker.BONUS_MAYHEM) > 0:
		won.append(EXECUTIONER)
	if get_bonus_count(KillBonusTracker.BONUS_PRIORITY) >= SURGEON_KILLS:
		won.append(SURGEON)
	if get_bonus_count(KillBonusTracker.BONUS_LONG_SHOT) >= SNIPER_KILLS:
		won.append(SNIPER)
	if earned >= TYCOON_EARNINGS:
		won.append(TYCOON)
	return won


# Private

func _on_kill_scored(_enemy_type: StringName, _position: Vector3, was_headshot: bool,
		_reward: int) -> void:
	kills += 1
	if was_headshot:
		headshots += 1


func _on_kill_payout(_reward: int, bonus_ids: Array, bonus_total: int,
		_position: Vector3) -> void:
	earned += bonus_total
	# El estilo puntua con el mismo multiplicador que paga en plata: el rating
	# de la transmision y las mejoras que lo tocan. Ver EconomyManager.
	style_points += int(round(float(bonus_total * _config().score_per_style)
		* EconomyManager.get_style_multiplier()))
	for id: StringName in bonus_ids:
		bonus_counts[id] = int(bonus_counts.get(id, 0)) + 1


func _on_kill_credited(reward: int) -> void:
	earned += reward
	kill_points += reward * _config().score_per_kill_reward


## El contador de golpes va aparte del de daño porque las preguntas son
## distintas: INTOCABLE pregunta cuantas veces te tocaron, no cuanto dolio.
func _on_player_damaged(amount: float) -> void:
	damage_taken += amount
	hits_taken += 1


func _on_wave_completed(wave_index: int, _duration: float, wave_damage: float) -> void:
	wave_points += _config().score_per_wave * (wave_index + 1)
	if wave_damage <= 0.0:
		flawless_waves += 1


func _on_purchase_made() -> void:
	purchases += 1


func _on_run_finished(_score: int, total_time: float, _waves_cleared: int,
		victory: bool) -> void:
	_trophies = evaluate(total_time, victory)


func _config() -> EconomyConfig:
	return EconomyManager.config if EconomyManager.config != null else EconomyConfig.new()
