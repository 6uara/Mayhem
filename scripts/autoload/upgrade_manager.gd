extends Node
## Owns purchased upgrades and aggregates their StatModifiers into live values.
## Contains no balance numbers - those live in UpgradeData resources.

signal upgrades_changed()

## upgrade id -> stack count
var _stacks: Dictionary = {}
## upgrade id -> UpgradeData
var _owned: Dictionary = {}
## upgrade id -> seconds remaining (temporary upgrades only)
var _temporary_remaining: Dictionary = {}


func _ready() -> void:
	EventBus.player_died.connect(reset)


func _process(delta: float) -> void:
	if _temporary_remaining.is_empty():
		return
	var expired: Array[StringName] = []
	for id: StringName in _temporary_remaining:
		var remaining: float = _temporary_remaining[id] - delta
		if remaining <= 0.0:
			expired.push_back(id)
		else:
			_temporary_remaining[id] = remaining
	for id: StringName in expired:
		_remove(id)
	if not expired.is_empty():
		upgrades_changed.emit()


# Public API

## Base value modified by every owned upgrade that touches `stat_key`.
func get_stat(stat_key: StringName, base_value: float) -> float:
	return aggregate(base_value, get_modifiers_for(stat_key))


func get_modifiers_for(stat_key: StringName) -> Array[StatModifier]:
	var result: Array[StatModifier] = []
	for id: StringName in _owned:
		var data: UpgradeData = _owned[id]
		var stacks: int = _stacks[id]
		for modifier: StatModifier in data.stat_modifiers:
			if modifier != null and modifier.stat_key == stat_key:
				for _i: int in stacks:
					result.push_back(modifier)
	return result


func add_upgrade(data: UpgradeData) -> bool:
	if data == null:
		push_error("UpgradeManager.add_upgrade: null data")
		return false
	if not can_add(data):
		return false
	_owned[data.id] = data
	_stacks[data.id] = int(_stacks.get(data.id, 0)) + 1
	if data.is_temporary:
		_temporary_remaining[data.id] = data.duration
	upgrades_changed.emit()
	return true


func can_add(data: UpgradeData) -> bool:
	if data == null:
		return false
	return get_stacks(data.id) < maxi(data.max_stacks, 1)


func get_stacks(id: StringName) -> int:
	return int(_stacks.get(id, 0))


func has_upgrade(id: StringName) -> bool:
	return get_stacks(id) > 0


func get_owned() -> Array[UpgradeData]:
	var result: Array[UpgradeData] = []
	for id: StringName in _owned:
		result.push_back(_owned[id])
	return result


## Seconds left on a temporary upgrade, or 0.0 if it is not active/temporary.
func get_temporary_remaining(id: StringName) -> float:
	return float(_temporary_remaining.get(id, 0.0))


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

func _remove(id: StringName) -> void:
	_temporary_remaining.erase(id)
	_stacks.erase(id)
	_owned.erase(id)
