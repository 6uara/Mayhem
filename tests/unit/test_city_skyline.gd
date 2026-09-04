extends GutTest
## La ciudad de fondo.
##
## Contesta la pregunta que el venue deja abierta apenas se hace de noche: donde
## pasa esto. Lo que hay que sostener es que este lejos, que este detras de las
## gradas, y que la ciudad entera siga siendo una sola draw call.

const SHELL_SCENE: String = "res://scenes/arena/shells/coliseum_shell.tscn"
const REACH := Vector2(60.0, 60.0)


func _skyline() -> CitySkyline:
	var skyline := CitySkyline.new()
	add_child_autofree(skyline)
	return skyline


## Del array del nodo y no del MultiMesh: en headless el servidor de render es
## un dummy y devuelve todas las transformadas en cero.
func _towers(skyline: CitySkyline) -> Array[Transform3D]:
	return skyline.get_towers()


func test_the_city_is_one_multimesh() -> void:
	var skyline: CitySkyline = _skyline()
	skyline.populate(Vector3.ZERO, REACH, 0.0)
	assert_eq(skyline.get_tower_count(),
		skyline.depth_rings * skyline.towers_per_ring)
	assert_eq(skyline.multimesh.instance_count, skyline.get_tower_count())
	assert_not_null(skyline.multimesh.mesh, "una malla para toda la ciudad")


func test_no_tower_lands_on_top_of_the_stands() -> void:
	# Una torre dentro del coliseo no es un skyline, es un poste en la tribuna.
	var skyline: CitySkyline = _skyline()
	skyline.populate(Vector3.ZERO, REACH, 0.0)
	var closest: float = INF
	for transform: Transform3D in _towers(skyline):
		var origin: Vector3 = transform.origin
		closest = minf(closest, Vector2(origin.x, origin.z).length())
	# Contra el borde de las gradas y no contra el radio del anillo: el jitter
	# corre cada torre en los dos ejes, asi que la distancia al centro puede
	# quedar bastante por debajo del radio nominal sin que eso sea un problema.
	assert_gt(closest, REACH.x,
		"hay una torre parada adentro del venue")
	assert_gt(closest, REACH.x + skyline.stand_off * 0.5,
		"la ciudad quedo demasiado encima del coliseo")


func test_the_far_rings_are_taller_so_they_can_be_seen() -> void:
	# Si los anillos de atras midieran lo mismo que los de adelante quedarian
	# tapados enteros, y los tres anillos costarian lo mismo que uno.
	var skyline: CitySkyline = _skyline()
	skyline.depth_rings = 2
	skyline.populate(Vector3.ZERO, REACH, 0.0)
	var per_ring: int = skyline.towers_per_ring
	var near: float = 0.0
	var far: float = 0.0
	var transforms: Array[Transform3D] = _towers(skyline)
	for i: int in transforms.size():
		var height: float = transforms[i].basis.get_scale().y
		if i < per_ring:
			near = maxf(near, height)
		else:
			far = maxf(far, height)
	assert_gt(far, near)


func test_the_bases_are_buried_under_the_arena_floor() -> void:
	# Nunca se ve donde apoyan, y asi no hay que decidir a que altura esta el
	# suelo de una ciudad que no existe.
	var skyline: CitySkyline = _skyline()
	skyline.populate(Vector3.ZERO, REACH, 12.0)
	for transform: Transform3D in _towers(skyline):
		var bottom: float = transform.origin.y - transform.basis.get_scale().y * 0.5
		assert_lte(bottom, 12.0, "una torre apoya por encima del piso")


func test_the_same_arena_gets_the_same_city() -> void:
	var first: CitySkyline = _skyline()
	first.populate(Vector3.ZERO, REACH, 0.0)
	var second: CitySkyline = _skyline()
	second.populate(Vector3.ZERO, REACH, 0.0)
	assert_eq(_towers(second), _towers(first))


func test_the_venue_puts_the_city_behind_its_own_stands() -> void:
	# El shell sabe hasta donde llegan sus gradas; la ciudad no tiene por que
	# adivinarlo, igual que el publico no adivina donde estan los escalones.
	var shell := (load(SHELL_SCENE) as PackedScene).instantiate() as ArenaColiseum
	add_child_autofree(shell)
	shell.setup(AABB(Vector3.ZERO, Vector3(72.0, 20.0, 72.0)))
	var skyline := shell.get_node("Skyline") as CitySkyline

	assert_gt(shell.get_outer_reach().x, 36.0, "las gradas llegan mas alla de la arena")
	assert_gt(skyline.get_tower_count(), 0)
	for transform: Transform3D in _towers(skyline):
		var origin: Vector3 = transform.origin
		var distance: float = Vector2(origin.x - 36.0, origin.z - 36.0).length()
		assert_gt(distance, shell.get_outer_reach().x,
			"una torre quedo por dentro del borde de la tribuna")
