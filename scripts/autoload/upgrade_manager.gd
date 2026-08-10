extends Node
## Owns purchased upgrades and aggregates their StatModifiers into live values.
## Contains no balance numbers - those live in UpgradeData resources.
##
## Category.WEAPON upgrades are scoped to the weapon they were bought for (loadout
## design: buying a new weapon replaces the current one, and its upgrades stay
## behind with the weapon they were bought for rather than carrying to the new
## gun - see WeaponHolder). Category.MOBILITY and Category.SURVIVABILITY upgrades
## stay global, same as before this scoping existed.
##
## Every dictionary below is keyed by a "scope key", not the bare upgrade id:
## `_key()` returns "<id>::<weapon_id>" when a weapon_id is given, or the bare id
## otherwise. This is what lets the same upgrade resource (e.g. "magazine") be
## bought independently for two different weapons over the life of a run and
## stack separately for each, instead of one weapon's purchases silently maxing
## out or bleeding into another's.

signal upgrades_changed()

## scope key -> stack count
var _stacks: Dictionary = {}
## scope key -> UpgradeData
var _owned: Dictionary = {}
## scope key -> seconds remaining (temporary upgrades only)
var _temporary_remaining: Dictionary = {}


func _ready() -> void:
	EventBus.player_died.connect(reset)


func _process(delta: float) -> void:
	if _temporary_remaining.is_empty():
		return
	var expired: Array[StringName] = []
	for key: StringName in _temporary_remaining:
		var remaining: float = _temporary_remaining[key] - delta
		if remaining <= 0.0:
			expired.push_back(key)
		else:
			_temporary_remaining[key] = remaining
	for key: StringName in expired:
		_remove(key)
	if not expired.is_empty():
		upgrades_changed.emit()


# Public API

## Base value modified by every owned upgrade that touches `stat_key`. `weapon_id`
## scopes which weapon's WEAPON-category upgrades apply - global (MOBILITY,
## SURVIVABILITY) upgrades always apply regardless of what is passed here.
func get_stat(stat_key: StringName, base_value: float, weapon_id: StringName = &"") -> float:
	return aggregate(base_value, get_modifiers_for(stat_key, weapon_id))


func get_modifiers_for(stat_key: StringName, weapon_id: StringName = &"") -> Array[StatModifier]:
	var result: Array[StatModifier] = []
	for key: StringName in _owned:
		var data: UpgradeData = _owned[key]
		# A WEAPON-scoped upgrade only counts for the weapon it was bought for;
		# global (MOBILITY/SURVIVABILITY) upgrades are never scoped and always count.
		if data.category == UpgradeData.Category.WEAPON and _key(data.id, weapon_id) != key:
			continue
		var stacks: int = int(_stacks[key])
		for modifier: StatModifier in data.stat_modifiers:
			if modifier != null and modifier.stat_key == stat_key:
				for _i: int in stacks:
					result.push_back(modifier)
	return result


## `weapon_id` is required for `data.category == Category.WEAPON` - an unscoped
## weapon upgrade purchase is a programming error, not a valid global one.
func add_upgrade(data: UpgradeData, weapon_id: StringName = &"") -> bool:
	if data == null:
		push_error("UpgradeManager.add_upgrade: null data")
		return false
	if data.category == UpgradeData.Category.WEAPON and weapon_id == &"":
		push_error("UpgradeManager.add_upgrade: WEAPON upgrade '%s' needs a weapon_id" % data.id)
		return false
	if not can_add(data, weapon_id):
		return false
	var key: StringName = _key(data.id, weapon_id)
	_owned[key] = data
	_stacks[key] = int(_stacks.get(key, 0)) + 1
	if data.is_temporary:
		_temporary_remaining[key] = data.duration
	upgrades_changed.emit()
	return true


func can_add(data: UpgradeData, weapon_id: StringName = &"") -> bool:
	if data == null:
		return false
	return get_stacks(data.id, weapon_id) < maxi(data.max_stacks, 1)


## For a WEAPON-category upgrade, pass the weapon it was (or would be) bought for -
## an empty `weapon_id` reads the global (non-weapon) bucket, not "every weapon".
func get_stacks(id: StringName, weapon_id: StringName = &"") -> int:
	return int(_stacks.get(_key(id, weapon_id), 0))


func has_upgrade(id: StringName, weapon_id: StringName = &"") -> bool:
	return get_stacks(id, weapon_id) > 0


## One entry per distinct purchase - if the same upgrade was bought for two
## different weapons, it appears twice, once per scope.
func get_owned() -> Array[UpgradeData]:
	var result: Array[UpgradeData] = []
	for key: StringName in _owned:
		result.push_back(_owned[key])
	return result


## Seconds left on a temporary upgrade, or 0.0 if it is not active/temporary.
func get_temporary_remaining(id: StringName, weapon_id: StringName = &"") -> float:
	return float(_temporary_remaining.get(_key(id, weapon_id), 0.0))


func reset() -> void:
	_stacks.clear()
	_owned.clear()
	_temporary_remaining.clear()
	upgrades_changed.emit()


## Aggregation order is ALWAYS: base -> all ADD -> all MULTIPLY -> OVERRIDE.
## The last OVERRIDE in the list wins. Documented and unit tested; do not change.
static func aggregate(base_value: float, modifiers: Array[StatModifier]) -> float:
	var result: float = base_value
	var multiplier: float = 1.0
	var override_value: float = 0.0
	var has_override: bool = false

	for modifier: StatModifier in modifiers:
		if modifier == null:
			continue
		match modifier.operation:
			StatModifier.Operation.ADD:
				result += modifier.value
			StatModifier.Operation.MULTIPLY:
				multiplier *= modifier.value
			StatModifier.Operation.OVERRIDE:
				override_value = modifier.value
				has_override = true

	result *= multiplier
	if has_override:
		return override_value
	return result


# Private

## "<id>::<weapon_id>" when scoped to a weapon, or the bare id when not - see the
## class docstring.
func _key(id: StringName, weapon_id: StringName) -> StringName:
	return id if weapon_id == &"" else StringName("%s::%s" % [id, weapon_id])


func _remove(key: StringName) -> void:
	_temporary_remaining.erase(key)
	_stacks.erase(key)
	_owned.erase(key)
