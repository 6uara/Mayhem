class_name UtilityComponent
extends Node
## The player's three utility slots: stun grenade, temporary wall, slow field.
## Limited carried count, purchasable, each on its own cooldown (CLAUDE.md 5.5).

signal utility_changed(slot: int, carried: int)
signal utility_used(slot: int, data: UtilityData)

const SLOT_COUNT: int = 3

@export var aim_node: Node3D
@export var body: CharacterBody3D
## Slot order matches utility_1 / utility_2 / utility_3.
@export var slots: Array[UtilityData] = []
@export var throw_sound: AudioStream

## Carried count per slot.
var _carried: Array[int] = []
var _cooldowns: Array[float] = []


func _ready() -> void:
	_carried.resize(SLOT_COUNT)
	_cooldowns.resize(SLOT_COUNT)
	_carried.fill(0)
	_cooldowns.fill(0.0)


func _process(delta: float) -> void:
	for i: int in SLOT_COUNT:
		if _cooldowns[i] > 0.0:
			_cooldowns[i] = maxf(_cooldowns[i] - delta, 0.0)


# Public API

func handle_input(event: InputEvent) -> bool:
	for i: int in SLOT_COUNT:
		if event.is_action_pressed("utility_%d" % (i + 1)):
			throw(i)
			return true
	return false


func throw(slot: int) -> bool:
	if not can_throw(slot):
		return false
	var data: UtilityData = slots[slot]
	var utility: Node = ObjectPool.acquire(data.scene)
	var thrown := utility as ThrownUtility
	if thrown == null:
		push_error("UtilityComponent: %s scene is not a ThrownUtility" % data.id)
		return false

	thrown.data = data
	var origin: Vector3 = aim_node.global_position - aim_node.global_transform.basis.z * 0.6
	# Thrown slightly above the aim line so a level throw still arcs.
	var direction: Vector3 = (-aim_node.global_transform.basis.z + Vector3.UP * 0.25).normalized()
	thrown.launch(origin, direction, body)

	_carried[slot] -= 1
	_cooldowns[slot] = data.cooldown
	AudioPool.play_3d(throw_sound, origin, AudioPool.BUS_WORLD)
	utility_changed.emit(slot, _carried[slot])
	utility_used.emit(slot, data)
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


func reset() -> void:
	_carried.fill(0)
	_cooldowns.fill(0.0)
	for i: int in SLOT_COUNT:
		utility_changed.emit(i, 0)
