class_name WeaponHolder
extends Node3D
## Owns the player's currently equipped weapon and the swap into a new one.
##
## Every weapon the player can ever hold exists as a WeaponComponent child from
## the start; only one is ever equipped. Loadout design: the player carries one
## weapon at a time, and buying a new one from the shop *replaces* the current
## one rather than adding a fourth slot - see UpgradeManager's weapon-scoped
## upgrades for the other half of that: a replaced weapon's WEAPON-category
## upgrades stay behind with it rather than following the player to the new gun.
##
## A replaced weapon is not destroyed or reset - its WeaponComponent simply stops
## being `current`, keeping whatever ammo it had. Buying it back later (the shop
## offers any weapon that is not the one currently equipped, including a
## previously-owned one) re-equips that same node, ammo and all, and its old
## upgrades are still there waiting in UpgradeManager under its weapon id. This
## is a deliberate consequence of scoping upgrades by weapon id rather than
## erasing them on replacement - not something to special-case away.

signal weapon_changed(weapon: WeaponComponent)
## Fires whenever which weapon is equipped changes - a purchase replacing the
## current weapon, or re-equipping a previously-owned one. Named for the HUD's
## single-weapon display, which is the only thing left listening to it.
signal weapon_replaced()

## Time the swap takes. Firing is blocked for the duration.
@export var swap_time: float = 0.35

var current: WeaponComponent
var is_swapping: bool = false

var _weapons: Array[WeaponComponent] = []
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

## No weapon-switch input remains: with one weapon carried at a time there is
## nothing to cycle or select. Kept (rather than removed) because Player still
## calls it every input event; the weapon_next/prev/1..4 actions stay defined in
## the input map (remap screens list every action) but nothing consumes them.
func handle_input(_event: InputEvent) -> bool:
	return false


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


## Equips `weapon_id`, replacing whatever is currently equipped. Returns false if
## it is already equipped, so the shop can reject the purchase rather than
## charging twice for the same gun.
func acquire(weapon_id: StringName) -> bool:
	var weapon: WeaponComponent = find_by_id(weapon_id)
	if weapon == null or weapon == current:
		return false
	weapon_replaced.emit()
	start_swap(weapon)
	return true


## True only for the weapon currently equipped - not "ever owned". A previously
## equipped weapon is not owned in this sense; the shop may offer it again.
func owns(weapon_id: StringName) -> bool:
	return current != null and current.data != null and current.data.id == weapon_id


func find_by_id(weapon_id: StringName) -> WeaponComponent:
	for weapon: WeaponComponent in _weapons:
		if weapon.data != null and weapon.data.id == weapon_id:
			return weapon
	return null


func get_all() -> Array[WeaponComponent]:
	return _weapons.duplicate()


## Tops up the currently equipped weapon - what an ammo pickup grants. Only one
## weapon is ever equipped, so there is nothing left to distribute across.
func add_reserve_ammo_fraction(fraction: float) -> int:
	if current == null:
		return 0
	return current.add_reserve_ammo(int(round(float(current.get_reserve_max()) * fraction)))


func reset() -> void:
	if _weapons.is_empty():
		return
	for weapon: WeaponComponent in _weapons:
		weapon.reset()
	_equip(_weapons[0])
	weapon_replaced.emit()


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
