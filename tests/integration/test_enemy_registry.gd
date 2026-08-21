extends GutTest
## La lista de enemigos vivos que Enemy mantiene, y que ahora consultan tanto la
## separacion como el campo de lentitud.
##
## Es static, o sea que sobrevive a la escena que la lleno. Eso es lo que la hace
## rapida y tambien lo que la hace peligrosa: un cuerpo que se va sin darse de
## baja queda ahi para siempre, empujando a los vivos desde donde sea que haya
## quedado - debajo del piso, o en una arena que ya no existe. Ninguna de esas
## fallas tira un error; se ven como enemigos que se esquivan solos.


func _make_enemy() -> Enemy:
	var enemy: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	add_child_autofree(enemy)
	await wait_physics_frames(1)
	enemy.setup(load("res://data/enemies/rusher.tres"), Vector3.ZERO)
	await wait_physics_frames(1)
	return enemy


func test_a_spawned_enemy_joins_the_list() -> void:
	var enemy: Enemy = await _make_enemy()
	assert_true(Enemy.get_active_enemies().has(enemy), "spawneado, esta en la lista")


## La baja por el pool: el cuerpo se recicla y hasta que no lo vuelvan a spawnear
## no cuenta como vecino de nadie.
func test_a_pooled_body_leaves_the_list() -> void:
	var enemy: Enemy = await _make_enemy()
	enemy._on_released()
	assert_false(Enemy.get_active_enemies().has(enemy), "en el pool, fuera de la lista")


## La otra baja, la que costo un commit aparte: irse del arbol sin pasar por el
## pool. Cambio de escena, queue_free, ObjectPool.clear(). Una lista static no se
## vacia sola entre escenas.
func test_an_enemy_that_leaves_the_tree_leaves_the_list() -> void:
	var enemy: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	add_child(enemy)
	await wait_physics_frames(1)
	enemy.setup(load("res://data/enemies/rusher.tres"), Vector3.ZERO)
	await wait_physics_frames(1)
	assert_true(Enemy.get_active_enemies().has(enemy), "vivo y en la lista")

	# El id y no el objeto: Array[Enemy].has() valida el tipo del argumento, y una
	# instancia liberada ya no pasa esa validacion - el test reventaria antes de
	# poder responder la pregunta.
	var id: int = enemy.get_instance_id()
	enemy.queue_free()
	await wait_physics_frames(2)
	var still_there: bool = false
	for other: Enemy in Enemy.get_active_enemies():
		if is_instance_valid(other) and other.get_instance_id() == id:
			still_there = true
	assert_false(still_there, "se fue del arbol: no puede seguir contando como vecino")


## Lo que ninguna de las dos bajas puede permitir: instancias muertas adentro.
## Quien recorra la lista las va a tocar, y tocar un objeto liberado es un crash,
## no un bug de comportamiento.
func test_the_list_never_holds_a_freed_instance() -> void:
	var one: Enemy = await _make_enemy()
	var two: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	add_child(two)
	await wait_physics_frames(1)
	two.setup(load("res://data/enemies/rusher.tres"), Vector3.ZERO)
	await wait_physics_frames(1)
	two.queue_free()
	await wait_physics_frames(2)

	for enemy: Enemy in Enemy.get_active_enemies():
		assert_true(is_instance_valid(enemy), "toda instancia en la lista sigue viva")
	assert_true(Enemy.get_active_enemies().has(one), "y el que sigue vivo sigue estando")


## No se duplica: setup() corre cada vez que el cuerpo sale del pool, y un cuerpo
## contado dos veces se empuja a si mismo.
func test_respawning_a_body_does_not_double_count_it() -> void:
	var enemy: Enemy = await _make_enemy()
	enemy.setup(load("res://data/enemies/rusher.tres"), Vector3.ZERO)
	await wait_physics_frames(1)

	var seen: int = 0
	for other: Enemy in Enemy.get_active_enemies():
		if other == enemy:
			seen += 1
	assert_eq(seen, 1, "una sola vez en la lista")
