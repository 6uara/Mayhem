class_name CrowdDropPickup
extends ThrownUtility
## El gadget que alguien del publico tira a la arena, en el aire y despues en el
## piso.
##
## Es la unica fuente de utilidades del juego: los gadgets salieron del shop
## justamente para que conseguirlos cueste posicion y no plata. Por eso el objeto
## tiene que verse desde lejos y verse *distinto* segun cual sea - el jugador
## decide si vale la pena cruzar la arena antes de llegar, no cuando llega.
##
## Vuela con la matematica de `ThrownUtility` (arco escalonado, no RigidBody3D) y
## al tocar el piso se queda quieto en vez de detonar: `_activate()`, que en los
## tres gadgets del jugador es "explota", aca es "quedate ahi hasta que alguien
## te levante". Es el mismo punto de extension, con el otro final.
##
## En el piso copia la gramatica de `AmmoPickup` -ambar, gira, flota, brilla,
## suena antes de verse- porque es la misma clase de cosa y el jugador ya
## aprendio a leerla.

signal collected(utility_id: StringName)
## Nadie lo levanto a tiempo. El director escucha esto para saber cuantos
## regalos se estan desperdiciando.
signal expired(utility_id: StringName)

@export_group("Pickup")
## Segundos en el piso antes de desaparecer. Sin esto la arena termina sembrada
## de gadgets viejos y el recurso deja de ser algo que hay que administrar.
@export var despawn_time: float = 22.0
## Cuanto antes del final empieza a parpadear. Un objeto que desaparece sin
## avisar se lee como un bug, no como una regla.
@export var blink_lead: float = 5.0
@export var pickup_sound: AudioStream
@export var idle_sound: AudioStream
## Hasta donde se escucha el zumbido. Igual que la municion: primero se oye,
## despues se ve.
@export var idle_audible_range: float = 30.0

@export_group("Nodos")
@export var hitbox: Area3D
## El nucleo, teñido con el `accent_color` del gadget: es lo que dice cual es.
@export var core: MeshInstance3D
## El halo, siempre ambar: es lo que dice que es de la casa y se puede levantar.
@export var halo: MeshInstance3D
@export var light: OmniLight3D

var is_available: bool = false

var _life_left: float = 0.0
var _bob_time: float = 0.0
var _rest_height: float = 0.0
var _idle_player: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group(&"crowd_drop")
	if core != null:
		_rest_height = core.position.y
	if hitbox != null:
		hitbox.body_entered.connect(_on_body_entered)
	_build_idle_player()
	_set_available(false)
	_show_body(false)


func _process(delta: float) -> void:
	# Girar lo hace tambien en el aire: es lo que lo vuelve seguible mientras cae,
	# que es la mitad del punto de tirarlo desde la tribuna. Lo que solo pasa en
	# el piso es flotar, parpadear y morirse.
	if core != null and core.visible:
		core.rotate_y(delta * 1.6)
	if not is_available:
		return

	_life_left -= delta
	if _life_left <= 0.0:
		_expire()
		return
	if _life_left < blink_lead:
		# Parpadeo cada vez mas rapido: la urgencia tiene que subir sola, no
		# aparecer de golpe en el ultimo segundo.
		var urgency: float = 1.0 - _life_left / maxf(blink_lead, 0.01)
		var on: bool = fmod(_life_left * (4.0 + urgency * 10.0), 1.0) > 0.35
		if core != null:
			core.visible = on
		if light != null:
			light.visible = on

	_bob_time += delta
	if core != null:
		core.position.y = _rest_height + sin(_bob_time * 2.2) * 0.12


# Public API

## Lo tira alguien de la tribuna. `from` es su asiento, `velocity` el arco ya
## resuelto: quien tira sabe adonde quiere que caiga, este objeto no.
func throw_from_stands(from: Vector3, velocity: Vector3, utility: UtilityData) -> void:
	data = utility
	_apply_accent()
	_show_body(true)
	launch_with_velocity(from, velocity, null)


## Toca el piso y se queda. `ThrownUtility` ya dejo el objeto apoyado sobre la
## superficie que golpeo y ya sono el impacto, asi que aca solo se enciende el
## pickup.
func _activate() -> void:
	# `ThrownUtility` tambien llama aca cuando se le acaba el tiempo de vuelo sin
	# haber tocado nada - la red de seguridad para algo tirado fuera del mapa. Un
	# gadget que se queda flotando en el aire porque nunca encontro piso no es un
	# pickup, es un bug con luz propia.
	if _flight_time >= MAX_FLIGHT_TIME:
		ObjectPool.release(self)
		return
	_set_available(true)


