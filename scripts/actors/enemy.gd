class_name Enemy
extends CharacterBody3D
## One enemy scene serves every archetype; `EnemyData` supplies the silhouette,
## stats, audio and behavior tree. Pooled, so `setup()` must fully reset state.
##
## Perception is deliberately absent: enemies always know where the player is
## (CLAUDE.md 5.3). The behavior trees describe engagement, not searching.

signal staggered()

## How long an enemy may be commanded to move while covering no ground before it
## treats itself as obstructed.
const STUCK_TIME: float = 0.3
## Metres per second of real progress below which it is not actually moving.
const STUCK_SPEED: float = 0.9
const JUMP_COOLDOWN: float = 0.9
## A jump that ends this close to where it started got the enemy nowhere.
##
## The bug this measures: an enemy wedged against a lip or a railing hops, lands
## on the same spot, waits out the cooldown and hops again - forever, in place,
## in front of the player. Nothing in the old code ever asked whether a jump had
## worked, so the same one was worth retrying every second of the wave.
const FAILED_JUMP_DISTANCE: float = 0.9
## How long an enemy stops trying to jump after one gets it nowhere. Long enough
## that walking around is what it does next, rather than hopping again.
const FAILED_JUMP_COOLDOWN: float = 3.0
## How long it commits to going sideways after a failed jump.
const DETOUR_TIME: float = 1.1
## How far off its heading it steps while detouring. Not a full right angle: the
## point is to slide off whatever it is caught on, not to walk away from the fight.
const DETOUR_DEGREES: float = 62.0
## A link that just refused to be crossed is left alone for this long, so the
## enemy stops relaunching into the same railing.
const LINK_BLOCK_TIME: float = 4.0
## Cerca de la salida de un link como para contar el cruce por bueno.
const LINK_ARRIVAL: float = 1.5

# Separacion (la unica regla de boids que este juego quiere)
#
# De las tres reglas clasicas, separacion es la que resuelve un problema real
# aca. Cohesion hace exactamente lo contrario de lo que se pidio: junta al grupo,
# que es el amontonamiento del que veniamos escapando. Y alineacion -copiar el
# rumbo del vecino- pelea con el navmesh, que ya decidio por donde va cada uno;
# en una horda que converge al mismo jugador los rumbos ya son casi paralelos,
# asi que no agrega nada que se note.
#
# Lo que queda es empujarse entre vecinos, y eso si se ve: la horda deja de
# apilarse en un punto y ocupa un frente.
## Hasta donde se sienten los vecinos.
const SEPARATION_RADIUS: float = 2.0
## Cuanto pesa el empujon contra la direccion en la que queria ir. Bajo a
## proposito: esto corrige el rumbo, no lo reemplaza, o los enemigos orbitan al
## jugador en vez de llegarle.
const SEPARATION_WEIGHT: float = 0.85
## Cada cuanto se recalculan los vecinos. A 20 por segundo nadie ve la diferencia
## y una oleada elite entera deja de recorrerse en cada frame de cada enemigo.
const SEPARATION_INTERVAL: float = 0.05
## How wide the fan is, in metres either side of the direct line.
const APPROACH_SPREAD: float = 2.4
## Distance over which the lane closes to nothing as the enemy arrives.
const APPROACH_FADE: float = 4.0

const STAGGER_TIME: float = 0.18
const FLASH_TIME: float = 0.08
const GRAVITY: float = 24.0

## Cuanto se le suma al radio del enemigo para decidir que un salto toco al
## jugador. Es el medio cuerpo del jugador: el salto pega por contacto, no por
## alcance, asi que este numero es el ancho de los dos sumado.
const LEAP_CONTACT_RADIUS: float = 0.5
## Diferencia de altura maxima para que el contacto cuente. Generoso a proposito:
## el enemigo cruza el arco entero y puede tocar al jugador a la altura del pecho
## o pasandole por arriba, y las dos son el mismo golpe.
const LEAP_CONTACT_HEIGHT: float = 2.0

@export var health: HealthComponent
@export var agent: NavigationAgent3D
@export var mesh_instance: MeshInstance3D
@export var body_hitbox: HitboxComponent
@export var head_hitbox: HitboxComponent
@export var body_shape: CollisionShape3D
@export var body_hitbox_shape: CollisionShape3D
@export var head_hitbox_shape: CollisionShape3D
@export var tree_holder: Node
@export var halo: MeshInstance3D
@export var tether: MeshInstance3D
## Anillo en el piso que dibuja el radio de la explosion mientras la espoleta
## cuenta. Solo lo usan los arquetipos con `EnemyData.has_fuse`.
@export var fuse_ring: MeshInstance3D
@export var flash_color: Color = Color(1.0, 0.9, 0.75)

var data: EnemyData
var is_active: bool = false
## Set by AI leaves; the enemy walks itself toward this each physics frame.
var move_target: Vector3 = Vector3.ZERO
var is_moving: bool = false

## How far into a wind-up this enemy is, 0 when it is not telegraphing anything.
##
## Kept as state rather than left inside the material because it has to travel:
## the telegraph is the player's warning, and a client whose enemies never glow
## is being asked to dodge something it cannot see coming.
var windup_progress: float = 0.0

## Contra quién está peleando. Era `_player` y se llamaba así porque no había otra
## cosa que pudiera ser; ahora es el hostil más cercano, que para la horda de hoy
## sigue dando el jugador siempre.
var _target: Node3D
var _material: StandardMaterial3D
## The rigged model currently attached, and the scene it came from. Kept between
## spawns: this node is pooled, and re-instantiating a model every time one left
## the pool would pay exactly the cost the pool exists to avoid. Only a change of
## archetype rebuilds it.
var _model: Node3D
var _model_source: PackedScene
## Every MeshInstance3D inside the model, and the one material laid over all of
## them to light the whole bot up at once.
var _model_meshes: Array[MeshInstance3D] = []
var _glow_material: StandardMaterial3D
## Walks the model's legs when it has any. Null for an archetype still wearing
## its grey-box capsule, which has nothing to walk with.
var _gait: LeggedGait
var _flash_timer: float = 0.0
var _stagger_timer: float = 0.0
var _attack_cooldown_left: float = 0.0
## En el aire por un salto de ataque - no por cruzar un link, que es otra cosa.
var _is_leaping: bool = false
## Adonde apunto el salto. Se fija al despegar y no se corrige: esquivar el salto
## es moverse de ahi mientras el enemigo vuela.
var _leap_target: Vector3 = Vector3.ZERO
## Un salto pega una sola vez, por mas que roce al jugador varios frames.
var _leap_hit_landed: bool = false
## Quieto despues de aterrizar. Es la ventana que premia el esquive.
var _leap_recovery_left: float = 0.0
var _behavior_tree: Node
var _slow_multiplier: float = 1.0

