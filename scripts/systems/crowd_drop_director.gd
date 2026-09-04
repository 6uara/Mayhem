class_name CrowdDropDirector
extends Node
## Decide cuando el publico tira un gadget a la arena, y cual.
##
## Existe por la misma razon que `HostDirector`: el timer y la eleccion son
## decisiones sobre el ritmo de la partida, y no tienen por que vivir dentro del
## objeto que vuela. `CrowdDropPickup` sabe caer y sabe levantarse; de cuando y
## desde donde no sabe nada, y asi el dia que el publico tire por otra razon -una
## racha de muertes, un round perdido- se cambia aca y en ningun otro lado.
##
## Solo tira durante una oleada. Entre oleadas no hay a quien entretener, y un
## gadget que aparece con la arena vacia se levanta sin costo - que es
## exactamente lo contrario de por que los gadgets salieron del shop.

## Donde cayo, para que el HUD o el Host puedan señalarlo.
signal drop_thrown(utility_id: StringName, landing: Vector3)

@export var table: CrowdDropTable
@export var drop_scene: PackedScene
## De donde saca el tamaño de la arena para no tirar nada fuera de ella.
@export var arena_host: ArenaHost

@export_group("Donde cae")
## Banda de distancia al jugador donde aterriza el gadget.
##
## No cae encima: un gadget gratis no cuesta posicion, y costar posicion es todo
## el motivo por el que dejo de comprarse. Tampoco cae del otro lado de la arena,
## porque a esa distancia nadie va a ir a buscarlo y el regalo se desperdicia.
@export var min_player_distance: float = 12.0
@export var max_player_distance: float = 26.0
## Metros de margen contra el borde de la arena, para que no quede pegado a la
## pared ni caiga en el foso.
@export var edge_margin: float = 3.0
## Cuanto tarda en llegar. Largo a proposito: el arco tiene que poder verse
## salir, seguirse y anticiparse, que es lo que le da al jugador la chance de
## estar ahi cuando toca el piso.
@export var flight_time: float = 2.2
## Altura minima desde la que se suelta, medida sobre el piso de la arena.
##
## Tiene que estar por encima del muro del perimetro, que es el cilindro
## invisible de 14 metros con el que el venue impide que el jugador se caiga al
## foso. El asiento esta afuera de ese muro y a un metro del suelo, asi que un
## tiro que sale del asiento se estrella contra la cara de afuera y el gadget
## queda colgado donde nadie lo puede levantar - es exactamente lo que pasaba.
##
## Lo que se levanta es la altura, no el lugar: el gadget sigue saliendo de las
## coordenadas del asiento, por encima de la cabeza de quien lo tiro. Un brazo
## que arroja algo por encima de una barrera de dos pisos es lo que se ve, y es
## lo que de verdad tendria que pasar.
@export var launch_height: float = 18.0

var _seconds_left: float = 0.0
var _is_running: bool = false
var _rng := RandomNumberGenerator.new()
var _crowd: CrowdStands


func _ready() -> void:
	_rng.randomize()
	EventBus.wave_started.connect(_on_wave_started.unbind(2))
	EventBus.wave_completed.connect(_on_wave_completed.unbind(3))
	EventBus.player_died.connect(_on_wave_completed)


func _process(delta: float) -> void:
	if not _is_running:
		return
	_seconds_left -= delta
	if _seconds_left > 0.0:
		return
	throw_now()
	_seconds_left = _roll_interval()


# Public API

## Tira uno ahora mismo, si hay a quien tirarselo y desde donde. Publica para que
## la consola y los tests puedan pedirlo sin esperar al reloj.
##
## Devuelve el pickup lanzado, o `null` cuando no habia nada para tirar - que no
## es un error: el jugador con los tres slots llenos es el caso normal de que el
## publico se guarde el regalo.
func throw_now() -> CrowdDropPickup:
	if drop_scene == null or table == null:
		return null
	var player := Players.local() as Player
	if player == null or player.utility == null:
		return null
	var data: UtilityData = table.pick(_rng, _has_room_for.bind(player))
	if data == null:
		return null
	var seat: Vector3 = _pick_origin(player)
	var landing: Vector3 = _pick_landing(player)

	var pickup := ObjectPool.acquire(drop_scene) as CrowdDropPickup
	if pickup == null:
		push_error("CrowdDropDirector: drop_scene is not a CrowdDropPickup")
		return null
	pickup.throw_from_stands(seat, CrowdDropPickup.arc_to(seat, landing, flight_time), data)
	drop_thrown.emit(data.id, landing)
	EventBus.crowd_drop_thrown.emit(data.id, landing)
	return pickup


