extends GutTest
## Lo que queda en el aire cuando muere un enemigo. Antes desaparecia entre dos
## cuadros y la kill no tenia nada en el mundo que la mostrara.

const BURST_SCENE: PackedScene = preload("res://scenes/vfx/enemy_death_burst.tscn")

var _burst: EnemyDeathBurst


func before_each() -> void:
	_burst = add_child_autofree(BURST_SCENE.instantiate())


func test_the_burst_takes_the_colour_of_the_enemy() -> void:
	_burst.play_at(Vector3.ZERO, Tokens.ENEMY_BOMBER, Tokens.DEATH_BURST_HEIGHT)
	assert_eq(_burst.flash.light_color, Tokens.ENEMY_BOMBER)
	assert_true(_burst.flash.visible, "el destello arranca prendido")
	var shard := _burst._shard_material.albedo_color
	assert_gt(shard.r, 1.0, "las esquirlas pasan el umbral del bloom")


func test_a_bigger_enemy_bursts_bigger() -> void:
	_burst.play_at(Vector3.ZERO, Tokens.ENEMY_ELITE, Tokens.DEATH_BURST_HEIGHT * 1.5)
	assert_almost_eq(_burst.scale.x, 1.5, 0.001)


func test_the_flash_goes_out_before_the_burst_ends() -> void:
	_burst.play_at(Vector3.ZERO, Tokens.ENEMY_RUSHER, Tokens.DEATH_BURST_HEIGHT)
	_burst._process(Tokens.DEATH_FLASH_TIME + 0.01)
	assert_false(_burst.flash.visible, "una luz apagada no se deja prendida en cero")


func test_two_bursts_do_not_share_their_colour() -> void:
	var other: EnemyDeathBurst = add_child_autofree(BURST_SCENE.instantiate())
	_burst.play_at(Vector3.ZERO, Tokens.ENEMY_RUSHER, 1.0)
	other.play_at(Vector3.ZERO, Tokens.ENEMY_BOMBER, 1.0)
	assert_ne(_burst._shard_material, other._shard_material)
	assert_ne(_burst._shard_material.albedo_color, other._shard_material.albedo_color)