## Segundos que le quedan a la espoleta. Solo significa algo con `_fuse_armed`.
var _fuse_left: float = 0.0
## Armada. No se apaga: ni huyendo, ni aturdiendo, ni matandolo - morir la
## adelanta. Ver EnemyData.has_fuse.
var _fuse_armed: bool = false
var _fuse_blink_time: float = 0.0
var _fuse_material: StandardMaterial3D
## Una explosion por cuerpo. Sin esto la bomba que se mata a si misma al detonar
## vuelve a entrar por _on_died() y revienta dos veces.
var _has_detonated: bool = false
## Whoever the healer is currently helping, for the tether beam.
var _tether_target: Enemy
var _stuck_time: float = 0.0
var _jump_cooldown_left: float = 0.0
var _last_position: Vector3
## Set while crossing a NavigationLink3D under our own ballistic arc.
var _link_target: Vector3 = Vector3.ZERO
var _is_traversing_link: bool = false
## Where the enemy left the ground, so the landing can be judged against it.
var _jump_origin: Vector3 = Vector3.ZERO
## True between a jump starting and its landing being judged.
var _jump_pending: bool = false
## Was the enemy on the floor last frame? The landing is the transition.
var _was_on_floor: bool = true
## Seconds left of walking sideways to get out of whatever the jump could not
## clear, and which way. The side alternates so a failed detour tries the other.
var _detour_time: float = 0.0
var _detour_sign: float = 1.0
## The link that just failed, and how long it stays off the table.
var _blocked_link: JumpLink
var _blocked_link_time: float = 0.0
## The link this jump was launched at, kept until the landing is judged.
var _last_link: JumpLink
## This enemy's lane, -1 to 1: which side of the direct line it approaches on,
## and how far out. Rolled per spawn, so a pooled body gets a new one each wave
## and the pack never forms up the same way twice.
var _approach_lane: float = 0.0
## Los enemigos vivos, para que la separacion recorra una lista propia en vez de
## pedirle el grupo al arbol en cada frame de cada enemigo - que era mil arrays
## descartables por segundo en una oleada llena, y es el mismo motivo por el que
## los links estan cacheados.
##
## Es static, asi que sobrevive a la escena que la lleno: un enemigo que se va
## sin pasar por el pool -queue_free, cambio de arena, ObjectPool.clear()- tiene
## que sacarse solo, o la lista arrastra entradas muertas de run en run y cada
## recalculo de separacion, para cada enemigo vivo, las vuelve a filtrar. De eso
## se ocupa _exit_tree().
static var _flock: Array[Enemy] = []
## Empujon acumulado de los vecinos, recalculado a intervalos.
var _separation: Vector3 = Vector3.ZERO
var _separation_timer: float = 0.0
## The arena's jump links, resolved once per spawn. They are placed at author time
## and never change during a run, so paying for a group query every frame - which
## allocates a fresh array each call - buys nothing.
var _links: Array[JumpLink] = []
## Latched answer to _has_navmesh(). NavigationServer3D.map_get_regions()
## allocates a fresh Array[RID] on every call, and _steer() asks the question
## every physics frame for every walking enemy - the same per-frame throwaway
## allocation already removed from _find_link_ahead(). The arena's regions are
## baked offline and committed (see ArenaNavigation), so once the answer is yes
## it stays yes for this spawn.
##
## Only `true` is cached, and the latch is cleared in setup(): a pooled enemy
## outlives the arena it was built in, so caching a `false` from a map that has
## not resolved yet - or from a previous, navmesh-less arena - would leave it
## straight-line steering for its whole life.
var _navmesh_latched: bool = false


func _ready() -> void:
	add_to_group(&"enemy")
	if health != null:
		health.damaged.connect(_on_damaged)
		health.died.connect(_on_died)
	if body_hitbox != null:
		body_hitbox.hit_taken.connect(_on_hit_taken)
	if head_hitbox != null:
		head_hitbox.hit_taken.connect(_on_hit_taken)


## Deja la lista de vivos: el que se va del arbol no vuelve por el pool, y una
## lista static no se vacia sola entre escenas. Ver `_flock`.
func _exit_tree() -> void:
	_flock.erase(self)


func _physics_process(delta: float) -> void:
	if not is_active:
		return

	_flash_timer = maxf(_flash_timer - delta, 0.0)
	if _flash_timer <= 0.0 and _glow_level() > 0.0:
		_set_glow(0.0)
	_stagger_timer = maxf(_stagger_timer - delta, 0.0)
	_attack_cooldown_left = maxf(_attack_cooldown_left - delta, 0.0)
	_jump_cooldown_left = maxf(_jump_cooldown_left - delta, 0.0)
	_detour_time = maxf(_detour_time - delta, 0.0)
	_separation_timer = maxf(_separation_timer - delta, 0.0)
	_leap_recovery_left = maxf(_leap_recovery_left - delta, 0.0)
	_blocked_link_time = maxf(_blocked_link_time - delta, 0.0)
	if _blocked_link_time <= 0.0:
		_blocked_link = null


	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0.0:
		# Only cancel downward speed. Zeroing unconditionally would wipe the jump
		# impulse set at the end of the previous frame, since the enemy is still
		# touching the floor when this runs.
		velocity.y = 0.0

	if halo != null and halo.visible:
		# The ring reads as a marker, not as part of the body, so it turns on its
		# own axis rather than following the enemy's facing.
		halo.rotate_y(delta * 0.8)
	_update_tether()

	# Antes de cualquier rama de movimiento, y fuera de todas ellas. La cuenta
	# corre igual si el bicho esta aturdido, saltando o quieto: una espoleta
	# armada no depende de que el enemigo pueda hacer nada.
	if _fuse_armed:
		_tick_fuse(delta)

	if _is_leaping:
		# En el aire y comprometido. No se dirige y no se frena: que el salto sea
		# esquivable depende de que no corrija a mitad de vuelo.
		_tick_leap()
	elif _leap_recovery_left > 0.0:
		# Aterrizo y esta juntando las patas. Quieto a proposito.
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
	elif _is_traversing_link:
		# Mid-arc: steering would fight the ballistic solution and land it short.
		_tick_link_traversal()
	elif _stagger_timer > 0.0:
		# Staggered enemies keep their knockback but stop steering.
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
	elif is_moving:
		# Checked every frame while walking, not only once wedged against something.
		# A link that leads *down* has no wall to stop the enemy first, so gating
		# traversal behind being stuck meant those were never taken at all.
		if not _try_traverse_link():
			_steer(delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)

	move_and_slide()
	_judge_landing()
	_check_obstruction(delta)


# Public API - lifecycle

## Configures the enemy for an archetype. Called every time it leaves the pool.
func setup(enemy_data: EnemyData, spawn_position: Vector3) -> void:
	data = enemy_data
	global_position = spawn_position
	velocity = Vector3.ZERO
	is_moving = false
	move_target = spawn_position
	# Pooled: an enemy carries the previous occupant's half-finished
	# telegraph otherwise.
	windup_progress = 0.0
	_stagger_timer = 0.0
	_flash_timer = 0.0
	# Desfase inicial, misma idea que el de separacion de abajo: una oleada
	# aparece de golpe, y si todos arrancan con el cooldown en cero el primer
	# ataque de cada arquetipo sale clavado en el mismo frame. El jitter de
	# start_attack_cooldown() los separa recien despues del primer ataque; esto
	# hace que ya el primero llegue escalonado.
	_attack_cooldown_left = randf() * enemy_data.attack_cooldown if enemy_data != null else 0.0
	_slow_multiplier = 1.0
	# Pooleado: el cuerpo puede venir de haber sido una bomba. Una espoleta
	# heredada explotaria a los dos segundos de spawnear un Rusher.
	_fuse_armed = false
	_fuse_left = 0.0
	_fuse_blink_time = 0.0
	_has_detonated = false
	_is_leaping = false
	_leap_hit_landed = false
	_leap_recovery_left = 0.0
	_stuck_time = 0.0
	_jump_cooldown_left = 0.0
	_last_position = spawn_position
	_is_traversing_link = false
	_link_target = spawn_position
	_jump_pending = false
	_was_on_floor = true
	_approach_lane = randf_range(-1.0, 1.0)
	# Pooleado: el cuerpo puede volver como otro arquetipo y hasta como otra
	# facción, y el objetivo del ocupante anterior no tiene por qué serlo suyo.
	_target = null
	_separation = Vector3.ZERO
	# Desfasado a proposito. Con todos arrancando en cero, los veintisiete
	# enemigos de una oleada elite recalculaban vecinos en el mismo frame y
	# despues descansaban juntos: el promedio no lo nota, el peor frame si.
	_separation_timer = randf() * SEPARATION_INTERVAL
	_detour_time = 0.0
	_blocked_link = null
	_blocked_link_time = 0.0
	_last_link = null
	_navmesh_latched = false
	_cache_links()

	_apply_presentation()
	_apply_collision()
	_apply_silhouette_markers()
	_apply_fuse_ring()

	if health != null:
		health.max_health = data.max_health
		health.reset()
	if agent != null:
		agent.max_speed = data.move_speed
	_set_hitboxes_enabled(true)
	_rebuild_behavior_tree()

	is_active = true
	if not _flock.has(self):
		_flock.append(self)
	AudioPool.play_3d(data.spawn_sound, global_position, AudioPool.BUS_ENEMIES)


func _on_acquired() -> void:
	is_active = false


func _on_released() -> void:
	is_active = false
	is_moving = false
	# Un cuerpo que volvio al pool vive debajo del piso. Si siguiera en la lista,
	# empujaria a los vivos desde ahi abajo.
	_flock.erase(self)
	_set_hitboxes_enabled(false)
	_clear_behavior_tree()


## Los enemigos en juego, sin pasar por el arbol.
##
## Es la lista que la separacion ya recorria; publica porque quien quiera
## preguntar "quien esta cerca" tiene el mismo problema que tenia ella, y
## get_nodes_in_group() arma un Array nuevo en cada llamada. Solo para leer: el
## alta y la baja son de setup() y _on_released().
static func get_active_enemies() -> Array[Enemy]:
	return _flock


