class_name CrowdMoodDirector
extends Node
## Cuando el publico se levanta, hace la ola y prende los celulares.
##
## Vive al lado de `HostDirector` y `CrowdDropDirector` por la misma razon que
## ellos: `CrowdStands` sabe dibujar diez mil espectadores y no sabe nada de la
## partida, y lo que decide si la tribuna esta encendida o muerta es lo que pasa
## en la arena. Con esto separado, cambiar cuando se levanta el publico no toca
## una linea de lo que lo dibuja.
##
## El publico no aplaude cada muerte. Se calienta con el ritmo -muchas muertes
## seguidas- y se enfria solo cuando no pasa nada, que es lo que hace que una
## racha se sienta como una racha en vez de como una barra que sube.

## Cuanto sube el entusiasmo por cada muerte.
@export var kill_heat: float = 0.22
## Cuanto se enfria por segundo cuando no pasa nada. Alto a proposito: un publico
## que se queda encendido deja de reaccionar a nada.
@export var cool_per_second: float = 0.16
## A partir de aca la tribuna esta lo bastante caliente como para arrancar una
## ola sola.
@export_range(0.0, 1.0) var wave_threshold: float = 0.75
## Cuanto tarda la ola en dar la vuelta al estadio.
@export var wave_duration: float = 3.2
## Guarda entre una ola y la siguiente. Sin esto una racha larga deja la tribuna
## haciendo la ola sin parar y el gesto pierde todo su peso.
@export var wave_cooldown: float = 14.0

@export_group("Celulares")
## Cuantos filman entre oleadas, cuando no hay nada mejor que hacer.
@export_range(0.0, 1.0) var idle_phone_share: float = 0.22
## Y cuantos durante la pelea. Menos: la gente mira.
@export_range(0.0, 1.0) var fighting_phone_share: float = 0.06

var _excitement: float = 0.0
var _wave_time: float = -1.0
var _wave_cooldown_left: float = 0.0
var _crowd: CrowdStands


func _ready() -> void:
	EventBus.enemy_killed.connect(_on_enemy_killed.unbind(3))
	EventBus.wave_started.connect(_on_wave_started.unbind(2))
	EventBus.wave_completed.connect(_on_wave_completed.unbind(3))
	EventBus.player_died.connect(_on_player_died)
	EventBus.crowd_drop_thrown.connect(_on_crowd_drop_thrown.unbind(2))


func _process(delta: float) -> void:
	var crowd: CrowdStands = _get_crowd()
	if crowd == null:
		return

	_excitement = maxf(_excitement - cool_per_second * delta, 0.0)
	crowd.set_excitement(_excitement)

	_wave_cooldown_left = maxf(_wave_cooldown_left - delta, 0.0)
	if _excitement >= wave_threshold and _wave_time < 0.0 and is_zero_approx(_wave_cooldown_left):
		start_wave()

	if _wave_time >= 0.0:
		_wave_time += delta / maxf(wave_duration, 0.01)
		if _wave_time > 1.0:
			_end_wave()
		else:
			crowd.set_wave_position(_wave_time)


# Public API

## Manda una ola desde donde arranque el recorrido. Publica para que la consola
## y los tests puedan pedirla sin tener que fabricar una racha.
func start_wave() -> void:
	_wave_time = 0.0
	_wave_cooldown_left = wave_cooldown


func add_excitement(amount: float) -> void:
	_excitement = clampf(_excitement + amount, 0.0, 1.0)


func get_excitement() -> float:
	return _excitement


func is_waving() -> bool:
	return _wave_time >= 0.0


# Private

func _on_enemy_killed() -> void:
	add_excitement(kill_heat)


func _on_wave_started() -> void:
	var crowd: CrowdStands = _get_crowd()
	if crowd != null:
		crowd.set_phone_share(fighting_phone_share)


## Una oleada limpia se aplaude entera, sin importar como venia la cosa: es el
## unico momento del combate en que el resultado ya esta y el publico puede
## festejar en vez de mirar.
func _on_wave_completed() -> void:
	add_excitement(1.0)
	start_wave()
	var crowd: CrowdStands = _get_crowd()
	if crowd != null:
		crowd.set_phone_share(idle_phone_share)


## Y esto tambien se festeja, porque el publico no vino a verte ganar.
func _on_player_died() -> void:
	add_excitement(1.0)
	start_wave()


func _on_crowd_drop_thrown() -> void:
	# Quien tiro algo se para para tirarlo, y los de al lado miran. Es un empujon
	# chico: el regalo es del publico, no una hazaña del jugador.
	add_excitement(0.2)


func _end_wave() -> void:
	_wave_time = -1.0
	var crowd: CrowdStands = _get_crowd()
	if crowd != null:
		crowd.set_wave_position(-1.0)


func _get_crowd() -> CrowdStands:
	if _crowd == null or not is_instance_valid(_crowd):
		_crowd = get_tree().get_first_node_in_group(&"crowd") as CrowdStands
	return _crowd
