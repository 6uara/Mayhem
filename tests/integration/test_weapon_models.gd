extends GutTest
## Los viewmodels de las cuatro armas: brazos y arma en una sola malla
## (tools/blender/build_viewmodels.py). Que se vean bien lo dice
## tools/preview_viewmodel.gd; lo que se fija aca es el contrato con
## WeaponComponent: la boca del cañon marcada, el cable del gancho con origen, y
## que todo lo que se anima vuelve al reposo.

const WEAPONS: Array[String] = ["pistol", "smg", "rifle_ak", "shotgun"]


func _data(weapon_id: String) -> WeaponData:
	return load("res://data/weapons/%s.tres" % weapon_id)


## Con la malla de los brazos adentro, la caja del modelo ya no dice donde
## termina el cañon: la boca viene marcada, y es lo mas adelantado del modelo.
func test_every_viewmodel_marks_its_muzzle_at_the_front() -> void:
	for weapon_id: String in WEAPONS:
		var model: Node3D = add_child_autofree(_data(weapon_id).viewmodel.instantiate())
		var muzzle := model.find_child(WeaponComponent.MUZZLE_NODE, true, false) as Node3D
		assert_not_null(muzzle, "%s: trae el nodo Muzzle" % weapon_id)
		if muzzle == null:
			continue
		var front: float = INF
		for node: Node in model.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			var bounds: AABB = mesh_instance.transform * mesh_instance.mesh.get_aabb()
			front = minf(front, bounds.position.z)
		assert_almost_eq(muzzle.position.z, front, 0.01,
			"%s: la boca esta en el frente del modelo" % weapon_id)


func test_the_muzzle_marker_sits_on_the_marked_muzzle() -> void:
	var weapon := WeaponComponent.new()
	weapon.data = _data("rifle_ak")
	weapon.muzzle = Node3D.new()
	weapon.add_child(weapon.muzzle)
	add_child_autofree(weapon)
	var model: Node3D = weapon._view.get_child(0)
	var marked := model.find_child(WeaponComponent.MUZZLE_NODE, true, false) as Node3D
	var expected: Vector3 = model.transform * marked.position
	var marker: Node3D = weapon._view.get_node("MuzzleMarker")
	assert_almost_eq(marker.position, expected, Vector3.ONE * 0.001)
	assert_almost_eq(weapon.muzzle.position, weapon.data.viewmodel_offset + expected,
		Vector3.ONE * 0.001, "los tiros salen de la misma boca que el fogonazo")


## El cable del gancho sale de la muñeca izquierda del modelo, sin un segundo
## lanzador dibujado encima del que trae la malla.
func test_the_grapple_cable_leaves_from_the_wrist_of_each_viewmodel() -> void:
	for weapon_id: String in WEAPONS:
		var host: Node3D = add_child_autofree(Node3D.new())
		var weapon := WeaponComponent.new()
		weapon.data = _data(weapon_id)
		weapon.viewmodel_parent = host
		add_child_autofree(weapon)
		var launcher: Node3D = weapon._view.get_node_or_null("GrappleLauncher")
		assert_not_null(launcher, "%s: tiene lanzador" % weapon_id)
		if launcher == null:
			continue
		assert_false(launcher.show_body, "%s: el lanzador lo dibuja la malla" % weapon_id)
		assert_ne(weapon.data.viewmodel_launcher_position, Vector3.ZERO,
			"%s: el lanzador tiene un lugar en la muñeca" % weapon_id)


## Sacar el arma la sube desde abajo, y termina exactamente en su lugar.
func test_equipping_raises_the_weapon_into_place() -> void:
	var weapon := WeaponComponent.new()
	weapon.data = _data("smg")
	weapon.idle_breath_height = 0.0
	weapon.idle_breath_roll_degrees = 0.0
	add_child_autofree(weapon)
	weapon._equip_left = weapon.equip_time
	weapon._tick_viewmodel(0.0)
	assert_lt(weapon._view.position.y, weapon.data.viewmodel_offset.y - 0.1,
		"recien sacada esta abajo")
	weapon._tick_viewmodel(weapon.equip_time)
	assert_almost_eq(weapon._view.position, weapon.data.viewmodel_offset, Vector3.ONE * 0.001,
		"al terminar queda en su lugar")
	assert_almost_eq(weapon._view.rotation_degrees, Vector3.ZERO, Vector3.ONE * 0.001)


## La recarga es el bloque entero: baja, golpea al entrar el cargador, y vuelve.
func test_the_reload_dips_seats_and_returns() -> void:
	var weapon := WeaponComponent.new()
	weapon.data = _data("rifle_ak")
	add_child_autofree(weapon)
	assert_eq(weapon._reload_seat(0.0), 0.0, "sin recarga no hay golpe")
	assert_gt(weapon._reload_seat(weapon.reload_seat_at), 0.0, "el cargador entra con un golpe")
	assert_eq(weapon._reload_seat(0.2), 0.0, "el golpe es un instante, no toda la recarga")
	assert_eq(weapon._reload_seat(1.0), 0.0)