# Public API - used by the AI leaves

## De qué bando pelea. Lo contesta como método y no como propiedad porque es lo
## que `Factions.of()` le pregunta a cualquier nodo sin conocer su tipo, que es
## como esa utilidad evita nombrar a `Enemy` y cerrar un ciclo de clases.
func get_faction() -> Factions.Id:
	return data.faction if data != null else Factions.Id.HORDE


## Contra quién pelea este enemigo. **No** es "el jugador": es el hostil más
## cercano, y para la horda de hoy eso da el jugador siempre, porque no hay nadie
## más de otra facción en el arena (PLAN_NEW_ENEMY_TYPES §2.1).
##
## Re-apunta sólo cuando el objetivo actual se muere o se va, nunca por distancia:
## la IA está aggro-lockeada a propósito (ver la nota de MovementComponent sobre
## por qué la velocidad del jugador es segura), y elegir el más cercano cada frame
## haría que el bicho oscile entre dos hostiles que se cruzan corriendo en vez de
## comprometerse con uno. Eso también es lo que mantiene barata la búsqueda: se
## recorre la lista al perder el objetivo, no todos los frames - que es la
## advertencia de costo de §5.3 del plan, resuelta por no hacer el trabajo.
func get_target() -> Node3D:
	# Primero lo liberado, y acá y no adentro de `_is_valid_target()`: pasarle un
	# objeto ya liberado a un parámetro tipado es un error del motor antes de que
	# la función llegue a correr, así que la validez no se puede preguntar del otro
	# lado de la llamada. El caso es real: el objetivo puede desaparecer del árbol
	# entre dos frames.
	#
	# Y sin acompañarlo de `!= null`, que es la trampa: un objeto liberado compara
	# **igual** a null, así que esa guarda se saltea sola justo en el caso que
	# tiene que atajar. `is_instance_valid()` sola contesta bien las dos cosas.
	if not is_instance_valid(_target):
		_target = null
	if not _is_valid_target(_target):
		_target = _find_target()
	return _target


## Nombre viejo, mismo objetivo. Existe porque la refactorización tenía que poder
## demostrar que no cambió nada, y la prueba de eso son los tests de los cinco
## arquetipos originales pasando **sin tocarse** (§5.6 del plan).
func get_player() -> Node3D:
	return get_target()


func _is_valid_target(candidate: Node3D) -> bool:
	if candidate == null or not is_instance_valid(candidate):
		return false
	var enemy := candidate as Enemy
	if enemy != null:
		return enemy.is_active
	return Players.is_alive(candidate)


## El hostil más cercano. Los jugadores salen de `Players`, que ya sabía
## buscarlos; los de otras facciones, del array estático que la separación ya
## recorría - y no de `get_nodes_in_group()`, que arma un Array nuevo por llamada.
func _find_target() -> Node3D:
	var mine: Factions.Id = get_faction()
	var best: Node3D = null
	var best_distance: float = INF

	if Factions.are_hostile(mine, Factions.Id.PLAYER):
		best = Players.nearest(global_position)
		if best != null:
			best_distance = global_position.distance_squared_to(best.global_position)

	for other: Enemy in _flock:
		if other == self or not other.is_active:
			continue
		if not Factions.are_hostile(mine, other.get_faction()):
			continue
		var distance: float = global_position.distance_squared_to(other.global_position)
		if distance < best_distance:
			best_distance = distance
			best = other
	return best


func get_target_position() -> Vector3:
	var target: Node3D = get_target()
	return target.global_position if target != null else global_position


## Where this enemy walks while it is closing in - a point beside the player
## rather than the player.
##
## A dozen enemies all pathing to one set of feet arrive as a queue: the same
## line, single file, each one shoving the one in front. Every archetype in the
## game is melee-adjacent enough for that to be the shape of most fights, and it
## reads as a conga line rather than as being surrounded.
##
## Each enemy carries its own lane, a fixed sideways offset from whatever
## direction it happens to be approaching from. Sideways rather than a fixed
## point on a circle, so nobody walks the long way around the player to reach an
## angle it was assigned; they fan out across the front they are already coming
## from.
##
## The lane closes as it arrives. Past the commit distance the offset fades to
## nothing and the enemy goes for the player itself, because an attack aimed at a
## point beside someone is an attack that misses.
func get_approach_position() -> Vector3:
	var victim: Node3D = get_target()
	if victim == null:
		return global_position
	var target: Vector3 = victim.global_position
	var wants_bearing: bool = data != null and data.approach_bearing_weight > 0.0
	if is_zero_approx(_approach_lane) and not wants_bearing:
		return target

	var to_player: Vector3 = target - global_position
	to_player.y = 0.0
	var distance: float = to_player.length()
	var commit: float = _approach_commit_distance()
	if distance <= commit or distance < 0.01:
		return target

	# Full lane far out, none of it once inside the commit distance, and a smooth
	# ramp between - a hard switch would make the whole pack snap inward at the
	# same radius, which is the queue again with extra steps.
	var blend: float = clampf((distance - commit) / APPROACH_FADE, 0.0, 1.0)
	var lateral: Vector3 = to_player.normalized().cross(Vector3.UP)
	var lane_offset: Vector3 = lateral * _approach_lane * APPROACH_SPREAD * blend
	if not wants_bearing:
		return target + lane_offset
	return _bearing_position(target, distance, blend) + lane_offset * 0.5


## El punto desde el que este arquetipo quiere llegar: un lugar alrededor del
## jugador medido desde su propia direccion de mirada, no desde el norte del
## arena.
##
## Se desvanece con la misma rampa que el carril lateral, y por el mismo motivo.
## Un enemigo que insiste en la espalda mientras el jugador gira se queda
## orbitando para siempre y no ataca nunca: flanquea de lejos y se compromete de
## cerca. Que la insistencia baje a cero justo donde empieza el rango de ataque
## es lo que evita el carrusel.
func _bearing_position(target: Vector3, distance: float, blend: float) -> Vector3:
	var facing: Vector3 = get_target_facing()
	if facing.length_squared() < 0.01:
		return target

	var degrees: float = data.approach_bearing_degrees
	if data.approach_bearing_mirrors and _approach_lane < 0.0:
		degrees = -degrees
	# Desde donde mira el jugador, girando alrededor de su eje vertical. A 180
	# grados el punto cae exactamente detras suyo.
	var bearing: Vector3 = facing.rotated(Vector3.UP, deg_to_rad(degrees))

	# A la distancia a la que este arquetipo ya pelea: un Ranger no tiene por que
	# acercarse al flanco, le alcanza con estar en el flanco.
	var stand_off: float = data.preferred_distance if data.preferred_distance > 0.0 \
		else maxf(data.attack_range, commit_floor())
	var wanted: Vector3 = target + bearing * minf(stand_off, distance)
	var weight: float = clampf(data.approach_bearing_weight, 0.0, 1.0) * blend
	return target.lerp(wanted, weight)


## Piso del stand-off para arquetipos cuerpo a cuerpo, que tienen attack_range
## chico y quedarian pegados al jugador antes de haber flanqueado nada.
func commit_floor() -> float:
	return 3.0


## Hacia donde mira el jugador, aplanado. Es la referencia de todo el sistema de
## flancos: "por la espalda" no significa nada respecto del arena, solo respecto
## de el.
##
## Se lee del basis y no de una API de Player, asi que cualquier Node3D sirve -
## incluido el nodo pelado con el que los tests paran a un jugador falso.
func get_target_facing() -> Vector3:
	var target: Node3D = get_target()
	if target == null:
		return Vector3.ZERO
	# Godot mira hacia -Z.
	var forward: Vector3 = -target.global_transform.basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.001 else Vector3.ZERO


## Con que velocidad se esta moviendo el jugador, para quien tenga que adelantarse
## a donde va a estar. Vector3.ZERO si el objetivo no es un cuerpo que se mueva.
func get_target_velocity() -> Vector3:
	var body := get_target() as CharacterBody3D
	return body.velocity if body != null else Vector3.ZERO


## Inside this, the enemy stops flanking and comes straight in. Scaled off its
## own reach so a long-armed elite commits sooner than a rusher.
func _approach_commit_distance() -> float:
	var reach: float = data.attack_range if data != null else 2.0
	return maxf(reach * 1.8, 2.5)


