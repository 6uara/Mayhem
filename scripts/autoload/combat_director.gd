extends Node
## Coordina a la horda como un grupo: quien viene de frente, quien se abre, quien
## llega por atras, y quien puede pedirle trabajo al motor este frame.
##
## El problema que resuelve no es de un enemigo sino de todos juntos. Cada bicho
## ya sabia pelear -perseguir, kitear, flanquear, tirar frascos- pero lo decidia
## solo, con datos de su arquetipo y un carril al azar. Eso alcanza para seis
## enemigos y deja de alcanzar antes de los veinte: dos Rangers eligen el mismo
## angulo y se tapan, tres Bombers llegan por la misma espalda, los Environmental
## empapelan el mismo metro cuadrado, y la separacion -lo unico que los despegaba-
## cuesta N^2 justo cuando N crece.
##
## Aca viven las tres cosas que solo se pueden decidir mirando a todos:
##
## 1. **El puesto de cada uno.** El director reparte rumbos alrededor del jugador
##    por rol, sin repetir. `EnemyData.approach_bearing_degrees` deja de ser la
##    respuesta y pasa a ser la *banda* dentro de la que este rol pide su lugar
##    (ver `ROLE_BANDS` y `_reassign_bearings`).
## 2. **Quien se compromete.** Los ataques que telegrafian y bloquean -el salto,
##    el slam- salen por ficha. Sin techo, una oleada de treinta se lee como
##    ruido: todo pasa al mismo tiempo y nada se puede leer ni esquivar.
## 3. **El presupuesto por frame.** Vecinos y repaths se sirven de una grilla y de
##    un cupo, no de un recorrido completo por enemigo por frame.
##
## Es autoload y no un nodo del arena a proposito: los enemigos son pooleados y
## sobreviven al cambio de escena, asi que el registro tiene que vivir mas que
## cualquier arena. `reset()` lo vacia entre runs.

## Roles de combate. No son los arquetipos: el arquetipo dice **que** hace un
## enemigo, el rol dice **donde se para mientras lo hace**. Dos arquetipos
## distintos pueden querer el mismo puesto, y uno futuro consigue comportamiento
## de grupo eligiendo un rol en vez de tocar el director.
enum Role {
	## Cuerpo a cuerpo basico. Viene de frente y no disimula: es la presion que
	## obliga a moverse, y la que le da sentido a todo lo que llega por otro lado.
	BRAWLER,
	## Tiradores. Se abren a la periferia del frente y se separan entre si: la
	## pregunta que hacen es "no te podes quedar mirando a uno solo".
	SKIRMISHER,
	## Negacion de terreno. Tira predictivo, adelante del jugador, y se coordina
	## para no empapelar el mismo piso dos veces.
	ARTILLERY,
	## La sorpresa. Busca el punto ciego y llega por ahi.
	INFILTRATOR,
}

## Cada cuanto se reparten los puestos. Bajo a proposito: el reparto es una
## decision de composicion, no de direccion - la direccion la sigue resolviendo
## cada enemigo con su navegacion, frame a frame.
const REASSIGN_INTERVAL: float = 0.25
## Lado de la celda de la grilla de vecinos, en metros. Igual al radio de
## separacion: asi un enemigo mira su celda y las ocho de alrededor y tiene
## garantizado no perderse a nadie dentro del radio.
const CELL_SIZE: float = 2.0
## Hasta donde se sienten los vecinos para separarse.
const SEPARATION_RADIUS: float = 2.0
## Cada cuanto se rearma la grilla. Al ritmo al que se consulta -la separacion se
## recalcula cada 50ms- y no una vez por frame: rearmarla asigna un Array por
## celda ocupada, o sea decenas de arrays descartables por frame en una oleada
## llena, para responder lo mismo. En 50ms un enemigo se corre menos de medio
## metro, y la consulta ya mira una celda de margen a cada lado.
const GRID_INTERVAL: float = 0.05

