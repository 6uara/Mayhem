extends GutTest
## El visor de enemigos: que abra, que muestre cada arquetipo y que ningun
## control rompa. No juzga como se ven - eso es lo que el visor esta para que
## juzgue una persona.

const VIEWER_SCENE: String = "res://scenes/main/enemy_viewer.tscn"

var _viewer: Node3D


func before_each() -> void:
	_viewer = add_child_autofree(load(VIEWER_SCENE).instantiate())
	await wait_frames(2)


func test_it_lists_every_archetype() -> void:
	assert_eq(_viewer._archetypes.size(), 8, "los ocho arquetipos de data/enemies")
	assert_not_null(_viewer._enemy, "y muestra el primero al abrir")


## El enemigo del visor no puede tener IA: saldria a buscar al jugador, y una
## bomba se armaria y reventaria sola.
func test_the_shown_enemy_has_no_ai_and_no_physics() -> void:
	var enemy: Enemy = _viewer._enemy
	assert_false(enemy.is_physics_processing(), "la fisica la maneja el visor")
	await wait_frames(2)
	assert_eq(enemy.tree_holder.get_child_count(), 0, "sin arbol de comportamiento")


func test_every_archetype_survives_every_control() -> void:
	for data: EnemyData in _viewer._archetypes:
		_viewer._show_archetype(data)
		await wait_frames(2)
		_viewer._on_walk_toggled(true)
		await wait_frames(10)
		_viewer._on_ability_pressed()
		_viewer._on_windup_pressed()
		_viewer._on_hitboxes_toggled(true)
		if data.has_fuse:
			_viewer._on_fuse_toggled(true)
		await wait_frames(10)
		_viewer._on_fuse_toggled(false)
		_viewer._on_hitboxes_toggled(false)
		_viewer._on_walk_toggled(false)
		assert_eq(_viewer._data, data)
	assert_true(is_instance_valid(_viewer._enemy), "el mismo cuerpo para todos, como el pool")


## Caminando, el cuerpo avanza y la velocidad que lee la animacion es real.
func test_walking_moves_the_body_and_feeds_velocity() -> void:
	var start: Vector3 = _viewer._enemy.global_position
	_viewer._on_walk_toggled(true)
	await wait_frames(20)
	assert_gt(_viewer._enemy.global_position.distance_to(start), 0.5)
	assert_gt(_viewer._enemy.velocity.length(), 0.5)