func get_distance_to_target() -> float:
	var target: Node3D = get_target()
	if target == null:
		return INF
	return global_position.distance_to(target.global_position)


## Nombre viejo, ver get_player().
func get_distance_to_player() -> float:
	return get_distance_to_target()


func set_move_target(target: Vector3) -> void:
	move_target = target
	is_moving = true
	if agent != null:
		agent.target_position = target


func stop_moving() -> void:
	is_moving = false


## Yaw-only turn toward the player; enemies never pitch.
func face_target(delta: float, turn_speed: float = 8.0) -> void:
	var to_player: Vector3 = get_target_position() - global_position
	to_player.y = 0.0
	if to_player.length_squared() < 0.01:
		return
	var target_yaw: float = atan2(to_player.x, to_player.z)
	rotation.y = rotate_toward(rotation.y, target_yaw, turn_speed * delta)


func is_attack_ready() -> bool:
	return _attack_cooldown_left <= 0.0


## Cada espera sale un poco distinta, para que dos enemigos del mismo arquetipo no
## queden atacando al unisono el resto de la ola.
##
## El jitter va centrado en el valor base, asi que a la larga el arquetipo ataca
## igual de seguido que antes - lo unico que cambia es que las fases se separan
## solas. Ver EnemyData.attack_cooldown_jitter.
func start_attack_cooldown() -> void:
	if data == null:
		_attack_cooldown_left = 1.0
		return
	var jitter: float = clampf(data.attack_cooldown_jitter, 0.0, 0.9)
	_attack_cooldown_left = data.attack_cooldown * randf_range(1.0 - jitter, 1.0 + jitter)


func is_staggered() -> bool:
	return _stagger_timer > 0.0


## Stun grenade. Reuses the stagger timer, so a stunned enemy also fails its
## behavior tree's attack branch rather than merely standing still.
func apply_stun(duration: float) -> void:
	_stagger_timer = maxf(_stagger_timer, duration)
	staggered.emit()


## Slow field. Multiplier is re-applied every frame the enemy is inside, and
## cleared when it leaves or the field expires.
func apply_slow(multiplier: float) -> void:
	_slow_multiplier = clampf(multiplier, 0.05, 1.0)


func clear_slow() -> void:
	_slow_multiplier = 1.0


## Radius of the shootable volume. Falls back to the body capsule when the archetype
## has not declared one, which is correct for anything roughly as wide as it is deep.
func get_hitbox_radius() -> float:
	if data == null:
		return 0.4
	return data.hitbox_radius if data.hitbox_radius > 0.0 else data.collision_radius


func get_move_speed() -> float:
	var speed: float = data.move_speed if data != null else 5.0
	return speed * _slow_multiplier


## Melee hit on whatever it is fighting, applied only if it is still in range.
func deal_melee_damage() -> void:
	var victim: Node3D = get_target()
	if victim == null or data == null:
		return
	if global_position.distance_to(victim.global_position) > data.attack_range * 1.4:
		return  # The target escaped the wind-up. That is the point of telegraphing.
	if not _can_see(victim):
		# Distance alone is not reach. An enemy wedged under a platform is within
		# 3m of someone standing on top of it, and would otherwise punch through
		# the floor - damage from nowhere, with nothing on screen to explain it.
		return
	var victim_health: HealthComponent = _find_health(victim)
	if victim_health != null:
		victim_health.apply_damage(data.damage, self)
	AudioPool.play_3d(data.attack_sound, global_position, AudioPool.BUS_ENEMIES)


## Se tira encima del jugador. Devuelve false si desde aca no se puede.
##
## El arco se resuelve para caer donde esta el jugador AHORA y no se toca mas: el
## enemigo se compromete al despegar. Eso es lo que hace que el salto se pueda
## esquivar moviendose, y es la diferencia con el golpe de melee de antes, que
## simplemente aparecia cuando el enemigo te habia alcanzado.
func start_leap() -> bool:
	if data == null or not data.can_leap or _is_leaping or not is_on_floor():
		return false
	var victim: Node3D = get_target()
	if victim == null:
		return false
	var target: Vector3 = victim.global_position
	if global_position.distance_to(target) > data.leap_range:
		return false
	# Sin linea de vision no hay salto: si no, se estrella contra la pared que hay
	# en el medio y el jugador ve al bicho tirarse a la nada.
	if not _can_see(victim):
		return false

	_leap_target = target
	_is_leaping = true
	_leap_hit_landed = false
	is_moving = false
	var time: float = maxf(data.leap_flight_time, 0.1)
	var offset: Vector3 = target - global_position
	velocity = Vector3(offset.x, 0.0, offset.z) / time
	velocity.y = offset.y / time + 0.5 * GRAVITY * time
	_begin_jump()
	return true


## Prende la espoleta. Devuelve false si el arquetipo no tiene, o si ya estaba
## armada - eso es lo que hace que la hoja del arbol pueda llamarla cada frame.
##
## A partir de aca la explosion es un hecho. No hay ninguna via para apagarla, y
## eso es a proposito: si huir la desarmara, el Bomber seria un enemigo del que
## te alejas, y toda la decision interesante ("donde lo hago explotar") vive en
## que la respuesta no pueda ser "en ningun lado".
func arm_fuse() -> bool:
	if data == null or not data.has_fuse or _fuse_armed or _has_detonated:
		return false
	_fuse_armed = true
	_fuse_left = maxf(data.fuse_time, 0.05)
	_fuse_blink_time = 0.0
	# La espoleta es un aviso, no un sonido de bicho: se roba una voz antes que
	# perderse. Una bomba silenciosa es una bomba invisible.
	AudioPool.play_3d(data.fuse_sound, global_position, AudioPool.BUS_ENEMIES,
		0.0, 1.0, AudioPool.Priority.TELEGRAPH)
	return true


func is_fuse_armed() -> bool:
	return _fuse_armed


func get_fuse_left() -> float:
	return _fuse_left if _fuse_armed else 0.0


## Desde cuan lejos se arma la espoleta. Cae en attack_range cuando el arquetipo
## no declara uno propio, igual que hitbox_radius cae en collision_radius.
func get_fuse_arm_range() -> float:
	if data == null:
		return 0.0
	return data.fuse_arm_range if data.fuse_arm_range > 0.0 else data.attack_range


func is_leaping() -> bool:
	return _is_leaping


## True mientras esta tirado despues de un salto: ni ataca ni se mueve.
func is_recovering() -> bool:
	return _leap_recovery_left > 0.0


## Un paso de salto: mirar si toco al jugador, y si ya aterrizo.
func _tick_leap() -> void:
	if not _leap_hit_landed:
		_check_leap_contact()
	# is_on_floor() con velocidad hacia abajo es el aterrizaje. La condicion de
	# velocidad importa porque en el primer frame el enemigo todavia toca el piso
	# del que acaba de despegar.
	if is_on_floor() and velocity.y <= 0.0:
		_end_leap()
		return
	# Se cayo del mapa o algo interrumpio el arco.
	if global_position.y < _leap_target.y - 12.0:
		_end_leap()


## El daño del salto. Es contacto real, no alcance: si el jugador se corrio, el
## enemigo pasa de largo y no pasa nada.
func _check_leap_contact() -> void:
	var victim: Node3D = get_target()
	if victim == null:
		return
	var offset: Vector3 = victim.global_position - global_position
	# Horizontal: el jugador mide casi dos metros y el enemigo le pasa por
	# encima o por el pecho segun el momento del arco, y las dos cosas son el
	# mismo impacto. Comparar en 3D haria que rozarle la cabeza no cuente.
	var horizontal: float = Vector2(offset.x, offset.z).length()
	var reach: float = data.collision_radius + LEAP_CONTACT_RADIUS
	if horizontal > reach or absf(offset.y) > LEAP_CONTACT_HEIGHT:
		return
	_leap_hit_landed = true
	var victim_health: HealthComponent = _find_health(victim)
	if victim_health != null:
		victim_health.apply_damage(data.damage, self)
	AudioPool.play_3d(data.attack_sound, global_position, AudioPool.BUS_ENEMIES)