## Banda angular de cada rol, en grados desde la mirada del jugador. 0 es de
## frente, 180 es la espalda. El director reparte adentro de la banda; el
## arquetipo elige el rol, no el numero.
##
## Las bandas casi no se pisan, y ese es todo el diseño: si el mismo angulo lo
## pueden pedir un Rusher y un Ranger, el jugador no puede aprender que significa
## cada silueta segun de donde viene.
const ROLE_BANDS: Dictionary = {
	# De frente, con algo de apertura para que un peloton no sea una fila.
	Role.BRAWLER: Vector2(0.0, 35.0),
	# Los costados del frente: visibles sin girar la cabeza, pero fuera del centro.
	Role.SKIRMISHER: Vector2(55.0, 115.0),
	# Entre el frente y el flanco: tiran a donde el jugador **va**, asi que
	# quedarse muy al costado seria tirarle a un camino que no va a tomar.
	Role.ARTILLERY: Vector2(35.0, 80.0),
	# El punto ciego. 180 es la espalda exacta; la banda la abre para que dos
	# bombas no lleguen por la misma linea.
	Role.INFILTRATOR: Vector2(145.0, 200.0),
}

## Cuantos enemigos de cada rol pueden estar comprometidos en un ataque
## telegrafiado al mismo tiempo. El techo es lo que hace que una oleada grande
## siga siendo legible: veinte Rushers saltando juntos no son mas dificiles, son
## menos leibles.
const ATTACK_TOKENS: Dictionary = {
	Role.BRAWLER: 3,
	Role.SKIRMISHER: 4,
	Role.ARTILLERY: 2,
	Role.INFILTRATOR: 2,
}

## Cuantos enemigos pueden pedirle un camino nuevo al navmesh en un mismo frame
## de fisica. Un repath es una consulta al NavigationServer y es la parte cara de
## `set_move_target`; con cuarenta enemigos a 5 repaths por segundo son 200
## consultas por segundo que se apilan en los mismos frames si nadie las reparte.
##
## No frena a nadie: el que no consigue turno reintenta al frame siguiente, o sea
## 16ms tarde, sobre un intervalo de 200ms.
const REPATH_BUDGET_PER_FRAME: int = 6

## Cuanto tienen que estar separados dos hazards para contar como distintos. Ver
## `claim_hazard`.
const HAZARD_MIN_SEPARATION: float = 4.0
## Cuanto dura una reserva de piso. La reserva no cubre la vida del charco -de eso
## ya se ocupa el tope de charcos vivos de `ActionThrowFlask`- sino la ventana en
## la que dos lanzadores podrian estar apuntando al mismo lugar sin saberlo: el
## vuelo del frasco mas un margen. Vence sola para que nadie tenga que acordarse
## de devolverla cuando el charco se apaga.
const HAZARD_CLAIM_TIME: float = 2.5

## Los enemigos vivos. Es la lista que la separacion recorria adentro de `Enemy`,
## traida aca porque la pregunta "quien esta cerca" es de todos y no de cada uno.
var _enemies: Array[Enemy] = []

# Snapshot del objetivo, una vez por frame en vez de una vez por enemigo.
var _target: Node3D
var _target_position: Vector3 = Vector3.ZERO
var _target_facing: Vector3 = Vector3.FORWARD
var _target_velocity: Vector3 = Vector3.ZERO

## instance_id -> grados con signo, el puesto que le toco a cada uno.
var _bearings: Dictionary = {}
## Celda (Vector2i) -> Array de enemigos, sin tipar: ver el bucle de separation_for().
var _grid: Dictionary = {}
## Role -> cuantas fichas de ataque estan en uso.
var _tokens: Dictionary = {}
## instance_id -> Role, para poder devolver la ficha sola si el que la tenia muere.
var _token_holders: Dictionary = {}
## Pedazos de piso reservados: cada entrada es {position, expiry}.
var _hazards: Array[Dictionary] = []

var _reassign_timer: float = 0.0
var _grid_timer: float = 0.0
var _repaths_left: int = REPATH_BUDGET_PER_FRAME


func _ready() -> void:
	# Antes que cualquier enemigo: todos leen el snapshot y la grilla de este frame.
	process_priority = -100
	EventBus.player_died.connect(reset)