## Levantarlo es sumar una carga al slot que le corresponde, exactamente como lo
## hacia el shop. Que el gadget venga de la tribuna no cambia lo que es.
func collect(player: Player) -> bool:
	if not is_available or data == null:
		return false
	if player == null or player.utility == null:
		return false
	# Se pregunta antes de tomarlo: pasar por encima con el slot lleno tiene que
	# dejar el gadget donde esta, para cuando de verdad haga falta. Es la misma
	# regla que la caja de municion.
	if not player.utility.add_charge(data.id):
		return false
	AudioPool.play_3d(pickup_sound, global_position, AudioPool.BUS_WORLD)
	collected.emit(data.id)
	_set_available(false)
	ObjectPool.release(self)
	return true


func get_time_left() -> float:
	return _life_left


## La velocidad que lleva algo de `from` a `to` en `flight` segundos, bajo la
## misma gravedad con la que vuelan estos objetos.
##
## Vive aca y no en quien tira porque la gravedad tambien vive aca: un director
## que resolviera el arco con su propio numero dejaria los gadgets cayendo cortos
## sin que nada lo explique. Quien tira elige adonde y en cuanto tiempo; con que
## velocidad se llega es cuenta del objeto.
static func arc_to(from: Vector3, to: Vector3, flight: float) -> Vector3:
	var seconds: float = maxf(flight, 0.1)
	return (to - from) / seconds + Vector3.UP * (0.5 * get_gravity() * seconds)


# Private

func _on_body_entered(body: Node3D) -> void:
	# Tambien agarra en el aire, y esta bien que agarre: correr abajo de algo que
	# cae y llegar es exactamente el pilar de movilidad. Lo que no puede pasar es
	# que se cobre solo por pasar cerca mientras todavia vuela, y de eso se
	# encarga `is_available`, que recien se enciende al aterrizar.
	if not is_available or not body.is_in_group(&"player"):
		return
	collect(body as Player)


func _expire() -> void:
	_set_available(false)
	if data != null:
		expired.emit(data.id)
	ObjectPool.release(self)


func _set_available(available: bool) -> void:
	is_available = available
	_life_left = despawn_time if available else 0.0
	_bob_time = 0.0
	if hitbox != null:
		# Diferido porque `collect()` se llama desde `body_entered`, y el servidor
		# de fisica no deja tocar el monitoring de un area mientras esta
		# despachando sus propias señales.
		hitbox.set_deferred(&"monitoring", available)
	if core != null:
		core.position.y = _rest_height
	# El halo es lo unico que se enciende al aterrizar: mientras vuela el objeto
	# se ve -tiene que verse, para poder correr adonde va a caer- pero todavia no
	# se puede levantar, y el anillo es lo que marca esa diferencia.
	if halo != null:
		halo.visible = available
	if _idle_player != null and is_instance_valid(_idle_player):
		if available:
			_idle_player.play()
		else:
			_idle_player.stop()


## Tiñe el nucleo con el color del gadget. El halo no se toca: ese es ambar
## siempre, porque lo que dice es "esto se levanta", y eso no cambia con el
## contenido.
func _apply_accent() -> void:
	if core == null or data == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = data.accent_color
	material.emission_enabled = true
	material.emission = data.accent_color
	material.emission_energy_multiplier = 1.6
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.material_override = material
	if light != null:
		light.light_color = data.accent_color


## Un reproductor propio en loop y no una voz del pool: el zumbido tiene que
## durar todo lo que dure el objeto, y el pool es para one-shots.
## Prende o apaga el objeto entero. Distinto de `_set_available()`: esto es "se
## ve", aquello es "se puede levantar", y entre el lanzamiento y el aterrizaje
## las dos cosas no coinciden.
func _show_body(visible_now: bool) -> void:
	if core != null:
		core.visible = visible_now
	if light != null:
		light.visible = visible_now


func _build_idle_player() -> void:
	if idle_sound == null:
		return
	_idle_player = AudioStreamPlayer3D.new()
	_idle_player.stream = idle_sound
	_idle_player.bus = String(AudioPool.BUS_WORLD)
	_idle_player.max_distance = idle_audible_range
	_idle_player.unit_size = 8.0
	_idle_player.volume_db = -7.0
	add_child(_idle_player)
	_idle_player.finished.connect(func() -> void:
		if is_available:
			_idle_player.play())


func _on_acquired() -> void:
	super()
	is_available = false


func _on_released() -> void:
	super()
	_set_available(false)
	_show_body(false)
	data = null
	if core != null:
		core.material_override = null
