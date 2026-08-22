extends GutTest
## Bandos y objetivos (PLAN_NEW_ENEMY_TYPES §2.1 y §2.2).
##
## Dos supuestos del codigo dejaron de valer al mismo tiempo: que el objetivo de
## un enemigo es siempre el jugador, y que un ataque enemigo solo puede tocar al
## jugador. Los dos eran ciertos con dos bandos y ninguno lo es con tres.
##
## La red de esta refactorizacion no esta toda aca: la mitad importante es que
## test_enemy_behavior.gd y test_enemy_pathing_fixes.gd sigan pasando **sin
## tocarse**, porque los cinco arquetipos originales tienen que comportarse
## exactamente igual que antes. Lo que se prueba aca es lo que se agrego.

const ENEMY_SCENE: String = "res://scenes/enemies/enemy.tscn"
const RUSHER: String = "res://data/enemies/rusher.tres"
const RANGER: String = "res://data/enemies/ranger.tres"
const HEALER: String = "res://data/enemies/healer.tres"
const HAZARD_SCENE: String = "res://scenes/arena/hazard_zone.tscn"

var _spawned: Array[Enemy] = []
var _player: Node3D = null


func before_each() -> void:
	_player = Node3D.new()
	_player.add_to_group(&"player")
	add_child(_player)
	_player.global_position = Vector3(20.0, 0.0, 0.0)


func after_each() -> void:
	for enemy: Enemy in _spawned:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_spawned.clear()
	if is_instance_valid(_player):
		_player.queue_free()
	_player = null
	ObjectPool.release_all()
	await wait_physics_frames(2)


## Un arquetipo con la facción cambiada a mano. Los Gladiadores todavía no tienen
## archivo propio, y el punto de la abstracción es justamente que no hace falta
## uno: la facción es un campo, no una clase.
func _spawn(path: String, at: Vector3, faction: Factions.Id = Factions.Id.HORDE) -> Enemy:
	var data: EnemyData = (load(path) as EnemyData).duplicate()
	data.faction = faction
	var enemy: Enemy = load(ENEMY_SCENE).instantiate()
	add_child(enemy)
	await wait_physics_frames(1)
	enemy.setup(data, at)
	await wait_physics_frames(1)
	_spawned.append(enemy)
	return enemy


# ------------------------------------------------------------------- la matriz

func test_everyone_is_hostile_to_everyone_outside_their_own_faction() -> void:
	assert_true(Factions.are_hostile(Factions.Id.PLAYER, Factions.Id.HORDE))
	assert_true(Factions.are_hostile(Factions.Id.PLAYER, Factions.Id.GLADIATOR))
	assert_true(Factions.are_hostile(Factions.Id.HORDE, Factions.Id.GLADIATOR))


func test_nobody_is_hostile_to_its_own_faction() -> void:
	for faction: Factions.Id in [Factions.Id.PLAYER, Factions.Id.HORDE, Factions.Id.GLADIATOR]:
		assert_false(Factions.are_hostile(faction, faction),
			"el fuego amigo no sale de la matriz, sale de la explosion del Bomber")


func test_the_player_group_is_still_what_names_the_player() -> void:
	assert_eq(Factions.of(_player), Factions.Id.PLAYER as int)


func test_an_enemy_says_its_faction_without_anyone_knowing_its_type() -> void:
	var gladiator: Enemy = await _spawn(RUSHER, Vector3.ZERO, Factions.Id.GLADIATOR)
	assert_eq(Factions.of(gladiator), Factions.Id.GLADIATOR as int,
		"Factions no nombra a Enemy - se lo pregunta")


## La mascara existe porque hay consultas que se resuelven en el servidor de
## fisica y no pueden filtrar por bando despues.
func test_the_hostile_mask_of_the_horde_is_what_it_always_was() -> void:
	var mask: int = Factions.hostile_mask(Factions.Id.HORDE)
	assert_true(mask & PhysicsLayers.PLAYER > 0, "la horda le pega al jugador")
	assert_true(mask & PhysicsLayers.GLADIATOR > 0, "y a los Gladiadores")
	assert_eq(mask & PhysicsLayers.ENEMY, 0, "y nunca a si misma")


func test_a_gladiator_body_lives_on_its_own_layer() -> void:
	var horde: Enemy = await _spawn(RUSHER, Vector3.ZERO)
	var gladiator: Enemy = await _spawn(RUSHER, Vector3(3.0, 0.0, 0.0), Factions.Id.GLADIATOR)
	assert_eq(horde.collision_layer, PhysicsLayers.ENEMY, "la horda no se movio de capa")
	assert_eq(gladiator.collision_layer, PhysicsLayers.GLADIATOR)


## Pooleado: el cuerpo vuelve como otra cosa, y la capa tiene que volver con el.
func test_a_recycled_body_goes_back_to_the_layer_of_its_new_faction() -> void:
	var enemy: Enemy = await _spawn(RUSHER, Vector3.ZERO, Factions.Id.GLADIATOR)
	assert_eq(enemy.collision_layer, PhysicsLayers.GLADIATOR)
	enemy.setup(load(RUSHER), Vector3.ZERO)
	await wait_physics_frames(1)
	assert_eq(enemy.collision_layer, PhysicsLayers.ENEMY, "volvio a la horda")


# ---------------------------------------------------------------- el objetivo

## Lo que tenia que no cambiar: sin nadie mas en el arena, un enemigo de la horda
## apunta al jugador, igual que cuando "objetivo" y "jugador" eran la misma
## palabra.
func test_a_horde_enemy_still_targets_the_player() -> void:
	var rusher: Enemy = await _spawn(RUSHER, Vector3.ZERO)
	assert_eq(rusher.get_target(), _player)
	assert_eq(rusher.get_player(), _player, "el nombre viejo sigue contestando")