func _physics_process(delta: float) -> void:
	_repaths_left = REPATH_BUDGET_PER_FRAME
	if _enemies.is_empty():
		return
	_prune()
	_expire_hazards()
	_refresh_target()
	_grid_timer -= delta
	if _grid_timer <= 0.0:
		_grid_timer = GRID_INTERVAL
		_rebuild_grid()
	_reassign_timer -= delta
	if _reassign_timer <= 0.0:
		_reassign_timer = REASSIGN_INTERVAL
		_reassign_bearings()


# API - registro

## Alta al spawnear. La hace `Enemy.setup()`.
func register(enemy: Enemy) -> void:
	if enemy == null or _enemies.has(enemy):
		return
	_enemies.append(enemy)


## Baja al volver al pool, al morir o al irse del arbol. Devuelve la ficha si la
## tenia: un enemigo que muere a mitad de un salto no puede quedarse con el cupo
## del resto de la oleada.
func unregister(enemy: Enemy) -> void:
	if enemy == null:
		return
	_enemies.erase(enemy)
	release_attack_token(enemy)
	_bearings.erase(enemy.get_instance_id())


## Los enemigos vivos, sin pasar por el arbol - `get_nodes_in_group()` arma un
## Array nuevo en cada llamada. Solo para leer.
func get_active_enemies() -> Array[Enemy]:
	return _enemies


## Vacia todo. Entre runs y entre arenas: un director que arrastra enemigos de la
## corrida anterior reparte puestos a fantasmas.
func reset() -> void:
	_enemies.clear()
	_bearings.clear()
	_grid.clear()
	_tokens.clear()
	_token_holders.clear()
	_hazards.clear()
	_target = null
	_reassign_timer = 0.0


# API - rol

## Que rol juega este arquetipo. Se deduce del dato, no se pregunta por nombre: un
## arquetipo nuevo hereda el puesto que le corresponde por como pelea, sin tocar
## esta funcion.
##
## El orden importa. La espoleta gana sobre todo lo demas -una bomba es una bomba
## aunque tambien sepa pegar- y despues manda el alcance: el que pelea de lejos se
## para lejos, el que pelea de cerca viene de frente.
static func role_of(data: EnemyData) -> Role:
	if data == null:
		return Role.BRAWLER
	if data.has_fuse:
		return Role.INFILTRATOR
	if data.archetype == EnemyData.Archetype.ENVIRONMENTAL:
		return Role.ARTILLERY
	if data.preferred_distance > 0.0:
		return Role.SKIRMISHER
	return Role.BRAWLER


# API - puestos

## El rumbo que le toca a este enemigo, en grados con signo desde la mirada del
## jugador. Es lo que `Enemy._bearing_position()` usa en lugar del numero fijo del
## arquetipo.
##
## Devuelve el valor del `.tres` mientras el director todavia no repartio -el
## primer frame de un spawn, o un test que corre sin director-, asi que un enemigo
## nunca se queda sin puesto.
func bearing_for(enemy: Enemy) -> float:
	if enemy == null:
		return 0.0
	var id: int = enemy.get_instance_id()
	if _bearings.has(id):
		return _bearings[id]
	return enemy.data.approach_bearing_degrees if enemy.data != null else 0.0


## Si el director ya le repartio puesto a este enemigo. Lo pregunta `Enemy`, que
## espeja el rumbo del `.tres` segun su carril pero no debe espejar un puesto
## repartido: ese ya viene con el lado elegido.
func has_bearing(enemy: Enemy) -> bool:
	return enemy != null and _bearings.has(enemy.get_instance_id())


# API - separacion y vecindad

