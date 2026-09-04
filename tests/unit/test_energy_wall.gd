extends GutTest
## El limite de la arena, hecho visible.
##
## Lo que hay que sostener no es como se ve: es que conteste cuando lo tocan, y
## que conteste en el lugar correcto. Una onda que aparece en el punto
## equivocado es peor que no tener onda, porque enseña mal donde esta el borde.

const BOUNDS := AABB(Vector3(-20.0, 0.0, -20.0), Vector3(40.0, 10.0, 40.0))


func _wall() -> EnergyWall:
	var wall := EnergyWall.new()
	add_child_autofree(wall)
	wall.setup(BOUNDS)
	return wall


func test_the_field_is_one_mesh_that_casts_no_shadow() -> void:
	# Aditiva y transparente: si proyectara sombra seria una caja negra sobre la
	# arena.
	var wall: EnergyWall = _wall()
	var field := wall.get_node("Field") as MeshInstance3D
	assert_not_null(field)
	assert_eq(field.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func test_it_starts_quiet() -> void:
	assert_eq(_wall().get_impact_count(), 0)


func test_touching_it_lights_a_ripple() -> void:
	var wall: EnergyWall = _wall()
	wall.ripple_at(Vector3(0.0, 2.0, 20.0))
	assert_eq(wall.get_impact_count(), 1)


func test_the_ripple_never_outgrows_its_slots() -> void:
	# Circular a proposito: ocho ondas a la vez ya es mas de lo que se distingue,
	# y un array que crece seria un array que hay que limpiar.
	var wall: EnergyWall = _wall()
	for i: int in 40:
		wall.ripple_at(Vector3(float(i), 2.0, 20.0))
	assert_eq(wall.get_impact_count(), EnergyWall.MAX_IMPACTS)


func test_rebuilding_leaves_one_field() -> void:
	var wall: EnergyWall = _wall()
	wall.setup(BOUNDS)
	await wait_frames(2)
	var fields: int = 0
	for child: Node in wall.get_children():
		if not child.is_queued_for_deletion():
			fields += 1
	assert_eq(fields, 1)
