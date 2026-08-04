class_name WeaponHolder
extends Node3D
## Owns the player's weapons and handles switching between them.
##
## Every weapon the player can own exists as a WeaponComponent child from the start;
## owning one just enables it. That keeps per-weapon ammo persistent across switches
## and shop visits without any save/restore dance.

signal weapon_changed(weapon: WeaponComponent)
signal owned_weapons_changed()

## Time the swap takes. Firing is blocked for the duration.
@export var swap_time: float = 0.35

var current: WeaponComponent
var is_swapping: bool = false

var _weapons: Array[WeaponComponent] = []
var _owned: Array[WeaponComponent] = []
var _swap_timer: float = 0.0
var _pending: WeaponComponent


func _ready() -> void:
	for child: Node in get_children():
		var weapon := child as WeaponComponent
		if weapon != null:
			_weapons.push_back(weapon)
			weapon.visible = false
			weapon.set_process(false)
	if _weapons.is_empty():
		push_warning("WeaponHolder on %s has no WeaponComponent children" % get_path())
		return
	# The pistol is the starting weapon (CLAUDE.md 5.1): backup, generous ammo.
	_owned.push_back(_weapons[0])
	_equip(_weapons[0])


func _process(delta: float) -> void:
	if not is_swapping:
		return
	_swap_timer -= delta
	if _swap_timer <= 0.0:
		is_swapping = false
		_equip(_pending)
		_pending = null


# Public API

func handle_input(event: InputEvent) -> bool:
	if event.is_action_pressed("weapon_next"):
		cycle(1)
		return true
	if event.is_action_pressed("weapon_prev"):
		cycle(-1)
		return true
	for i: int in 4:
		if event.is_action_pressed("weapon_%d" % (i + 1)):
			select_slot(i)
			return true
	return false


func select_slot(index: int) -> void:
	if index < 0 or index >= _weapons.size():
		return
	var weapon: WeaponComponent = _weapons[index]
	if not _owned.has(weapon):
		return
	start_swap(weapon)


func cycle(direction: int) -> void:
	if _owned.size() <= 1:
		return
	var index: int = _owned.find(current)
	if index < 0:
		index = 0
	start_swap(_owned[wrapi(index + direction, 0, _owned.size())])


func start_swap(weapon: WeaponComponent) -> void:
	if weapon == null or weapon == current or is_swapping:
		return
	# Dropping the trigger on swap stops a held fire input carrying over.
	if current != null:
		current.set_trigger(false)
		current.set_ads(false)
	_pending = weapon
	is_swapping = true
	_swap_timer = swap_time


## Grants a weapon. Returns false if it was already owned, so the shop can reject
## the purchase rather than charging twice for the same gun.
func acquire(weapon_id: StringName) -> bool:
	var weapon: WeaponComponent = find_by_id(weapon_id)
	if weapon == null or _owned.has(weapon):
		return false
	_owned.push_back(weapon)
	owned_weapons_changed.emit()
	start_swap(weapon)
	return true


func owns(weapon_id: StringName) -> bool:
	var weapon: WeaponComponent = find_by_id(weapon_id)
	return weapon != null and _owned.has(weapon)


func find_by_id(weapon_id: StringName) -> WeaponComponent:
	for weapon: WeaponComponent in _weapons:
		if weapon.data != null and weapon.data.id == weapon_id:
			return weapon
	return null


func get_owned() -> Array[WeaponComponent]:
	return _owned.duplicate()


func get_all() -> Array[WeaponComponent]:
	return _weapons.duplicate()


## Tops up every owned weapon - what an ammo pickup grants.
func add_reserve_ammo_fraction(fraction: float) -> int:
	var total: int = 0
	for weapon: WeaponComponent in _owned:
		total += weapon.add_reserve_ammo(
			int(round(float(weapon.get_reserve_max()) * fraction)))
	return total


func reset() -> void:
	_owned.clear()
	if _weapons.is_empty():
		return
	_owned.push_back(_weapons[0])
	for weapon: WeaponComponent in _weapons:
		weapon.reset()
	_equip(_weapons[0])
	owned_weapons_changed.emit()


# Private

func _equip(weapon: WeaponComponent) -> void:
	if weapon == null:
		return
	for other: WeaponComponent in _weapons:
		var is_current: bool = other == weapon
		other.visible = is_current
		other.set_process(is_current)
	current = weapon
	current.notify_equipped()
	weapon_changed.emit(current)
	EventBus.weapon_switched.emit(current.data.id if current.data != null else &"")