## El empujon de los vecinos, resuelto contra la grilla en vez de contra la lista
## entera.
##
## Es el mismo calculo que vivia en `Enemy._compute_separation()`, con la unica
## diferencia que importa: antes cada enemigo recorria a los N enemigos, o sea N^2
## por ciclo. Con la grilla mira solo su celda y las ocho vecinas, que a densidad
## de horda son un puñado - y deja de importar cuantos hay del otro lado del arena.
func separation_for(enemy: Enemy) -> Vector3:
	var push := Vector3.ZERO
	var origin: Vector3 = enemy.global_position
	var base: Vector2i = _cell_of(origin)
	for dx: int in range(-1, 2):
		for dz: int in range(-1, 2):
			var bucket: Variant = _grid.get(base + Vector2i(dx, dz))
			if bucket == null:
				continue
			for entry: Variant in bucket:
				# Sin tipar: la grilla sobrevive unos frames (ver GRID_INTERVAL) y
				# puede tener a alguien que murio en el medio. Asignar una
				# instancia liberada a una variable tipada es un error del motor
				# **antes** de que la guarda corra - la misma trampa que
				# documenta Enemy.get_target().
				if not is_instance_valid(entry):
					continue
				var other := entry as Enemy
				if other == null or other == enemy or not other.is_active:
					continue
				var offset: Vector3 = origin - other.global_position
				offset.y = 0.0
				var distance: float = offset.length()
				if distance >= SEPARATION_RADIUS:
					continue
				if distance < 0.01:
					# Exactamente encimados: no hay direccion que sacar del
					# vector, asi que se desempata con algo estable por enemigo.
					var angle: float = float(enemy.get_instance_id() % 360) * TAU / 360.0
					push += Vector3(cos(angle), 0.0, sin(angle))
					continue
				push += offset / distance * (1.0 - distance / SEPARATION_RADIUS)
	return push


## Los enemigos dentro de `radius` de un punto, sin recorrer a todos. Publica
## porque el problema de "quien esta cerca" lo tienen tambien la explosion, el
## healer y cualquier cosa de area que venga despues.
func neighbors(point: Vector3, radius: float) -> Array[Enemy]:
	var found: Array[Enemy] = []
	var cells: int = int(ceil(radius / CELL_SIZE))
	var base: Vector2i = _cell_of(point)
	var radius_squared: float = radius * radius
	for dx: int in range(-cells, cells + 1):
		for dz: int in range(-cells, cells + 1):
			var bucket: Variant = _grid.get(base + Vector2i(dx, dz))
			if bucket == null:
				continue
			for entry: Variant in bucket:
				if not is_instance_valid(entry):
					continue
				var other := entry as Enemy
				if other == null or not other.is_active:
					continue
				if other.global_position.distance_squared_to(point) <= radius_squared:
					found.append(other)
	return found


# API - compromiso

## Pide permiso para un ataque que telegrafia y bloquea. `false` significa "este
## frame no": el enemigo sigue presionando desde su puesto y lo reintenta.
##
## Solo para los ataques que se **leen** - saltos, slams, cargas. El golpe basico
## no pide ficha, porque un cuerpo a cuerpo que espera turno estando ya encima del
## jugador se lee como un bug y no como una coreografia.
func request_attack_token(enemy: Enemy) -> bool:
	if enemy == null:
		return true
	var id: int = enemy.get_instance_id()
	if _token_holders.has(id):
		return true  # Ya la tiene; pedirla de nuevo no gasta dos.
	var role: Role = role_of(enemy.data)
	var used: int = _tokens.get(role, 0)
	if used >= int(ATTACK_TOKENS.get(role, 1)):
		return false
	_tokens[role] = used + 1
	_token_holders[id] = role
	return true


## Si este enemigo tiene la ficha ahora mismo.
func holds_attack_token(enemy: Enemy) -> bool:
	return enemy != null and _token_holders.has(enemy.get_instance_id())


## Devuelve la ficha. Idempotente a proposito: la sueltan tanto el final del
## ataque como la muerte, y las dos cosas pueden pasar en ese orden.
func release_attack_token(enemy: Enemy) -> void:
	if enemy == null:
		return
	var id: int = enemy.get_instance_id()
	if not _token_holders.has(id):
		return
	var role: Role = _token_holders[id]
	_token_holders.erase(id)
	_tokens[role] = maxi(int(_tokens.get(role, 1)) - 1, 0)


# API - presupuesto