## Un paso de la cuenta regresiva.
##
## No mira distancia, ni linea de vision, ni si el jugador sigue vivo. Una vez
## armada la espoleta es aritmetica, y esa es toda su personalidad.
func _tick_fuse(delta: float) -> void:
	_fuse_left -= delta
	if _fuse_left <= 0.0:
		_detonate()
		return

	# El parpadeo se acelera hacia el final. Es el mismo idioma que la plataforma
	# que se desvanece (Tokens.PLATFORM_BLINK_STEP -> _FAST), asi que el jugador
	# ya sabe leerlo sin que nadie se lo enseñe de nuevo.
	var urgency: float = 1.0 - clampf(_fuse_left / maxf(data.fuse_time, 0.05), 0.0, 1.0)
	var step: float = lerpf(Tokens.TELL_BOMBER_FUSE_SLOW, Tokens.TELL_BOMBER_FUSE_FAST, urgency)
	_fuse_blink_time += delta
	var lit: bool = fmod(_fuse_blink_time, step * 2.0) < step
	if _fuse_material != null:
		_fuse_material.emission_energy_multiplier = 2.6 if lit else 0.35
		_fuse_material.albedo_color.a = 0.75 if lit else 0.2
	# El cuerpo late con el anillo. El anillo dice donde, el cuerpo dice cual -
	# con tres bombas encimadas los anillos se superponen y dejan de distinguirse.
	_set_glow(1.0 if lit else 0.15)


## La cuenta llego a cero: se mata a si misma.
##
## No larga el estallido aca. El estallido tiene un solo lugar - _on_died() - y
## eso es lo que hace que la bomba que revienta sola y la bomba que le vuelan de
## un escopetazo sean exactamente la misma muerte, para la economia, para el
## contador de la oleada y para el pool. Matarse es como esta llega ahi.
func _detonate() -> void:
	_fuse_armed = false
	if health != null and not health.is_dead:
		health.apply_damage(health.current_health)
		return
	# Sin HealthComponent, o ya muerta y todavia contando: nadie va a emitir
	# died(), asi que el camino normal no existe y se hace a mano.
	if not _has_detonated:
		_has_detonated = true
		_spawn_blast()


## El estallido en si. Sale del pool y sobrevive al cuerpo que lo causo, que en
## este mismo frame vuelve al suyo.
func _spawn_blast() -> void:
	if data == null or data.explosion_scene == null:
		return
	var blast := ObjectPool.acquire(data.explosion_scene) as Explosion
	if blast == null:
		push_error("Enemy: explosion_scene de %s no es una Explosion" % data.id)
		return
	blast.global_position = global_position + Vector3.UP * (data.collision_height * 0.5)
	# El estallido lo causa esta bomba, pero lo que mate es del que la mató: matar
	# un Bomber al lado de un grupo es cobrar el grupo (PLAN_NEW_ENEMY_TYPES §5.4).
	# La cadena no se encadena de nuevo - si la explosión mata a otro Bomber, ese
	# segundo estallido hereda el mismo dueño por el mismo camino, porque el golpe
	# que lo mató ya venía atribuido.
	var owner_of_the_blast: Node = health.last_attacker if health != null else null
	blast.detonate(data.explosion_radius, data.explosion_damage, data.explosion_sound,
		self, owner_of_the_blast)


## El anillo de aviso en el piso, del tamaño exacto del estallido.
##
## Es la mitad visual de la promesa que hace HazardZone: lo que se dibuja es lo
## que lastima. Aca ademas se arrastra, porque la bomba camina - por eso el
## jugador puede decidir donde va a reventar en vez de solo cuando.
func _apply_fuse_ring() -> void:
	if fuse_ring == null:
		return
	var carries_fuse: bool = data != null and data.has_fuse
	fuse_ring.visible = carries_fuse
	if not carries_fuse:
		return
	fuse_ring.scale = Vector3(data.explosion_radius, 1.0, data.explosion_radius)
	if _fuse_material == null:
		_fuse_material = StandardMaterial3D.new()
		_fuse_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_fuse_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_fuse_material.emission_enabled = true
		fuse_ring.material_override = _fuse_material
	# HAZARD y no el amarillo del cuerpo: el anillo dice "esto te quema", que es
	# la misma frase que dicen el charco del Elite y las trampas del arena. El
	# color del cuerpo identifica al arquetipo, el del piso identifica al peligro.
	_fuse_material.albedo_color = Color(Tokens.WORLD_HAZARD, 0.2)
	_fuse_material.emission = Tokens.WORLD_HAZARD
	_fuse_material.emission_energy_multiplier = 0.35


func _end_leap() -> void:
	_is_leaping = false
	velocity.x = 0.0
	velocity.z = 0.0
	_leap_recovery_left = maxf(data.leap_recovery, 0.0) if data != null else 0.0


## Clear line from this enemy's head to the target's chest.
##
## Note this is NOT perception - enemies still always know where the player is
## (CLAUDE.md 5.3). It only stops an attack landing through solid geometry.
func _can_see(target: Node3D) -> bool:
	var from: Vector3 = global_position + Vector3.UP * data.head_offset
	var to: Vector3 = target.global_position + Vector3.UP * 1.0
	var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.WORLD)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func fire_projectile() -> void:
	if data == null or data.projectile_scene == null:
		return
	var origin: Vector3 = global_position + Vector3.UP * data.head_offset
	var target: Vector3 = get_target_position() + Vector3.UP * 1.0
	var projectile: Node = ObjectPool.acquire(data.projectile_scene)
	var typed := projectile as EnemyProjectile
	if typed == null:
		push_error("Enemy: %s projectile_scene is not an EnemyProjectile" % data.id)
		return
	var direction: Vector3 = (target - origin).normalized()
	typed.launch(origin, direction, data.damage, data.projectile_speed, self)
	AudioPool.play_3d(data.attack_sound, global_position, AudioPool.BUS_ENEMIES)
	# The shot itself is not in the snapshot - snapshots carry who is standing


## Heals every other living enemy inside `heal_radius`. Returns how many it helped,
## so the healer's tree can fail when there is nothing to do.
##
## "Ally" pasó a significar algo: es el de la misma facción, no cualquiera que
## esté en el grupo `&"enemy"`. Un Healer de la horda curando a un Gladiador
## sería el mismo error que un Gladiador cobrando una muerte del jugador.
func heal_nearby_allies() -> int:
	if data == null:
		return 0
	var healed: int = 0
	for node: Node in get_tree().get_nodes_in_group(&"enemy"):
		var other := node as Enemy
		if other == null or other == self or not other.is_active or other.health == null:
			continue
		if other.get_faction() != get_faction():
			continue
		if global_position.distance_to(other.global_position) > data.heal_radius:
			continue
		if other.health.current_health >= other.health.max_health:
			continue
		other.health.heal(data.heal_amount)
		if _tether_target == null or not is_instance_valid(_tether_target) 				or other.health.get_health_fraction() < _tether_target.health.get_health_fraction():
			_tether_target = other
		healed += 1
	return healed


## Plays the visual half of a wind-up telegraph.
func show_windup(progress: float) -> void:
	windup_progress = clampf(progress, 0.0, 1.0)
	_set_glow(windup_progress)


func clear_windup() -> void:
	windup_progress = 0.0
	if _flash_timer <= 0.0:
		_set_glow(0.0)


# Private

## Steers along the navmesh when there is one, and straight at the target when there
## is not.
##
## The distinction matters. Straight-line steering is correct for flying variants
## and for a map with no navmesh at all (CLAUDE.md 5.3), but it is wrong when a
## navmesh exists and the target simply cannot be walked to: charging the straight
## line then grinds the enemy into whatever wall is in the way, which is what
## "enemies get stuck beside the ramp" looks like from the outside.
##
## So when the path runs out short of an unreachable target, the enemy stops at the
## closest reachable point instead of pushing into geometry.
func _steer(delta: float) -> void:
	var next_point: Vector3 = move_target

	if agent != null and _has_navmesh():
		if not agent.is_navigation_finished():
			var path_point: Vector3 = agent.get_next_path_position()
			if path_point.distance_squared_to(global_position) > 0.01:
				next_point = path_point
		elif not agent.is_target_reachable():
			# As close as walking gets. Stop rather than shove.
			_stop_horizontal(delta)
			return

	var direction: Vector3 = next_point - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.04:
		_stop_horizontal(delta)
		return
	direction = direction.normalized()
	# Fresh off a jump that got nowhere: lean sideways for a moment. Walking at
	# the same corner again would only produce the same failed jump, and sliding
	# along the obstacle is what a player watching expects to see anyway.
	if _detour_time > 0.0:
		direction = direction.rotated(Vector3.UP,
			deg_to_rad(DETOUR_DEGREES) * _detour_sign).normalized()

	if _separation_timer <= 0.0:
		_separation_timer = SEPARATION_INTERVAL
		_separation = _compute_separation()
	if _separation != Vector3.ZERO:
		direction = (direction + _separation * SEPARATION_WEIGHT).normalized()
	var speed: float = get_move_speed()
	velocity.x = move_toward(velocity.x, direction.x * speed, 30.0 * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, 30.0 * delta)


