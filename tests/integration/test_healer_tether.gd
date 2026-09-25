extends GutTest
## Lo que hace legible al Healer: los haces hacia todo lo que cura, y el bono por
## cortarlos.
##
## El haz viejo mostraba uno solo -el mas lastimado- y no se apagaba nunca. Las
## dos cosas engañaban: la primera hacia parecer que el Healer sostenia a un
## enemigo cuando sostenia a cuatro, y la segunda dejaba una linea dibujada
## mientras no estaba pasando nada. Todo lo de abajo existe contra esos dos.

const ENEMY_SCENE: String = "res://scenes/enemies/enemy.tscn"
const RUSHER: String = "res://data/enemies/rusher.tres"
const HEALER: String = "res://data/enemies/healer.tres"

var _spawned: Array[Enemy] = []
var _player: Node3D = null


func before_each() -> void:
	_player = Node3D.new()
	_player.add_to_group(&"player")
	add_child(_player)
	_player.global_position = Vector3(40.0, 0.0, 0.0)
	KillBonusTracker.reset()


func after_each() -> void:
	for enemy: Enemy in _spawned:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_spawned.clear()
	if is_instance_valid(_player):
		_player.queue_free()
	_player = null
	KillBonusTracker.reset()
	ObjectPool.release_all()
	await wait_physics_frames(2)


func _spawn(path: String, at: Vector3) -> Enemy:
	var data: EnemyData = (load(path) as EnemyData).duplicate()
	var enemy: Enemy = load(ENEMY_SCENE).instantiate()
	add_child(enemy)
	await wait_physics_frames(1)
	enemy.setup(data, at)
	await wait_physics_frames(1)
	_spawned.append(enemy)
	return enemy


## Tres heridos alrededor de un Healer, ya curados una vez.
func _healer_with_patients(count: int) -> Enemy:
	var healer: Enemy = await _spawn(HEALER, Vector3.ZERO)
	for i: int in count:
		var ally: Enemy = await _spawn(RUSHER, Vector3(float(i + 1), 0.0, 0.0))
		ally.health.apply_damage(ally.health.max_health * 0.5)
	healer.heal_nearby_allies()
	await wait_physics_frames(1)
	return healer


# ----------------------------------------------------------------- los haces

func test_the_healer_draws_one_beam_per_patient() -> void:
	var healer: Enemy = await _healer_with_patients(3)
	assert_eq(healer.healer_tether.get_active_count(), 3,
		"tres heridos son tres haces, no uno al mas lastimado")


## El tope existe para que el Healer rodeado no sea una maraña. Que se respete
## importa tanto como que se dibujen: cinco lineas ya no señalan a nadie.
func test_the_beams_are_capped() -> void:
	var healer: Enemy = await _healer_with_patients(HealerTether.MAX_BEAMS + 2)
	assert_eq(healer.healer_tether.get_active_count(), HealerTether.MAX_BEAMS)


func test_an_archetype_that_does_not_heal_draws_nothing() -> void:
	var rusher: Enemy = await _spawn(RUSHER, Vector3.ZERO)
	assert_false(rusher.healer_tether.is_active())
	assert_false(rusher.healer_tether.visible,
		"y ni siquiera procesa: un Rusher no paga por el componente del Healer")


## Que se apaguen solos es la mitad del arreglo. Un haz que se queda dibujado
## deja de significar "esto esta pasando ahora".
func test_the_beams_die_out_when_the_healing_stops() -> void:
	var healer: Enemy = await _healer_with_patients(2)
	assert_true(healer.healer_tether.is_active(), "arranca prendido")
	await wait_seconds(HealerTether.FADE_TIME + 0.2)
	assert_false(healer.healer_tether.is_active(),
		"sin pulsos nuevos, la conexion se apaga")


## El cuerpo vuelve al pool y puede renacer como Rusher. Los haces son top_level
## -viven en coordenadas de mundo-, asi que quedarian dibujados sobre la arena.
func test_a_recycled_body_does_not_keep_the_beams() -> void:
	var healer: Enemy = await _healer_with_patients(2)
	assert_true(healer.healer_tether.is_active())
	healer._on_released()
	assert_false(healer.healer_tether.is_active())


# --------------------------------------------------------------- la prioridad

## Matar al Healer mientras trabaja es la unica decision de objetivo que el juego
## pide de verdad, asi que se paga.
func test_killing_a_working_healer_pays_priority() -> void:
	var seen: Array = []
	var handler := func(_reward: int, ids: Array, _total: int, _at: Vector3) -> void:
		seen.append(ids.duplicate())
	EventBus.kill_payout.connect(handler)
	EventBus.healed.emit(self, 10.0)
	EventBus.kill_scored.emit(&"healer", Vector3.ZERO, false, 20)
	EventBus.kill_payout.disconnect(handler)
	assert_true(seen[0].has(KillBonusTracker.BONUS_PRIORITY))


func test_a_healer_that_was_doing_nothing_pays_no_priority() -> void:
	var seen: Array = []
	var handler := func(_reward: int, ids: Array, _total: int, _at: Vector3) -> void:
		seen.append(ids.duplicate())
	EventBus.kill_payout.connect(handler)
	EventBus.kill_scored.emit(&"healer", Vector3.ZERO, false, 20)
	EventBus.kill_payout.disconnect(handler)
	assert_false(seen[0].has(KillBonusTracker.BONUS_PRIORITY),
		"sin cura reciente no corto nada")


func test_only_the_healer_pays_priority() -> void:
	var seen: Array = []
	var handler := func(_reward: int, ids: Array, _total: int, _at: Vector3) -> void:
		seen.append(ids.duplicate())
	EventBus.kill_payout.connect(handler)
	EventBus.healed.emit(self, 10.0)
	EventBus.kill_scored.emit(&"rusher", Vector3.ZERO, false, 10)
	EventBus.kill_payout.disconnect(handler)
	assert_false(seen[0].has(KillBonusTracker.BONUS_PRIORITY))