## Turno para pedirle un camino nuevo al navmesh este frame. El que no lo consigue
## reintenta al siguiente. Ver `REPATH_BUDGET_PER_FRAME`.
func request_repath() -> bool:
	if _repaths_left <= 0:
		return false
	_repaths_left -= 1
	return true


# API - predictivo y terreno

## Donde va a estar el jugador dentro de `lead_time` segundos, aplanado.
##
## Vive aca y no en cada hoja porque es la misma cuenta para todos los que
## anticipan, y porque tenerla en un solo lugar es lo que permite que dos
## Environmental no la resuelvan con datos de frames distintos y terminen
## apuntando al mismo metro por casualidad.
func predicted_position(lead_time: float, lead_fraction: float = 1.0) -> Vector3:
	var lead: Vector3 = _target_velocity * lead_time * clampf(lead_fraction, 0.0, 1.0)
	lead.y = 0.0
	return _target_position + lead


## Reserva un pedazo de piso para un hazard. `false` si ya hay uno reclamado
## demasiado cerca: dos charcos encimados niegan el mismo terreno dos veces y
## cuestan el doble, que es la definicion de presion que no se lee.
func claim_hazard(point: Vector3) -> bool:
	for claim: Dictionary in _hazards:
		var at: Vector3 = claim["position"]
		if Vector2(at.x - point.x, at.z - point.z).length() < HAZARD_MIN_SEPARATION:
			return false
	_hazards.append({"position": point, "expiry": _now() + HAZARD_CLAIM_TIME})
	return true


# API - snapshot

## Si el director ya sabe contra quien pelea la horda. Lo preguntan los que tienen
## una cuenta propia de respaldo -la prediccion del Environmental- para no usar un
## snapshot vacio: sin director corriendo, `get_target_position()` es el origen del
## arena, y apuntar ahi es peor que no haber preguntado.
func has_target() -> bool:
	return _target != null


func get_target() -> Node3D:
	return _target


func get_target_position() -> Vector3:
	return _target_position


func get_target_facing() -> Vector3:
	return _target_facing


func get_target_velocity() -> Vector3:
	return _target_velocity


# Private

## Saca los liberados y los que volvieron al pool sin avisar. Un objeto liberado
## compara **igual** a null, asi que la guarda tiene que ser `is_instance_valid`.
func _prune() -> void:
	var alive: Array[Enemy] = []
	for i: int in _enemies.size():
		# Sin tipar la variable del bucle, y ese es todo el punto: asignar una
		# instancia ya liberada a una variable tipada es un error del motor antes
		# de que la guarda llegue a correr, asi que la validez no se puede
		# preguntar del otro lado de la asignacion. Es la misma trampa que
		# Enemy.get_target() documenta.
		var entry: Variant = _enemies[i]
		if not is_instance_valid(entry):
			continue
		var enemy := entry as Enemy
		if enemy != null and enemy.is_active:
			alive.append(enemy)
	if alive.size() != _enemies.size():
		_enemies = alive


func _refresh_target() -> void:
	if not is_instance_valid(_target):
		_target = null
	if _target == null:
		# El objetivo del primer enemigo vivo alcanza: hoy toda la horda pelea
		# contra el mismo. Cuando existan facciones que se peleen entre si, el
		# reparto pasa a ser por objetivo y esto se vuelve un diccionario.
		for enemy: Enemy in _enemies:
			var candidate: Node3D = enemy.get_target()
			if candidate != null:
				_target = candidate
				break
	if _target == null:
		return
	_target_position = _target.global_position
	# Godot mira hacia -Z.
	var forward: Vector3 = -_target.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.001:
		_target_facing = forward.normalized()
	var body := _target as CharacterBody3D
	_target_velocity = body.velocity if body != null else Vector3.ZERO


func _expire_hazards() -> void:
	var now: float = _now()
	var live: Array[Dictionary] = []
	for claim: Dictionary in _hazards:
		if float(claim["expiry"]) > now:
			live.append(claim)
	if live.size() != _hazards.size():
		_hazards = live


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _cell_of(point: Vector3) -> Vector2i:
	return Vector2i(int(floor(point.x / CELL_SIZE)), int(floor(point.z / CELL_SIZE)))