## Decides whether the jump that just ended was worth taking.
##
## Every way out of being stuck ends in a landing, and until now nothing looked
## at where that landing was. An enemy that hops a lip it cannot clear, or
## launches at a link and bounces off the railing beside it, comes down on the
## spot it left - and the only thing standing between it and doing that again is
## a one second cooldown. That is the enemy the player sees pogoing on the edge
## of a platform for the rest of the wave.
##
## Landing where it started is the signal. What follows is not another jump: the
## jump is put away for a few seconds, the link that refused it is left alone,
## and the enemy walks sideways instead - which is what gets it off the corner it
## is caught on.
func _judge_landing() -> void:
	var grounded: bool = is_on_floor()
	var just_landed: bool = grounded and not _was_on_floor
	_was_on_floor = grounded
	if not just_landed or not _jump_pending:
		return
	_jump_pending = false
	# Un cruce de link se juzga por haber llegado, no por cuanto se movio: un
	# link a plomo -una caida recta desde una plataforma- avanza cero en
	# horizontal y seria un cruce perfecto marcado como fallido.
	var arrived: bool = false
	if _last_link != null:
		arrived = global_position.distance_to(_link_target) <= LINK_ARRIVAL
	_note_jump_result(Vector2(global_position.x - _jump_origin.x,
		global_position.z - _jump_origin.z).length(), arrived)


## Lo que se decide con el resultado del salto, separado de detectar el aterrizaje.
##
## Aparte porque son dos cosas distintas: una necesita un piso abajo y un cuerpo
## cayendo, la otra es una regla. Partido asi, la regla se puede ejercitar sin
## montar una arena, y lo que queda arriba es solo "esto fue un aterrizaje".
func _note_jump_result(travelled: float, reached_target: bool = false) -> void:
	if reached_target or travelled >= FAILED_JUMP_DISTANCE:
		return

	_jump_cooldown_left = FAILED_JUMP_COOLDOWN
	_stuck_time = 0.0
	# Alternate sides: if going left did not free it, the next attempt goes right
	# rather than grinding into the same corner from the same angle.
	_detour_sign = -_detour_sign
	_detour_time = DETOUR_TIME
	if _is_traversing_link:
		_is_traversing_link = false
	if _last_link != null:
		_blocked_link = _last_link
		_blocked_link_time = LINK_BLOCK_TIME
		_last_link = null


## Records a jump so its landing can be judged. Every launch goes through here.
func _begin_jump(link: JumpLink = null) -> void:
	_jump_origin = global_position
	_jump_pending = true
	_was_on_floor = true
	_last_link = link


## Empujon que reciben unos de otros los enemigos que estan demasiado juntos.
##
## Es la regla de separacion de un boid, y nada mas que esa. Cada vecino dentro
## del radio empuja en direccion contraria, con fuerza que crece cuanto mas
## encimado esta - dos enemigos pisandose se separan fuerte, dos a dos metros
## casi no se sienten.
##
## Horizontal a proposito: la componente vertical la maneja la gravedad, y un
## empujon hacia arriba entre dos enemigos apilados los haria flotar.
##
## No lo hace el NavigationAgent3D, aunque la escena diga avoidance_enabled: eso
## requiere pasarle la velocidad al agente y esperar su callback, y nadie lo
## hacia nunca. El agente calculaba evitacion todos los frames para que el
## resultado se tirara a la basura.
func _compute_separation() -> Vector3:
	var push := Vector3.ZERO
	for other: Enemy in _flock:
		if other == self or not is_instance_valid(other) or not other.is_active:
			continue
		var offset: Vector3 = global_position - other.global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance >= SEPARATION_RADIUS:
			continue
		if distance < 0.01:
			# Exactamente encimados: no hay direccion que sacar del vector, asi
			# que se desempata con algo estable pero distinto por enemigo.
			var angle: float = float(get_instance_id() % 360) * TAU / 360.0
			push += Vector3(cos(angle), 0.0, sin(angle))
			continue
		push += offset / distance * (1.0 - distance / SEPARATION_RADIUS)
	return push


## Watches for the enemy being told to move while covering no ground, and hops the
## thing in the way.
##
## Deliberately reactive rather than predictive: it does not care *why* it is stuck
## - a ramp lip, a crowded doorway, a navmesh seam, another enemy - only that it is.
## That is what makes it a safety net for every future layout rather than a patch
## for the one ramp that was reported.
func _check_obstruction(delta: float) -> void:
	var travelled: float = Vector2(global_position.x - _last_position.x,
		global_position.z - _last_position.z).length()
	_last_position = global_position

	var wants_to_move: bool = is_moving and not is_staggered()
	var making_progress: bool = travelled / maxf(delta, 0.0001) > STUCK_SPEED
	if not wants_to_move or making_progress or not is_on_floor():
		_stuck_time = 0.0
		return

	# A ledge is far commoner than a real obstacle, and stepping is instant, so try
	# it every frame rather than waiting out the stuck timer.
	if _try_step_up():
		_stuck_time = 0.0
		return

	_stuck_time += delta
	if _stuck_time < STUCK_TIME or _jump_cooldown_left > 0.0:
		return
	if _try_jump_obstacle():
		_stuck_time = 0.0


## Rides out a link crossing. The arc was solved at launch, so nothing steers here -
## the traversal simply ends when the enemy is back on the ground.
func _tick_link_traversal() -> void:
	if is_on_floor() and velocity.y <= 0.0:
		_is_traversing_link = false
		# Land facing the way it was going, so the walk resumes without a pivot.
		set_move_target(_link_target)
		return
	# Bail out if the arc was interrupted - a wall, a wave reset, anything.
	if global_position.y < _link_target.y - 12.0:
		_is_traversing_link = false


## Crosses a NavigationLink3D by jumping it.
##
## The pathfinder will happily route through a link, but it only ever hands back a
## point to walk to - so without this the enemy walks to the lip of the gap and
## stands there. The link supplies the arc; the enemy just commits to it.
func _try_traverse_link() -> bool:
	if data == null or not data.can_jump or _is_traversing_link:
		return false
	# Nothing launches off the ground it is not standing on, and the cooldown is what
	# stops an enemy that lands beside a link's far end from immediately taking it
	# back - now that this runs every frame rather than only when wedged.
	if not is_on_floor() or _jump_cooldown_left > 0.0:
		return false

	# One scan answers both questions. This used to ask "is a link the next step?"
	# and "which link is it?" separately, walking the whole link group twice - and
	# the first question was answered by looking for exactly the link the second one
	# then went and found again, so it could never actually reject anything.
	var link: JumpLink = _find_link_ahead()
	if link == null:
		return false

	var exit: Vector3 = link.get_exit_for(global_position)
	velocity = link.get_launch_velocity(global_position, exit, GRAVITY)
	_link_target = exit
	_is_traversing_link = true
	_jump_cooldown_left = JUMP_COOLDOWN
	_begin_jump(link)
	return true


## Resolved on spawn rather than in _ready(): a pooled enemy is built once but reused
## across waves and arenas, so the links it should know about are the ones present
## the moment it is put into play.
func _cache_links() -> void:
	_links.clear()
	for node: Node in get_tree().get_nodes_in_group(&"jump_link"):
		var link := node as JumpLink
		if link != null:
			_links.push_back(link)


## The nearest link whose near end we are standing on, and whose far end is closer to
## where we are trying to go than we are now - otherwise jumping is a detour.
##
## Reads the cached list rather than the scene tree. This runs every frame for every
## walking enemy now, and a group query allocates its result array on each call - at
## a full wave that was well over a thousand throwaway arrays a second, for a set of
## links that never changes during a run.
func _find_link_ahead() -> JumpLink:
	var best: JumpLink = null
	var best_distance: float = INF
	for link: JumpLink in _links:
		if not is_instance_valid(link) or not link.enabled:
			continue
		# The one that just bounced this enemy off a railing is off the table for
		# a few seconds. Without this the pathfinder keeps offering the same
		# crossing and the enemy keeps taking it, which is the pogo.
		if link == _blocked_link:
			continue
		var distance: float = global_position.distance_to(_nearest_end(link))
		if distance > data.collision_radius + 1.6 or distance >= best_distance:
			continue
		var exit: Vector3 = link.get_exit_for(global_position)
		if exit.distance_to(move_target) >= global_position.distance_to(move_target):
			continue  # the far side is no closer to the goal, so jumping is a detour
		best = link
		best_distance = distance
	return best


