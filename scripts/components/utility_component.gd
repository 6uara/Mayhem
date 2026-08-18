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
## Names each throw this player makes, so the copies of it on other machines
## can be matched back to the one the host flew. Local counter: the pair of
## this component and the number is already unique, since the messages only
## ever travel on the thrower's own node.
var _next_throw_id: int = 0
## throw id -> the copy flying here, for a landing correction that arrives
## after it was thrown.
var _copies: Dictionary = {}


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
	var origin: Vector3 = aim_node.global_position - aim_node.global_transform.basis.z * 0.6
	# Thrown slightly above the aim line so a level throw still arcs.
	var direction: Vector3 = (-aim_node.global_transform.basis.z + Vector3.UP * 0.25).normalized()

	# The arc leaves your hand now, on your own machine, whatever the ping is -
	# a grenade that waits for a round trip is a grenade you stop trusting. On a
	# client that copy is for the eyes only; the throw that moves enemies is the
	# one the host flies from the same numbers a moment later.
	var throw_id: int = _next_throw_id
	_next_throw_id += 1
	if not _spawn_throw(data, origin, direction, not NetworkManager.is_host(), throw_id):
		return false

	_carried[slot] -= 1
	_cooldowns[slot] = data.cooldown
	AudioPool.play_3d(throw_sound, origin, AudioPool.BUS_WORLD)
	utility_changed.emit(slot, _carried[slot])
	utility_used.emit(slot, data)

	if not NetworkManager.is_online():
		return true
	if NetworkManager.is_host():
		# Everyone else gets a copy to watch. call_remote: ours is already flying.
		_receive_throw.rpc(slot, origin, direction, NetworkManager.SERVER_ID, throw_id)
	else:
		_request_throw.rpc_id(NetworkManager.SERVER_ID, slot, origin, direction, throw_id)
	return true


# Coop
#
# A throw is a request from wherever it was made and a fact once the host has
# flown it. The charge is spent locally either way: the pouch belongs to the
# player who threw it, and a host that could refuse a throw after the animation
# has played would be taking back something already spent.
#
# Both directions are any_peer with the sender checked by hand, for the same
# reason Player._report_downed is: this node lives under a player body whose
# authority is the client driving it, so an "authority" rpc here is one the host
# is not allowed to send - and the host is the machine that owns the enemies
# these utilities exist to stop.

@rpc("any_peer", "call_remote", "reliable")
func _request_throw(slot: int, origin: Vector3, direction: Vector3,
		throw_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	# The body this component hangs off is the one that threw it. A peer cannot
	# throw someone else's grenade.
	if body == null or body.name.to_int() != sender:
		return
	var data: UtilityData = _data_for(slot)
	if data == null:
		return
	# The host's copy is the real one: it is the only machine whose enemies are
	# not scenery.
	_spawn_throw(data, origin, direction, false, throw_id)
	_receive_throw.rpc(slot, origin, direction, sender, throw_id)


## Host -> everyone: somebody threw this, here is a copy to watch.
@rpc("any_peer", "call_remote", "reliable")
func _receive_throw(slot: int, origin: Vector3, direction: Vector3,
		thrower_id: int, throw_id: int) -> void:
	if multiplayer.get_remote_sender_id() != NetworkManager.SERVER_ID:
		return
	if thrower_id == NetworkManager.local_id():
		return  # We threw it. Our copy has been in the air since we pressed the key.
	var data: UtilityData = _data_for(slot)
	if data == null:
		return
	_spawn_throw(data, origin, direction, true, throw_id)


func _spawn_throw(data: UtilityData, origin: Vector3, direction: Vector3,
		cosmetic: bool, throw_id: int) -> bool:
	var thrown := ObjectPool.acquire(data.scene) as ThrownUtility
	if thrown == null:
		push_error("UtilityComponent: %s scene is not a ThrownUtility" % data.id)
		return false
	thrown.data = data
	thrown.is_cosmetic = cosmetic
	thrown.throw_id = throw_id
	thrown.thrower_utility = self
	thrown.launch(origin, direction, body)
	if cosmetic:
		_copies[throw_id] = thrown
	return true


## Host -> everyone: the throw came to rest here.
##
## Only the wall uses this, and only because it is the one utility whose exact
## position changes what a player can do: it is solid, and everyone has to be
## stopped by it in the same place. Each machine flies its own copy from the same
## origin and direction, but the arc is raycast against enemies too, and enemies
## are a few centimetres apart between peers - which is enough to drop a wall
## across a lane on one screen and beside it on another.
##
## A grenade needs none of this. It goes off, and where its flash was drawn is
## nobody's business but that machine's.
func broadcast_landing(throw_id: int, position: Vector3, yaw: float) -> void:
	if not NetworkManager.is_online() or not NetworkManager.is_host():
		return
	_receive_landing.rpc(throw_id, position, yaw)


@rpc("any_peer", "call_remote", "reliable")
func _receive_landing(throw_id: int, position: Vector3, yaw: float) -> void:
	if multiplayer.get_remote_sender_id() != NetworkManager.SERVER_ID:
		return
	var copy := _copies.get(throw_id) as ThrownUtility
	# Gone already, or the pool handed this slot to a later throw: either way
	# there is nothing here that still belongs to that one.
	if copy == null or not is_instance_valid(copy) or copy.throw_id != throw_id:
		_copies.erase(throw_id)
		return
	copy.snap_to_landing(position, yaw)
	_copies.erase(throw_id)


func _data_for(slot: int) -> UtilityData:
	if slot < 0 or slot >= slots.size():
		return null
	var data: UtilityData = slots[slot]
	return data if data != null and data.scene != null else null


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