func _rebuild_grid() -> void:
	# Se limpia y se rellena en vez de mantenerse incremental: los enemigos se
	# mueven todos los frames, asi que mover entradas entre celdas costaria lo
	# mismo que rehacerla, y ademas habria que acordarse de sacarlas al morir.
	_grid.clear()
	for enemy: Enemy in _enemies:
		var cell: Vector2i = _cell_of(enemy.global_position)
		if not _grid.has(cell):
			_grid[cell] = []
		_grid[cell].append(enemy)


## Reparte los rumbos: por rol, en abanico dentro de la banda del rol, de a uno
## por puesto.
##
## El criterio de a quien le toca cual es "el que ya esta mas cerca de ese
## angulo". Ordenar a los enemigos y a los puestos por angulo y aparearlos en
## orden da esa asignacion sin buscarla: es la solucion de costo minimo cuando los
## dos conjuntos viven sobre el mismo circulo, y sale en un `sort` en vez de en
## una matriz de N x N. Que sea estable importa tanto como que sea barata -
## reasignar al azar cada 250ms haria que el grupo entero se cruce en el aire.
func _reassign_bearings() -> void:
	if _target == null:
		return
	var by_role: Dictionary = {}
	for enemy: Enemy in _enemies:
		if enemy.data == null or enemy.data.approach_bearing_weight <= 0.0:
			# El que no pide rumbo no ocupa puesto: viene de frente y se separa
			# con el carril lateral, como antes de que esto existiera.
			continue
		var role: Role = role_of(enemy.data)
		if not by_role.has(role):
			by_role[role] = [] as Array[Enemy]
		by_role[role].append(enemy)

	for role: Role in by_role:
		var members: Array[Enemy] = by_role[role]
		var slots: Array[float] = slots_for(role, members.size())
		members.sort_custom(_by_current_bearing)
		slots.sort()
		for i: int in members.size():
			_bearings[members[i].get_instance_id()] = slots[i]


## Los angulos disponibles de un rol para `count` enemigos: la banda repartida en
## abanico y espejada a los dos costados, alternando lado a lado.
##
## Alternar y no llenar un costado primero es lo que hace que tres Rangers no
## queden los tres a la izquierda cuando el reparto no da par.
static func slots_for(role: Role, count: int) -> Array[float]:
	var slots: Array[float] = []
	if count <= 0:
		return slots
	var band: Vector2 = ROLE_BANDS.get(role, Vector2(0.0, 0.0))
	# Cuantos angulos distintos hacen falta de un lado: con espejo, cada angulo
	# rinde dos puestos.
	var per_side: int = int(ceil(count / 2.0))
	var angles: Array[float] = []
	if per_side == 1:
		angles.append((band.x + band.y) * 0.5)
	else:
		var step: float = (band.y - band.x) / float(per_side - 1)
		for i: int in per_side:
			angles.append(band.x + step * float(i))
	for i: int in count:
		var angle: float = angles[i / 2]
		# Los mayores a 180 se envuelven al otro lado: la banda del infiltrador
		# cruza la espalda, y 200 grados a la izquierda son 160 a la derecha.
		if angle > 180.0:
			angle -= 360.0
		slots.append(angle if i % 2 == 0 else -angle)
	return slots


## Donde esta parado hoy este enemigo respecto de la mirada del jugador, en grados
## con signo. Es la clave del ordenamiento del reparto.
func _current_bearing(enemy: Enemy) -> float:
	var offset: Vector3 = enemy.global_position - _target_position
	offset.y = 0.0
	if offset.length_squared() < 0.01 or _target_facing.length_squared() < 0.01:
		return 0.0
	var direction: Vector3 = offset.normalized()
	var side: float = signf(_target_facing.cross(direction).y)
	var angle: float = rad_to_deg(_target_facing.angle_to(direction))
	return angle * (side if not is_zero_approx(side) else 1.0)


func _by_current_bearing(a: Enemy, b: Enemy) -> bool:
	return _current_bearing(a) < _current_bearing(b)