func _nearest_end(link: JumpLink) -> Vector3:
	var start: Vector3 = link.get_start_global()
	var end: Vector3 = link.get_end_global()
	return start if global_position.distance_squared_to(start) \
		< global_position.distance_squared_to(end) else end


## Lifts the enemy over a low ledge - the ramp's own side edge, a platform lip, the
## seam where two boxes meet.
##
## This is the case the reported bug actually was: head-on the ramp is a slope and
## move_and_slide climbs it; from the side it is a vertical edge, and an edge of any
## height stops a CharacterBody3D dead. The navmesh routes across those edges
## because the bake believes the agent can climb agent_max_climb, so the body has to
## be able to as well or the two disagree and the enemy grinds.
func _try_step_up() -> bool:
	if data == null or not is_on_wall():
		return false
	var step_height: float = data.max_auto_step
	if step_height <= 0.0:
		return false

	var heading: Vector3 = _desired_heading()
	if heading == Vector3.ZERO:
		return false

	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var reach: float = data.collision_radius + 0.35
	var ahead: Vector3 = global_position + heading * reach

	# Nothing to step onto if the space above the ledge is occupied.
	var head_room: Vector3 = global_position + Vector3.UP * (step_height + 0.1)
	var head_query := PhysicsRayQueryParameters3D.create(head_room,
		head_room + heading * reach, PhysicsLayers.WORLD)
	head_query.exclude = [get_rid()]
	if not space.intersect_ray(head_query).is_empty():
		return false

	# Find the top of whatever is in front, by looking down from above it.
	var from_above: Vector3 = ahead + Vector3.UP * (step_height + 0.1)
	var down_query := PhysicsRayQueryParameters3D.create(from_above,
		ahead - Vector3.UP * 0.05, PhysicsLayers.WORLD)
	down_query.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(down_query)
	if hit.is_empty():
		return false

	var rise: float = float(hit["position"].y) - global_position.y
	if rise <= 0.02 or rise > step_height:
		return false

	# Lifting the body without checking it fits is what makes an enemy bounce: the
	# next depenetration shoves it back out and it re-approaches, forever. Test the
	# destination first, and commit only if it can also move forward from there -
	# otherwise standing on the very lip would just stall it again.
	var lifted: Transform3D = global_transform
	lifted.origin.y = float(hit["position"].y) + 0.05
	var nudge: Vector3 = heading * (data.collision_radius * 0.5)
	if test_move(lifted, nudge):
		return false

	global_position = lifted.origin + nudge
	return true


## Where the enemy is trying to go, preferring its actual motion and falling back to
## its target when a wall has already scrubbed the velocity to nothing.
func _desired_heading() -> Vector3:
	var heading := Vector3(velocity.x, 0.0, velocity.z)
	if heading.length_squared() < 0.01:
		heading = move_target - global_position
		heading.y = 0.0
	if heading.length_squared() < 0.01:
		return Vector3.ZERO
	return heading.normalized()


## Probes the obstacle the way the player's mantle does: something solid at knee
## height with clear air above it is a thing to jump, not a wall to lean on.
func _try_jump_obstacle() -> bool:
	if data == null or not data.can_jump:
		return false

	var heading: Vector3 = _desired_heading()
	if heading == Vector3.ZERO:
		return false

	var reach: float = data.collision_radius + 0.6
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state

	# Something in the way just above the feet. Probing at knee height would sail
	# over exactly the low edges that cause the most trouble.
	var shin: Vector3 = global_position + Vector3.UP * 0.12
	var shin_query := PhysicsRayQueryParameters3D.create(shin, shin + heading * reach,
		PhysicsLayers.WORLD | PhysicsLayers.ENEMY)
	shin_query.exclude = [get_rid()]
	if space.intersect_ray(shin_query).is_empty():
		return false

	# ...and nothing above it, or the jump would just be a shorter grind.
	var clearance: Vector3 = global_position + Vector3.UP * data.max_step_height
	var clear_query := PhysicsRayQueryParameters3D.create(clearance,
		clearance + heading * reach, PhysicsLayers.WORLD)
	if not space.intersect_ray(clear_query).is_empty():
		return false

	velocity.y = data.jump_velocity
	_jump_cooldown_left = JUMP_COOLDOWN
	_begin_jump()
	return true


## True when there is baked navigation to follow. False means straight-line
## steering is the right answer, not a fallback for a broken path.
func _has_navmesh() -> bool:
	if _navmesh_latched:
		return true
	var map: RID = agent.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_regions(map).is_empty():
		return false
	_navmesh_latched = true
	return true


func _stop_horizontal(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)


func _apply_presentation() -> void:
	_apply_model()
	if mesh_instance == null:
		return
	# The primitive is the fallback silhouette. With a model attached it is still
	# here - the archetype may be swapped for one without a model on the next
	# trip out of the pool - it is simply not drawn.
	mesh_instance.visible = _model == null
	if data.mesh != null:
		mesh_instance.mesh = data.mesh
	mesh_instance.scale = Vector3.ONE * data.body_scale
	# Centrada sobre la capsula, igual que _resize_capsule hace con las formas.
	#
	# Estaba fija en 0.9 desde la escena, que es la mitad de la capsula de 1.8 con
	# la que se autoro - o sea, correcta para un arquetipo de 1.8m de alto y para
	# ninguno de los que hay. El Ranger (1.9) zafaba por poco, el Elite (2.8) y el
	# Summoner (2.2) quedaban hundidos, y cualquier arquetipo mas bajo que 1.8
	# flota. Las mallas ya vienen con el pivote en su propio centro (es lo que
	# garantiza tools/bake_enemy_meshes.gd), asi que la mitad de la altura es
	# donde va. Los arquetipos con model_scene no lo notan: ahi esta primitiva
	# no se dibuja.
	mesh_instance.position.y = data.collision_height * 0.5
	if _material == null:
		_material = StandardMaterial3D.new()
		mesh_instance.material_override = _material
	_material.albedo_color = data.body_color
	_material.emission_enabled = true
	_material.emission = flash_color
	_material.emission_energy_multiplier = 0.0


## Attaches the archetype's model, or takes down the one from the archetype this
## pooled body used to be.
func _apply_model() -> void:
	if data.model_scene == _model_source:
		_place_model()
		return
	if _model != null:
		_model.queue_free()
	_model = null
	_model_meshes.clear()
	_model_source = data.model_scene
	if _model_source == null:
		return
	_model = _model_source.instantiate() as Node3D
	if _model == null:
		push_error("Enemy: %s model_scene is not a Node3D" % data.id)
		return
	add_child(_model)
	_prune_authoring_nodes(_model)
	_collect_model_meshes(_model)
	_place_model()
	_attach_gait()


