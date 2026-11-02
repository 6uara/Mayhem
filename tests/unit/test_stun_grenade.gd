extends GutTest
## La granada aturdidora sale del pool, y el pool devuelve el cuerpo como quedo.

const SCENE: PackedScene = preload("res://scenes/utilities/stun_grenade.tscn")
const DATA: UtilityData = preload("res://data/utilities/stun_grenade.tres")


func after_each() -> void:
	ObjectPool.release_all()


## El destello se apaga subiendo la transparencia a 1. Sin volverla a 0, la
## segunda granada que salia del mismo cuerpo aturdia sin destello visible.
func test_a_recycled_grenade_flashes_again() -> void:
	var grenade := ObjectPool.acquire(SCENE) as StunGrenade
	grenade.data = DATA
	grenade.flash_mesh.transparency = 1.0
	grenade._activate()
	assert_true(grenade.flash_mesh.visible, "precondicion: el destello arranco")
	assert_almost_eq(grenade.flash_mesh.transparency, 0.0, 0.001,
		"el destello arranca opaco aunque el anterior haya terminado transparente")
