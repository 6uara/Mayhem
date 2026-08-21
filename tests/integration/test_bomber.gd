extends GutTest
## El Bomber: una cuenta regresiva con patas.
##
## Lo que se prueba aca no son los numeros del arquetipo (esos viven en
## test_enemy_data), sino las tres promesas que lo hacen ser lo que es:
##
##   1. La espoleta, una vez armada, NO se apaga. Ni huyendo, ni aturdiendolo,
##      ni matandolo - matarlo la adelanta.
##   2. Lo que revienta es exactamente el circulo que se dibujo en el piso.
##   3. La explosion lastima a la horda, y es el unico caso en que la horda se
##      lastima sola (PLAN_NEW_ENEMY_TYPES §5.2).
##
## Las tres se rompen en silencio. Una espoleta que se cancela al morir se ve
## como "no exploto, raro"; un radio que no coincide con el decal se ve como
## "me pego desde lejos". Ninguna tira un error.

const ENEMY_SCENE: String = "res://scenes/enemies/enemy.tscn"
const BOMBER: String = "res://data/enemies/bomber.tres"
const RUSHER: String = "res://data/enemies/rusher.tres"

var _spawned: Array[Enemy] = []


func after_each() -> void:
	for enemy: Enemy in _spawned:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_spawned.clear()
	ObjectPool.release_all()
	await wait_physics_frames(2)


func _spawn(path: String, at: Vector3 = Vector3.ZERO) -> Enemy:
	var enemy: Enemy = load(ENEMY_SCENE).instantiate()
	add_child(enemy)
	await wait_physics_frames(1)
	enemy.setup(load(path), at)
	await wait_physics_frames(1)
	_spawned.append(enemy)
	return enemy


func _data() -> EnemyData:
	return load(BOMBER)


# ----------------------------------------------------------------- la espoleta

func test_a_fresh_bomber_is_not_counting() -> void:
	var bomber: Enemy = await _spawn(BOMBER)
	assert_false(bomber.is_fuse_armed(), "recien spawneado no cuenta nada")


func test_arming_it_starts_the_count() -> void:
	var bomber: Enemy = await _spawn(BOMBER)
	assert_true(bomber.arm_fuse(), "se arma")
	assert_true(bomber.is_fuse_armed(), "armada")
	assert_almost_eq(bomber.get_fuse_left(), _data().fuse_time, 0.05,
		"arranca en fuse_time")


## Es lo que le deja a la hoja del arbol llamarla cada frame sin pensar: la
## primera vez arma, las demas dicen que no y el selector cae a perseguir.
func test_arming_twice_does_not_restart_the_count() -> void:
	var bomber: Enemy = await _spawn(BOMBER)
	bomber.arm_fuse()
	await wait_physics_frames(6)
	var left: float = bomber.get_fuse_left()
	assert_false(bomber.arm_fuse(), "la segunda llamada no hace nada")
	assert_almost_eq(bomber.get_fuse_left(), left, 0.05, "la cuenta no se reinicio")


func test_the_count_runs_down_on_its_own() -> void:
	var bomber: Enemy = await _spawn(BOMBER)
	bomber.arm_fuse()
	var start: float = bomber.get_fuse_left()
	await wait_physics_frames(10)
	assert_lt(bomber.get_fuse_left(), start, "la cuenta baja sola")


## El corazon del arquetipo. Aturdirlo lo frena y no lo apaga: si el aturdimiento
## cancelara la espoleta, la respuesta al Bomber seria "dispararle" y no
## "moverse", que es la unica respuesta que se le quiso pedir al jugador.
func test_stunning_it_does_not_defuse_it() -> void:
	var bomber: Enemy = await _spawn(BOMBER)
	bomber.arm_fuse()
	var start: float = bomber.get_fuse_left()
	bomber.apply_stun(5.0)
	await wait_physics_frames(10)
	assert_true(bomber.is_fuse_armed(), "aturdido y contando")
	assert_lt(bomber.get_fuse_left(), start, "la cuenta corrio igual")


## Un arquetipo sin espoleta no la puede prender ni por accidente. Los cuerpos
## salen de un pool compartido, asi que este es el test de que un Rusher que
## reciclo el cuerpo de una bomba no hereda la bomba.
func test_an_archetype_without_a_fuse_cannot_arm_one() -> void:
	var rusher: Enemy = await _spawn(RUSHER)
	assert_false(rusher.arm_fuse(), "un Rusher no tiene espoleta")
	assert_false(rusher.is_fuse_armed(), "y no queda contando")


func test_a_recycled_body_does_not_carry_the_previous_fuse() -> void:
	var enemy: Enemy = await _spawn(BOMBER)
	enemy.arm_fuse()
	assert_true(enemy.is_fuse_armed(), "armada como Bomber")
	enemy.setup(load(RUSHER), Vector3.ZERO)
	await wait_physics_frames(1)
	assert_false(enemy.is_fuse_armed(), "reutilizado como Rusher: sin espoleta")


# ---------------------------------------------------------------- el estallido

func test_the_count_reaching_zero_kills_it() -> void:
	var bomber: Enemy = await _spawn(BOMBER)
	bomber.arm_fuse()
	await wait_seconds(_data().fuse_time + 0.4)
	assert_false(bomber.is_active, "la cuenta llego a cero y se murio sola")