## Throws away what the modelling program packed alongside the model.
##
## A .fbx exported straight out of Blender keeps that file's camera and lights.
## Instanced once per enemy that is a light per enemy, and a Camera3D that makes
## itself current takes over the screen - the horde would be filming itself.
## Stripped here rather than in the import settings so it holds for any model
## anyone drops in later, whatever state its export was in.
func _prune_authoring_nodes(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Camera3D or child is Light3D:
			child.queue_free()
			continue
		_prune_authoring_nodes(child)


## Gives the model a walk, if it has legs to walk with. Dropped again when it
## has none rather than left in place doing nothing every frame - the pool runs
## a lot of these at once.
func _attach_gait() -> void:
	if _gait != null:
		_gait.queue_free()
		_gait = null
	if _model == null:
		return
	var gait := LeggedGait.new()
	add_child(gait)
	if gait.setup(_model, self):
		_gait = gait
		return
	gait.queue_free()


func _place_model() -> void:
	if _model == null:
		return
	_model.position = data.model_offset
	_model.scale = Vector3.ONE * data.model_scale
	_model.rotation = Vector3(0.0, deg_to_rad(data.model_yaw_degrees), 0.0)


## An imported model brings its own materials, so the hit flash cannot be an
## albedo swap the way it is on a grey-box capsule. It is laid over the top
## instead: one unshaded material on every part, transparent until something
## lights it up.
func _collect_model_meshes(node: Node) -> void:
	var mesh_node := node as MeshInstance3D
	if mesh_node != null:
		if _glow_material == null:
			_glow_material = StandardMaterial3D.new()
			_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_glow_material.albedo_color = Color(flash_color, 0.0)
		mesh_node.material_overlay = _glow_material
		_model_meshes.append(mesh_node)
	for child: Node in node.get_children():
		_collect_model_meshes(child)


## One knob for "this enemy is lit up", whichever way it is being drawn: the
## emission on a capsule, the overlay on a model. Hit flashes and attack
## wind-ups both go through here, so neither has to know which it is looking at.
func _set_glow(amount: float) -> void:
	# Ceiling of 1.2 rather than 1.0: the hit flash deliberately overshoots the
	# brightest wind-up, and 1.2 * 2.5 is the 3.0 the capsule flash has always
	# used. The overlay cannot go past opaque, so it clamps a step earlier.
	var level: float = clampf(amount, 0.0, 1.2)
	if _glow_material != null:
		_glow_material.albedo_color = Color(flash_color, minf(level, 1.0) * 0.8)
	if _material != null:
		_material.emission_energy_multiplier = level * 2.5


func _glow_level() -> float:
	if _glow_material != null:
		return _glow_material.albedo_color.a
	return _material.emission_energy_multiplier if _material != null else 0.0


## Shapes are resized per archetype, so each pooled instance needs its own copy -
## sub-resources in a .tscn are shared between instances by default.
## The halo and the tether are what make the Healer readable; every other archetype
## turns them off.
func _apply_silhouette_markers() -> void:
	if halo != null:
		halo.visible = data.has_halo
		if data.has_halo:
			halo.position.y = data.halo_height
			halo.scale = Vector3.ONE * data.halo_radius
			_tint(halo, data.body_color)
	if tether != null:
		tether.visible = false
		_tint(tether, data.body_color)
	_tether_target = null


func _tint(mesh: MeshInstance3D, tint: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 1.4
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = material


## Beam from the healer to its target, redrawn each frame it is active. Breaking
## line of sight is not simulated: the tether simply follows whoever is being healed.
func _update_tether() -> void:
	if tether == null or not data.has_tether:
		return
	if _tether_target == null or not is_instance_valid(_tether_target) 			or not _tether_target.is_active:
		tether.visible = false
		return
	var to_target: Vector3 = _tether_target.global_position - global_position
	var length: float = to_target.length()
	if length < 0.1:
		tether.visible = false
		return
	tether.visible = true
	tether.global_position = global_position + Vector3.UP * data.head_offset * 0.8
	tether.look_at(_tether_target.global_position + Vector3.UP, Vector3.UP)
	tether.scale = Vector3(1.0, 1.0, length)


func _apply_collision() -> void:
	# El cuerpo vive en la capa de su facción. Es lo que deja que una consulta de
	# física filtre por bando sin poder preguntar después - ver
	# `Factions.body_layer()`. Para la horda es `ENEMY`, o sea lo mismo que trae
	# authorado `enemy.tscn`.
	collision_layer = Factions.body_layer(get_faction())
	_resize_capsule(body_shape, data.collision_height, data.collision_radius, 0.5)
	# The hitbox tracks the silhouette, the body capsule tracks the navmesh - see
	# EnemyData.hitbox_radius for why those stopped being the same number.
	_resize_capsule(body_hitbox_shape, maxf(data.collision_height - 0.4, 0.4),
		get_hitbox_radius(), 0.5)

	if head_hitbox_shape == null:
		return
	if not _is_owned_shape(head_hitbox_shape):
		head_hitbox_shape.shape = head_hitbox_shape.shape.duplicate()
	var head_sphere := head_hitbox_shape.shape as SphereShape3D
	if head_sphere != null:
		head_sphere.radius = data.head_radius
		head_hitbox_shape.position.y = data.head_offset


func _resize_capsule(node: CollisionShape3D, height: float, radius: float,
		center_fraction: float) -> void:
	if node == null:
		return
	if not _is_owned_shape(node):
		node.shape = node.shape.duplicate()
	var capsule := node.shape as CapsuleShape3D
	if capsule == null:
		return
	capsule.radius = radius
	capsule.height = maxf(height, radius * 2.0)
	node.position.y = capsule.height * center_fraction


func _is_owned_shape(node: CollisionShape3D) -> bool:
	return node.shape != null and node.shape.resource_local_to_scene


func _rebuild_behavior_tree() -> void:
	_clear_behavior_tree()
	if data.behavior_tree == null or tree_holder == null:
		return
	_behavior_tree = data.behavior_tree.instantiate()
	tree_holder.add_child(_behavior_tree)
	var beehave := _behavior_tree as BeehaveTree
	if beehave != null:
		beehave.actor = self


func _clear_behavior_tree() -> void:
	if _behavior_tree != null and is_instance_valid(_behavior_tree):
		_behavior_tree.queue_free()
	_behavior_tree = null


func _set_hitboxes_enabled(enabled: bool) -> void:
	# Hitboxes are found by the projectile's ray, not by monitoring, so they have
	# to leave their physics layer rather than just stop processing.
	for hitbox: HitboxComponent in [body_hitbox, head_hitbox]:
		if hitbox != null:
			hitbox.collision_layer = PhysicsLayers.HITBOX if enabled else 0


func _on_hit_taken(_amount: float, _is_headshot: bool, hit_position: Vector3) -> void:
	# Visible reaction to every hit is a gunplay-feel requirement (CLAUDE.md 5.3).
	_flash_timer = FLASH_TIME
	# Over the top of the wind-up glow on purpose: a hit landing has to read even
	# on an enemy that is already lit up.
	_set_glow(1.2)
	var resistance: float = clampf(data.stagger_resistance if data != null else 0.0, 0.0, 1.0)
	if resistance >= 1.0:
		return
	_stagger_timer = STAGGER_TIME * (1.0 - resistance)
	var knockback: Vector3 = global_position - hit_position
	knockback.y = 0.0
	if knockback.length_squared() > 0.001:
		var force: float = 4.0 * (1.0 - resistance) / maxf(data.mass if data != null else 1.0, 0.1)
		velocity += knockback.normalized() * force
	staggered.emit()


func _on_damaged(_amount: float, _remaining: float) -> void:
	pass


func _on_died() -> void:
	if not is_active:
		return
	is_active = false
	is_moving = false
	_fuse_armed = false
	_set_hitboxes_enabled(false)
	_clear_behavior_tree()
	# Antes del release, porque el cuerpo se va al pool tres lineas mas abajo y el
	# estallido necesita saber donde estaba parado.
	#
	# Sin preguntar si la espoleta llego a armarse: es una bomba, y una bomba que
	# explota siempre se lee mucho mejor que una que a veces no. Matar un Bomber
	# recien spawneado del otro lado del arena tambien revienta - eso es lo que lo
	# vuelve un recurso que el jugador puede usar a proposito.
	if data != null and data.has_fuse and not _has_detonated:
		_has_detonated = true
		_spawn_blast()
	AudioPool.play_3d(data.death_sound, global_position, AudioPool.BUS_ENEMIES)
	# Los dos contestan preguntas distintas y por eso siguen siendo dos: enemy_killed
	# es "murió uno" y lo cobra el contador de la oleada pase lo que pase;
	# kill_credited es "y es tuyo", que a partir de ahora no siempre es cierto.
	EventBus.enemy_killed.emit(data.id, global_position, data.reward_currency)
	if _killed_by_the_player():
		EventBus.kill_credited.emit(data.reward_currency)
	ObjectPool.release(self)


## Si el golpe final fue del jugador, que es lo único que se cobra
## (PLAN_NEW_ENEMY_TYPES §5.4).
##
## Sube por los padres en vez de mirar sólo el nodo: el atacante que llega es el
## cuerpo del jugador hoy, pero una utilidad o un charco puesto por él pueden
## atribuirse a un hijo suyo, y esa muerte también es suya.
func _killed_by_the_player() -> bool:
	if health == null:
		return false
	var attacker: Node = health.last_attacker
	while attacker != null and is_instance_valid(attacker):
		if attacker.is_in_group(&"player"):
			return true
		attacker = attacker.get_parent()
	return false


func _find_health(node: Node) -> HealthComponent:
	for child: Node in node.get_children():
		var component := child as HealthComponent
		if component != null:
			return component
	return null