func test_a_gladiator_prefers_the_closest_hostile_even_if_it_is_not_the_player() -> void:
	var prey: Enemy = await _spawn(RUSHER, Vector3(2.0, 0.0, 0.0))
	var gladiator: Enemy = await _spawn(RUSHER, Vector3.ZERO, Factions.Id.GLADIATOR)
	assert_eq(gladiator.get_target(), prey,
		"el Rusher esta a 2m y el jugador a 20m")


func test_two_enemies_of_the_same_faction_ignore_each_other() -> void:
	var one: Enemy = await _spawn(RUSHER, Vector3.ZERO)
	await _spawn(RUSHER, Vector3(2.0, 0.0, 0.0))
	assert_eq(one.get_target(), _player, "un companero no es un objetivo")


## Aggro-lock: se re-apunta al perder el objetivo, nunca por distancia. Sin esto
## un bicho entre dos hostiles casi equidistantes gira en el lugar y no pelea -
## que es la histeresis que §5.3 del plan pide, resuelta por no elegir de nuevo.
func test_it_does_not_switch_target_just_because_something_closer_appeared() -> void:
	var gladiator: Enemy = await _spawn(RUSHER, Vector3.ZERO, Factions.Id.GLADIATOR)
	var first: Node3D = gladiator.get_target()
	assert_eq(first, _player, "arranca con el unico hostil que hay")

	await _spawn(RUSHER, Vector3(1.0, 0.0, 0.0))
	assert_eq(gladiator.get_target(), first, "no se distrae con lo que aparece al lado")


func test_it_retargets_when_its_target_dies() -> void:
	var prey: Enemy = await _spawn(RUSHER, Vector3(2.0, 0.0, 0.0))
	var gladiator: Enemy = await _spawn(RUSHER, Vector3.ZERO, Factions.Id.GLADIATOR)
	assert_eq(gladiator.get_target(), prey)

	prey.health.apply_damage(prey.health.max_health)
	await wait_physics_frames(2)
	assert_eq(gladiator.get_target(), _player, "muerto el objetivo, busca otro")


# -------------------------------------------------------------------- el daño

## §2.2: el charco del Elite lastimaba a la horda entera, que es fuego amigo que
## el plan reserva **solo** para la explosion del Bomber.
func test_a_pool_does_not_burn_its_owners_own_faction() -> void:
	var pool_owner: Enemy = await _spawn(RUSHER, Vector3(40.0, 0.0, 0.0))
	var ally: HealthComponent = await _health_standing_in_a_pool(pool_owner, &"enemy")
	assert_eq(ally.current_health, ally.max_health,
		"el charco de la horda no quema a la horda")


func test_a_pool_does_burn_the_other_faction() -> void:
	var pool_owner: Enemy = await _spawn(RUSHER, Vector3(40.0, 0.0, 0.0))
	var victim: HealthComponent = await _health_standing_in_a_pool(pool_owner, &"player")
	assert_lt(victim.current_health, victim.max_health,
		"al jugador si, que es de lo que vive el arquetipo")


## Una trampa del arena no es de nadie, y quema a todo el mundo. Es la diferencia
## entre "sin dueño" y "de un bando", y es lo que evita que la regla de arriba
## apague las trampas del mapa de paso.
func test_an_ownerless_trap_still_burns_everyone() -> void:
	var victim: HealthComponent = await _health_standing_in_a_pool(null, &"enemy")
	assert_lt(victim.current_health, victim.max_health,
		"una trampa del arena no perdona a nadie")


## Un charco real con alguien parado adentro, y la salud de ese alguien. Sin
## gravedad y a mano, como en test_arena_elements: un cuerpo con gravedad se cae
## del volumen en un test que no tiene piso.
func _health_standing_in_a_pool(pool_attacker: Node, group: StringName) -> HealthComponent:
	var zone: HazardZone = add_child_autofree(load(HAZARD_SCENE).instantiate())
	zone.tick_interval = 0.05
	zone.setup(5.0, 3.0, 2.0, pool_attacker)

	var body := CharacterBody3D.new()
	body.add_to_group(group)
	body.collision_layer = PhysicsLayers.PLAYER if group == &"player" else PhysicsLayers.ENEMY
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
	body.global_position = zone.global_position

	await wait_seconds(Tokens.HAZARD_WARNING + 0.3)
	return health


func test_a_healer_only_heals_its_own_faction() -> void:
	var healer: Enemy = await _spawn(HEALER, Vector3.ZERO)
	var stranger: Enemy = await _spawn(RUSHER, Vector3(1.0, 0.0, 0.0), Factions.Id.GLADIATOR)
	stranger.health.apply_damage(stranger.health.max_health * 0.5)
	var wounded: float = stranger.health.current_health

	healer.heal_nearby_allies()
	assert_eq(stranger.health.current_health, wounded,
		"un Healer de la horda no cura a un Gladiador")


func test_a_healer_still_heals_its_own() -> void:
	var healer: Enemy = await _spawn(HEALER, Vector3.ZERO)
	var ally: Enemy = await _spawn(RUSHER, Vector3(1.0, 0.0, 0.0))
	ally.health.apply_damage(ally.health.max_health * 0.5)
	var wounded: float = ally.health.current_health

	assert_gt(healer.heal_nearby_allies(), 0, "hay a quien curar")
	assert_gt(ally.health.current_health, wounded, "y lo curo")