func is_running() -> bool:
	return _is_running


func get_seconds_left() -> float:
	return _seconds_left


# Private

func _on_wave_started() -> void:
	_is_running = true
	# La primera espera de la oleada es mas larga que las siguientes: el publico
	# mira un rato antes de meterse, y el arranque de cada oleada se juega sin
	# regalos.
	_seconds_left = table.opening_delay if table != null else 12.0


func _on_wave_completed() -> void:
	_is_running = false
	_seconds_left = 0.0


func _has_room_for(data: UtilityData, player: Player) -> bool:
	var slot: int = player.utility.find_slot(data.id)
	if slot < 0:
		return false  # El jugador no lleva este gadget; no hay slot donde ponerlo.
	return player.utility.get_carried(slot) < data.max_carried


## El asiento del que sale. Sin tribuna en la escena -una arena de test, un
## shell sin publico- sale de arriba y a un costado del jugador: el drop tiene
## que seguir funcionando aunque el decorado no este.
func _pick_origin(player: Player) -> Vector3:
	if _crowd == null or not is_instance_valid(_crowd):
		_crowd = get_tree().get_first_node_in_group(&"crowd") as CrowdStands
	var seat: Vector3
	if _crowd != null and _crowd.has_seats():
		seat = _crowd.pick_seat()
	else:
		var angle: float = _rng.randf() * TAU
		seat = player.global_position + Vector3(cos(angle) * 24.0, 0.0, sin(angle) * 24.0)
	# Por encima del muro del perimetro. Ver `launch_height`.
	var floor_y: float = _arena_bounds().position.y
	seat.y = maxf(seat.y, floor_y + launch_height)
	return seat


## Un punto en la banda de distancia alrededor del jugador, recortado contra la
## arena. Se prueban varios angulos porque contra una esquina la mayoria de las
## direcciones se sale del mapa, y recortar sin mas amontonaria todos los drops
## en la misma pared.
func _pick_landing(player: Player) -> Vector3:
	var bounds: AABB = _arena_bounds()
	var origin: Vector3 = player.global_position
	var start: float = _rng.randf() * TAU
	for attempt: int in 8:
		var angle: float = start + TAU * float(attempt) / 8.0
		var distance: float = _rng.randf_range(min_player_distance, max_player_distance)
		var candidate: Vector3 = origin \
			+ Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		if _is_inside(candidate, bounds):
			candidate.y = bounds.position.y
			return candidate
	# Ningun angulo entro: la arena es mas chica que la banda de distancia. Cae en
	# el centro, que siempre esta adentro.
	var centre: Vector3 = bounds.position + bounds.size * 0.5
	return Vector3(centre.x, bounds.position.y, centre.z)


func _is_inside(point: Vector3, bounds: AABB) -> bool:
	return point.x > bounds.position.x + edge_margin \
		and point.x < bounds.position.x + bounds.size.x - edge_margin \
		and point.z > bounds.position.z + edge_margin \
		and point.z < bounds.position.z + bounds.size.z - edge_margin


func _arena_bounds() -> AABB:
	if arena_host != null and arena_host.runtime != null:
		return arena_host.runtime.get_content_bounds()
	# Sin arena cargada -tests, o un shell suelto- una caja grande centrada en el
	# origen, que no recorta nada. El drop cae igual; lo unico que se pierde es la
	# garantia de que no cayo afuera.
	return AABB(Vector3(-200.0, 0.0, -200.0), Vector3(400.0, 1.0, 400.0))


func _roll_interval() -> float:
	if table == null:
		return 20.0
	return table.roll_interval(maxi(WaveManager.current_index, 0), _rng)
