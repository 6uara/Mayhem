extends GutTest
## De quien es cada muerte (PLAN_NEW_ENEMY_TYPES §2.4 y §5.4).
##
## Hasta ahora la plata caia sola: morirse era suficiente para que el jugador
## cobrara, sin preguntar quien habia dado el golpe. Eso alcanza mientras el
## jugador sea el unico que mata, y deja de alcanzar en cuanto haya alguien mas
## en el arena repartiendo dano - los Gladiadores, pero tambien la explosion del
## Bomber, que ya existe.
##
## Lo que se prueba:
##
##   1. El golpe final tiene dueno y viaja hasta el HealthComponent, venga de
##      donde venga (bala, explosion, charco).
##   2. Solo se cobra lo que remato el jugador.
##   3. La cadena de la explosion es del que volo al Bomber, que es lo que hace
##      que elegir DONDE matarlo pague.
##
## Las tres fallan calladas: una atribucion perdida se ve como "cobre de menos",
## y ninguna tira un error.

const ENEMY_SCENE: String = "res://scenes/enemies/enemy.tscn"
const BOMBER: String = "res://data/enemies/bomber.tres"
const RUSHER: String = "res://data/enemies/rusher.tres"
const HAZARD_SCENE: String = "res://scenes/arena/hazard_zone.tscn"

var _spawned: Array[Enemy] = []
var _fake_player: Node3D = null


func before_each() -> void:
	# Un nodo en el grupo &"player" alcanza: la atribucion no pregunta por el tipo
	# del atacante, solo por su bando. Es lo mismo que hace Enemy.get_player().
	_fake_player = Node3D.new()
	_fake_player.add_to_group(&"player")
	add_child(_fake_player)
	watch_signals(EventBus)


func after_each() -> void:
	for enemy: Enemy in _spawned:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_spawned.clear()
	if is_instance_valid(_fake_player):
		_fake_player.queue_free()
	_fake_player = null
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


# ------------------------------------------------------------- quien pego ultimo

func test_a_hit_without_an_attacker_leaves_the_death_unowned() -> void:
	var enemy: Enemy = await _spawn(RUSHER)
	enemy.health.apply_damage(10.0)
	assert_null(enemy.health.last_attacker, "nadie se la atribuyo")


func test_the_attacker_travels_with_the_damage() -> void:
	var enemy: Enemy = await _spawn(RUSHER)
	enemy.health.apply_damage(10.0, _fake_player)
	assert_eq(enemy.health.last_attacker, _fake_player, "el golpe tiene dueno")


## Un golpe anonimo despues de uno atribuido no borra al dueno. Es el caso de la
## espoleta del Bomber matandose sola: el jugador lo dejo al borde de la muerte y
## la cuenta llego a cero un frame antes que su proxima bala. Esa muerte es suya.
func test_an_anonymous_hit_does_not_steal_an_owned_kill() -> void:
	var enemy: Enemy = await _spawn(RUSHER)
	enemy.health.apply_damage(5.0, _fake_player)
	enemy.health.apply_damage(5.0)
	assert_eq(enemy.health.last_attacker, _fake_player, "sigue siendo del jugador")


## Los cuerpos salen de un pool: sin limpiar el atacante, el proximo enemigo nace
## debiendole la muerte a quien mato al anterior, y el jugador cobra muertes que
## no hizo.
func test_a_recycled_body_does_not_inherit_the_previous_killer() -> void:
	var enemy: Enemy = await _spawn(RUSHER)
	enemy.health.apply_damage(5.0, _fake_player)
	enemy.setup(load(RUSHER), Vector3.ZERO)
	await wait_physics_frames(1)
	assert_null(enemy.health.last_attacker, "cuerpo reciclado, muerte sin dueno")


# ------------------------------------------------------------------ quien cobra

func test_the_player_gets_paid_for_its_own_kill() -> void:
	var enemy: Enemy = await _spawn(RUSHER)
	enemy.health.apply_damage(enemy.health.max_health, _fake_player)
	await wait_physics_frames(2)
	assert_signal_emit_count(EventBus, "kill_credited", 1, "la remato el jugador")