## La promesa central: matarlo NO desactiva la bomba, la adelanta. Es lo que
## convierte al Bomber en un recurso del jugador en vez de en una amenaza.
func test_killing_it_detonates_it_instead_of_cancelling_it() -> void:
	var bomber: Enemy = await _spawn(BOMBER, Vector3.ZERO)
	var victim: Enemy = await _spawn(RUSHER, Vector3(2.0, 0.0, 0.0))
	bomber.arm_fuse()
	var before: float = victim.health.current_health

	bomber.health.apply_damage(bomber.health.max_health)
	await wait_physics_frames(2)

	assert_lt(victim.health.current_health, before,
		"lo mataron a mitad de cuenta y reviento igual")


## El hueco que el plan dejo abierto, cerrado: una bomba que nunca llego a
## armarse tambien explota. Es mas legible que una regla condicional, y es lo que
## hace que matar un Bomber recien spawneado al lado de un grupo sea una jugada
## deliberada y no un accidente.
func test_a_bomber_that_never_armed_still_explodes_when_killed() -> void:
	var bomber: Enemy = await _spawn(BOMBER, Vector3.ZERO)
	var victim: Enemy = await _spawn(RUSHER, Vector3(2.0, 0.0, 0.0))
	assert_false(bomber.is_fuse_armed(), "nunca vio al jugador")
	var before: float = victim.health.current_health

	bomber.health.apply_damage(bomber.health.max_health)
	await wait_physics_frames(2)

	assert_lt(victim.health.current_health, before, "es una bomba: explota igual")


## Una sola vez. La bomba que llega a cero se mata a si misma, y esa muerte
## vuelve a entrar por el mismo camino que usaria un escopetazo - sin un candado
## explota dos veces y hace el doble de daño del que promete el circulo.
func test_it_only_ever_explodes_once() -> void:
	var bomber: Enemy = await _spawn(BOMBER, Vector3.ZERO)
	var victim: Enemy = await _spawn(RUSHER, Vector3(2.0, 0.0, 0.0))
	victim.health.max_health = 10000.0
	victim.health.reset()
	bomber.arm_fuse()
	await wait_seconds(_data().fuse_time + 0.5)

	var lost: float = victim.health.max_health - victim.health.current_health
	assert_almost_eq(lost, _data().explosion_damage, 0.5,
		"un solo estallido, un solo tick de daño")


# ---------------------------------------------------- el circulo es la promesa

## HazardZone existe porque un area que lastima fuera de su propio decal es un
## bug y no una dificultad. El anillo que el Bomber arrastra esta autorado con
## explosion_radius, asi que el estallido tiene que usar ese mismo numero.
func test_the_blast_reaches_exactly_as_far_as_the_ring_it_drew() -> void:
	var radius: float = _data().explosion_radius
	var bomber: Enemy = await _spawn(BOMBER, Vector3.ZERO)
	var inside: Enemy = await _spawn(RUSHER, Vector3(radius - 1.0, 0.0, 0.0))
	var outside: Enemy = await _spawn(RUSHER, Vector3(radius + 3.0, 0.0, 0.0))
	var inside_before: float = inside.health.current_health
	var outside_before: float = outside.health.current_health

	bomber.health.apply_damage(bomber.health.max_health)
	await wait_physics_frames(2)

	assert_lt(inside.health.current_health, inside_before, "adentro del circulo: le pega")
	assert_eq(outside.health.current_health, outside_before,
		"afuera del circulo: no le pega, aunque este cerca del borde")


## El fuego amigo dentro de la horda existe, y existe SOLO por esto. Un Ranger
## errandole al jugador no puede lastimar a un companero; una bomba si.
func test_the_blast_is_the_hordes_only_friendly_fire() -> void:
	var bomber: Enemy = await _spawn(BOMBER, Vector3.ZERO)
	var ally: Enemy = await _spawn(RUSHER, Vector3(1.5, 0.0, 0.0))
	var before: float = ally.health.current_health

	bomber.health.apply_damage(bomber.health.max_health)
	await wait_physics_frames(2)

	assert_almost_eq(ally.health.current_health, before - _data().explosion_damage, 0.5,
		"la explosion no distingue bandos")


## No se cuenta a si misma. Ya esta muerta cuando el estallido sale, y contarla
## seria una muerte de mas para la economia y para el contador de la oleada.
func test_the_bomber_is_not_its_own_victim() -> void:
	var bomber: Enemy = await _spawn(BOMBER, Vector3.ZERO)
	bomber.arm_fuse()
	await wait_seconds(_data().fuse_time + 0.5)
	assert_false(bomber.is_active, "murio una sola vez")


# -------------------------------------------------------------------- el anillo

## El decal solo aparece en un arquetipo que puede explotar, y mide lo que va a
## explotar. Un anillo de aviso sobre un Rusher es una promesa que nadie cumple.
func test_only_a_fused_archetype_shows_the_ring() -> void:
	var bomber: Enemy = await _spawn(BOMBER)
	var rusher: Enemy = await _spawn(RUSHER)
	assert_true(bomber.fuse_ring.visible, "la bomba dibuja su radio")
	assert_false(rusher.fuse_ring.visible, "el Rusher no promete ninguna explosion")


func test_the_ring_is_drawn_at_the_blast_radius() -> void:
	var bomber: Enemy = await _spawn(BOMBER)
	assert_almost_eq(bomber.fuse_ring.scale.x, _data().explosion_radius, 0.01,
		"el circulo dibujado es el circulo que lastima")
	assert_almost_eq(bomber.fuse_ring.scale.z, _data().explosion_radius, 0.01,
		"y es un circulo, no una elipse")
