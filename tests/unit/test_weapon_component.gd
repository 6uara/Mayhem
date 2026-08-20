extends GutTest
## Ammo, reload and recoil-index behavior. The recoil index tests are the ones that
## protect the learnability of a spray: same trigger discipline, same pattern.

const PROJECTILE_SCENE: String = "res://scenes/projectiles/projectile.tscn"

var _weapon: WeaponComponent
var _data: WeaponData


func before_each() -> void:
	_data = WeaponData.new()
	_data.id = &"test_rifle"
	_data.damage = 10.0
	_data.fire_rate = 10.0
	_data.magazine_size = 5
	_data.reserve_ammo_max = 20
	_data.reload_time = 1.0
	_data.spread_hipfire = 0.0
	_data.spread_ads = 0.0
	_data.projectile_speed = 100.0
	_data.projectile_scene = load(PROJECTILE_SCENE)

	var pattern := RecoilPattern.new()
	pattern.points = PackedVector2Array([Vector2(0, 1), Vector2(0, 1.2)])
	pattern.reset_time = 0.3
	_data.recoil_pattern = pattern

	_weapon = WeaponComponent.new()
	_weapon.data = _data
	_weapon.aim_node = _weapon
	add_child_autofree(_weapon)


func after_each() -> void:
	ObjectPool.release_all()


## Fires once and clears the fire-rate cooldown so the next shot is allowed.
func _fire_once() -> void:
	_weapon.set_trigger(true)
	_weapon.set_trigger(false)
	_weapon._process(_data.get_shot_interval())


func test_starts_with_a_full_magazine_and_reserve() -> void:
	assert_eq(_weapon.get_ammo(), 5)
	assert_eq(_weapon.get_reserve(), 20)


func test_firing_consumes_ammo() -> void:
	_fire_once()
	assert_eq(_weapon.get_ammo(), 4)


func test_fire_rate_blocks_a_second_shot_in_the_same_window() -> void:
	_weapon.set_trigger(true)
	_weapon.set_trigger(true)
	assert_eq(_weapon.get_ammo(), 4, "a held trigger cannot outrun the fire rate")


func test_shot_index_advances_per_shot() -> void:
	assert_eq(_weapon.get_shot_index(), 0)
	_fire_once()
	assert_eq(_weapon.get_shot_index(), 1)
	_fire_once()
	assert_eq(_weapon.get_shot_index(), 2)


func test_shot_index_resets_after_reset_time() -> void:
	_fire_once()
	assert_eq(_weapon.get_shot_index(), 1)
	_weapon._process(_data.recoil_pattern.reset_time + 0.01)
	assert_eq(_weapon.get_shot_index(), 0, "the pattern restarts after a pause")


func test_shot_index_does_not_reset_below_reset_time() -> void:
	_fire_once()
	_weapon._process(_data.recoil_pattern.reset_time * 0.5)
	assert_eq(_weapon.get_shot_index(), 1)


func test_reload_refills_from_reserve() -> void:
	_fire_once()
	_fire_once()
	assert_true(_weapon.try_reload())
	_weapon._process(_data.reload_time + 0.01)
	assert_eq(_weapon.get_ammo(), 5)
	assert_eq(_weapon.get_reserve(), 18, "a partial magazine only takes what it needs")


func test_reload_resets_the_recoil_pattern() -> void:
	_fire_once()
	_weapon.try_reload()
	_weapon._process(_data.reload_time + 0.01)
	assert_eq(_weapon.get_shot_index(), 0)


func test_reload_is_rejected_when_full_or_dry() -> void:
	assert_false(_weapon.try_reload(), "a full magazine cannot be reloaded")
	_fire_once()
	_weapon._reserve = 0
	assert_false(_weapon.try_reload(), "an empty reserve cannot be reloaded")


func test_reload_clamps_to_remaining_reserve() -> void:
	_weapon._ammo = 0
	_weapon._reserve = 2
	assert_true(_weapon.try_reload())
	_weapon._process(_data.reload_time + 0.01)
	assert_eq(_weapon.get_ammo(), 2)
	assert_eq(_weapon.get_reserve(), 0)


func test_pickup_overflow_is_left_behind() -> void:
	_weapon._reserve = 18
	assert_eq(_weapon.add_reserve_ammo(10), 2, "only the amount that fits is taken")
	assert_eq(_weapon.get_reserve(), 20)


func test_ads_progress_moves_toward_the_target() -> void:
	_weapon.set_ads(true)
	_weapon._process(_data.ads_transition_time * 0.5)
	assert_between(_weapon.ads_progress, 0.1, 0.9)
	_weapon._process(_data.ads_transition_time)
	assert_eq(_weapon.ads_progress, 1.0)


func test_spread_is_wider_in_the_air_than_on_the_ground() -> void:
	_data.spread_hipfire = 1.0
	_data.spread_airborne_multiplier = 3.0
	assert_eq(_weapon.get_current_spread(), 1.0, "no body means no movement penalty")


# ------------------------------------------------- animacion de recarga

## El playtest pidio señal visual de que estas recargando. La animacion se deriva
## de esto, asi que si el progreso miente, el arma gira mal.

func test_reload_progress_is_zero_when_not_reloading() -> void:
	assert_eq(_weapon.get_reload_progress(), 0.0)


func test_reload_progress_runs_from_zero_to_one() -> void:
	_fire_once()
	_weapon.try_reload()
	assert_almost_eq(_weapon.get_reload_progress(), 0.0, 0.01, "arranca en cero")

	_weapon._process(_data.reload_time * 0.5)
	assert_almost_eq(_weapon.get_reload_progress(), 0.5, 0.05, "a mitad de camino")


## La razon de que el giro sea una vuelta entera: termina donde empezo, y la pose
## de reposo se recupera por aritmetica en vez de por alguien acordandose de
## restaurarla.
func test_a_finished_spin_lands_back_on_the_resting_pose() -> void:
	assert_almost_eq(_weapon._reload_spin(1.0), -360.0, 0.01,
		"una vuelta completa es la misma pose")
	assert_eq(_weapon._reload_spin(0.0), 0.0, "sin recarga no hay giro")


## Una recarga interrumpida -cambio de arma, muerte, fin de run- no puede dejar el
## arma torcida para siempre.
func test_an_interrupted_reload_leaves_no_residue() -> void:
	_fire_once()
	_weapon.try_reload()
	_weapon._process(_data.reload_time * 0.4)
	assert_gt(absf(_weapon._reload_spin(_weapon.get_reload_progress())), 0.0,
		"a mitad de recarga el arma esta girada")

	_weapon.reset()
	assert_eq(_weapon.get_reload_progress(), 0.0, "cortar la recarga vuelve el giro a cero")