## La regla nueva. Antes esto pagaba igual, que es exactamente lo que hace que
## esconderse detras de un tercero sea gratis.
func test_a_kill_nobody_claimed_pays_nothing() -> void:
	var enemy: Enemy = await _spawn(RUSHER)
	enemy.health.apply_damage(enemy.health.max_health)
	await wait_physics_frames(2)
	assert_signal_emit_count(EventBus, "kill_credited", 0, "no la mato el jugador")


## La muerte se sigue anunciando aunque no la cobre nadie: el contador de la
## oleada no puede depender de quien pego. Una ola que no termina porque un
## Gladiador se llevo la ultima muerte seria un cuelgue, no un balance.
func test_an_unclaimed_kill_still_ends_up_in_the_wave_count() -> void:
	var enemy: Enemy = await _spawn(RUSHER)
	enemy.health.apply_damage(enemy.health.max_health)
	await wait_physics_frames(2)
	assert_signal_emit_count(EventBus, "enemy_killed", 1, "murio uno igual")


# --------------------------------------------------------- la cadena del Bomber

## El corazon de §5.4: el jugador vuela al Bomber, la explosion mata al Rusher, y
## las dos muertes son del jugador. Sin esto, elegir donde reventarlo no paga y
## el arquetipo vuelve a ser un accidente.
func test_the_blast_belongs_to_whoever_killed_the_bomber() -> void:
	var bomber: Enemy = await _spawn(BOMBER, Vector3.ZERO)
	var victim: Enemy = await _spawn(RUSHER, Vector3(2.0, 0.0, 0.0))

	bomber.health.apply_damage(bomber.health.max_health, _fake_player)
	await wait_physics_frames(2)

	assert_eq(victim.health.last_attacker, _fake_player,
		"lo que mata la explosion es del que volo la bomba")


func test_a_bomber_that_blew_up_on_its_own_pays_for_nothing() -> void:
	var bomber: Enemy = await _spawn(BOMBER, Vector3.ZERO)
	var victim: Enemy = await _spawn(RUSHER, Vector3(2.0, 0.0, 0.0))

	bomber.arm_fuse()
	await wait_seconds(load(BOMBER).fuse_time + 0.4)

	assert_false(bomber.is_active, "la cuenta llego a cero sola")
	assert_null(victim.health.last_attacker, "nadie la toco: la cadena no es de nadie")
	assert_signal_emit_count(EventBus, "kill_credited", 0, "no se cobra nada")


# ----------------------------------------------------------------- el charco

## El charco le sobrevive al frasco que lo dejo y al Elite que lo golpeo, asi que
## el dueno tiene que ser el actor y no el volumen - que ademas vuelve al pool.
func test_a_hazard_pool_credits_whoever_left_it() -> void:
	var zone: HazardZone = add_child_autofree(load(HAZARD_SCENE).instantiate())
	zone.tick_interval = 0.05
	zone.setup(5.0, 3.0, 2.0, _fake_player)
	# Sin gravedad y a mano, como en test_arena_elements: un cuerpo real se cae del
	# volumen en un test que no tiene piso, y el charco deja de alcanzarlo.
	var victim: CharacterBody3D = _make_standing_victim()
	victim.global_position = zone.global_position
	var health: HealthComponent = victim.get_child(1)

	# El aviso de 0.6s no es negociable ni siquiera en un test: hasta que no arma,
	# el charco no lastima a nadie (ver HazardZone).
	await wait_seconds(Tokens.HAZARD_WARNING + 0.3)

	assert_lt(health.current_health, health.max_health, "el charco pego")
	assert_eq(health.last_attacker, _fake_player,
		"lo que el charco mate es del que lo dejo, no del charco")


func _make_standing_victim() -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.add_to_group(&"enemy")
	body.collision_layer = PhysicsLayers.ENEMY

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.4
	shape.shape = capsule
	shape.position.y = 0.9
	body.add_child(shape)

	var health := HealthComponent.new()
	health.max_health = 100.0
	body.add_child(health)

	add_child_autofree(body)
	return body
