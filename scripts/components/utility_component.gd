class_name UtilityComponent
extends Node
## The player's three utility slots: stun grenade, temporary wall, slow field.
## Limited carried count, purchasable, each on its own cooldown (CLAUDE.md 5.5).

signal utility_changed(slot: int, carried: int)
signal utility_used(slot: int, data: UtilityData)
## Que gadget quedo en la mano, o -1 si ninguno. Solo se mueve en modo equipar;
## en quick cast nunca hay nada equipado porque el gadget sale en el acto.
signal armed_changed(slot: int)

const SLOT_COUNT: int = 3
## Setting que elige entre los dos esquemas. Ver handle_input().
const QUICK_CAST_KEY: String = "input/gadget_quick_cast"

@export var aim_node: Node3D
@export var body: CharacterBody3D
## Slot order matches utility_1 / utility_2 / utility_3.
@export var slots: Array[UtilityData] = []
@export var throw_sound: AudioStream

## Slot equipado esperando a que el jugador decida cuando lanzarlo, -1 si
## ninguno. Siempre -1 en quick cast.
var armed_slot: int = -1

## Carried count per slot.
var _carried: Array[int] = []
var _cooldowns: Array[float] = []


func _ready() -> void:
	_carried.resize(SLOT_COUNT)
	_cooldowns.resize(SLOT_COUNT)
	_carried.fill(0)
	_cooldowns.fill(0.0)
	# Un gadget en la mano cuando se abre la pausa no puede seguir ahi al volver:
	# el jugador solto el control en el medio y no se acuerda de que lo tenia.
	EventBus.game_paused.connect(_on_game_paused)


func _process(delta: float) -> void:
	for i: int in SLOT_COUNT:
		if _cooldowns[i] > 0.0:
			_cooldowns[i] = maxf(_cooldowns[i] - delta, 0.0)


# Public API

## Los dos esquemas que pidio el playtest, elegidos por setting.
##
## Quick cast: apretar el boton lanza. Rapido, y lo que se paga es no poder
## apuntar - el gadget sale hacia donde estabas mirando cuando lo pensaste.
##
## Equipar: la primera pulsacion se lo pone en la mano y el jugador decide
## cuando soltarlo con el disparo, apretando la misma tecla de nuevo para
## guardarlo. Mas lento y mas preciso.
##
## Ninguno de los dos es el correcto para todo el mundo, y por eso es una opcion
## y no una decision de diseño: son dos formas distintas de jugar el mismo
## gadget, no una mejor que la otra.
func handle_input(event: InputEvent) -> bool:
	if is_quick_cast():
		for i: int in SLOT_COUNT:
			if event.is_action_pressed("utility_%d" % (i + 1)):
				throw(i)
				return true
		return false

	for i: int in SLOT_COUNT:
		if event.is_action_pressed("utility_%d" % (i + 1)):
			# La misma tecla guarda lo que ya esta en la mano: sin eso, equipar
			# por error es un estado del que no se puede salir.
			if armed_slot == i:
				disarm()
			else:
				arm(i)
			return true

	# El disparo lanza lo que este equipado, y se consume aca: el arma no puede
	# disparar en el mismo evento con el que soltaste una granada.
	if armed_slot >= 0 and event.is_action_pressed("fire"):
		var slot: int = armed_slot
		disarm()
		throw(slot)
		return true
	return false


func is_quick_cast() -> bool:
	return bool(SettingsManager.get_value(QUICK_CAST_KEY, true))


## Pone un gadget en la mano. No consume carga ni cooldown - equipar no es usar,
## y guardarlo sin lanzarlo tiene que salir gratis.
func arm(slot: int) -> bool:
	if not can_throw(slot):
		return false
	if armed_slot == slot:
		return true
	armed_slot = slot
	armed_changed.emit(armed_slot)
	return true


func disarm() -> void:
	if armed_slot < 0:
		return
	armed_slot = -1
	armed_changed.emit(armed_slot)


func throw(slot: int) -> bool:
	if not can_throw(slot):
		return false
	var data: UtilityData = slots[slot]
	var origin: Vector3 = aim_node.global_position - aim_node.global_transform.basis.z * 0.6
	# Thrown slightly above the aim line so a level throw still arcs.
	var direction: Vector3 = (-aim_node.global_transform.basis.z + Vector3.UP * 0.25).normalized()

	if not _spawn_throw(data, origin, direction):
		return false

	_carried[slot] -= 1
	_cooldowns[slot] = data.cooldown
	AudioPool.play_3d(throw_sound, origin, AudioPool.BUS_WORLD)
	utility_changed.emit(slot, _carried[slot])
	utility_used.emit(slot, data)
	return true


func _spawn_throw(data: UtilityData, origin: Vector3, direction: Vector3) -> bool:
	var thrown := ObjectPool.acquire(data.scene) as ThrownUtility
	if thrown == null:
		push_error("UtilityComponent: %s scene is not a ThrownUtility" % data.id)
		return false
	thrown.data = data
	thrown.launch(origin, direction, body)
	return true


func can_throw(slot: int) -> bool:
	if slot < 0 or slot >= SLOT_COUNT or slot >= slots.size():
		return false
	var data: UtilityData = slots[slot]
	if data == null or data.scene == null:
		return false
	return _carried[slot] > 0 and _cooldowns[slot] <= 0.0 and aim_node != null


## Buying a utility adds one to its slot, up to `max_carried`. Returns false when
## full so the shop can refuse the sale instead of taking the money.
func add_charge(utility_id: StringName, amount: int = 1) -> bool:
	var slot: int = find_slot(utility_id)
	if slot < 0:
		return false
	var data: UtilityData = slots[slot]
	if _carried[slot] >= data.max_carried:
		return false
	_carried[slot] = mini(_carried[slot] + amount, data.max_carried)
	utility_changed.emit(slot, _carried[slot])
	return true


func find_slot(utility_id: StringName) -> int:
	for i: int in mini(slots.size(), SLOT_COUNT):
		if slots[i] != null and slots[i].id == utility_id:
			return i
	return -1


func get_carried(slot: int) -> int:
	if slot < 0 or slot >= _carried.size():
		return 0
	return _carried[slot]


func get_cooldown_fraction(slot: int) -> float:
	if slot < 0 or slot >= _cooldowns.size() or slots[slot] == null:
		return 0.0
	var cooldown: float = maxf(slots[slot].cooldown, 0.01)
	return clampf(_cooldowns[slot] / cooldown, 0.0, 1.0)


func get_slot_data(slot: int) -> UtilityData:
	if slot < 0 or slot >= slots.size():
		return null
	return slots[slot]


func _on_game_paused(_paused: bool) -> void:
	disarm()


func reset() -> void:
	disarm()
	_carried.fill(0)
	_cooldowns.fill(0.0)
	for i: int in SLOT_COUNT:
		utility_changed.emit(i, 0)
