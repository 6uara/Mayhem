extends GutTest
## Los viewmodels de las cuatro armas y su clip de recarga. Que se vean bien lo
## dice tools/preview_viewmodel.gd; lo que se fija aca es el contrato con
## WeaponComponent: cada modelo trae un clip `reload` que mueve una pieza, y el
## clip empieza y termina en la pose de reposo.

## Arma -> la pieza que tiene que moverse al recargar (tools/blender/build_weapons.py).
const PARTS: Dictionary = {
	"pistol": "Slide",
	"smg": "Magazine",
	"rifle_ak": "Magazine",
	"shotgun": "Pump",
}


func _data(weapon_id: String) -> WeaponData:
	return load("res://data/weapons/%s.tres" % weapon_id)


func _part_at(player: AnimationPlayer, part: Node3D, progress: float) -> Transform3D:
	player.seek(player.get_animation(&"reload").length * progress, true)
	return part.transform


func test_every_weapon_ships_a_reload_clip_that_moves_its_part() -> void:
	for weapon_id: String in PARTS:
		var model: Node3D = add_child_autofree(_data(weapon_id).viewmodel.instantiate())
		var players: Array[Node] = model.find_children("*", "AnimationPlayer", true, false)
		assert_eq(players.size(), 1, "%s: un AnimationPlayer" % weapon_id)
		var player := players[0] as AnimationPlayer
		assert_true(player.has_animation(&"reload"), "%s: trae el clip reload" % weapon_id)
		var part := model.find_child(PARTS[weapon_id], true, false) as Node3D
		assert_not_null(part, "%s: la pieza %s existe" % [weapon_id, PARTS[weapon_id]])
		if part == null or not player.has_animation(&"reload"):
			continue
		player.assigned_animation = &"reload"
		var rest: Transform3D = _part_at(player, part, 0.0)
		assert_true(_part_at(player, part, 1.0).is_equal_approx(rest),
			"%s: el clip termina en el reposo" % weapon_id)
		var moved: bool = false
		for progress: float in [0.2, 0.5, 0.65, 0.83]:
			moved = moved or not _part_at(player, part, progress).is_equal_approx(rest)
		assert_true(moved, "%s: la pieza se mueve en algun momento" % weapon_id)


## El clip se recorre por el progreso de la recarga, no por reloj: a mitad de la
## recarga del rifle el cargador esta afuera, y al cortarla vuelve a su lugar.
func test_reloading_drives_the_magazine_through_the_clip() -> void:
	var weapon := WeaponComponent.new()
	weapon.data = _data("rifle_ak")
	add_child_autofree(weapon)
	var magazine := weapon.find_child("Magazine", true, false) as Node3D
	assert_not_null(magazine, "el cargador cuelga del viewmodel")
	var rest: Transform3D = magazine.transform

	weapon._ammo = 0
	assert_true(weapon.try_reload(), "precondicion: recarga")
	weapon._process(weapon.get_reload_time() * 0.25)
	assert_false(magazine.transform.is_equal_approx(rest), "a un cuarto el cargador salio")

	weapon.reset()
	weapon._process(0.0)
	assert_true(magazine.transform.is_equal_approx(rest), "cortar la recarga lo devuelve")


## Las piezas escondidas en reposo (el cartucho de la escopeta, en escala casi
## cero bajo el arma) no cuentan para la caja del arma, que ubica las manos y la
## boca del cañon.
func test_hidden_parts_do_not_stretch_the_weapon_bounds() -> void:
	var weapon := WeaponComponent.new()
	weapon.data = _data("shotgun")
	add_child_autofree(weapon)
	var model: Node3D = weapon._view.get_child(0)
	var body := model.find_child("Body", true, false) as MeshInstance3D
	var body_bounds: AABB = model.transform * (body.transform * body.mesh.get_aabb())
	var bounds: AABB = weapon._model_bounds(model)
	assert_almost_eq(bounds.position.y, body_bounds.position.y, 0.02,
		"el piso de la caja es el del arma, no el del cartucho escondido")
