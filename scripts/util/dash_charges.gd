class_name DashCharges
extends RefCounted
## Deadlock-model dash charges: each spent charge regenerates independently on its
## own cooldown, so burning both dashes does not double the wait for the first one.
## Pure logic, no nodes - unit tested in tests/unit/test_dash_charges.gd.

var _max_charges: int = 2
var _cooldown: float = 5.0
## One entry per spent charge: seconds until that charge returns.
var _recharging: Array[float] = []


func setup(max_charges: int, cooldown: float) -> void:
	_max_charges = maxi(max_charges, 1)
	_cooldown = maxf(cooldown, 0.05)
	_recharging.clear()


## Upgrades change these live; charges already regenerating keep their timers.
func set_max_charges(value: int) -> void:
	_max_charges = maxi(value, 1)
	while _recharging.size() > _max_charges:
		_recharging.pop_front()


func set_cooldown(value: float) -> void:
	_cooldown = maxf(value, 0.05)


func tick(delta: float) -> void:
	if _recharging.is_empty():
		return
	for i: int in range(_recharging.size() - 1, -1, -1):
		_recharging[i] -= delta
		if _recharging[i] <= 0.0:
			_recharging.remove_at(i)


func try_consume() -> bool:
	if get_available() <= 0:
		return false
	_recharging.push_back(_cooldown)
	return true


func get_available() -> int:
	return maxi(_max_charges - _recharging.size(), 0)


func get_max_charges() -> int:
	return _max_charges


## 0..1 progress of the charge that will return next, for HUD pips.
func get_next_charge_progress() -> float:
	if _recharging.is_empty():
		return 1.0
	var soonest: float = _recharging[0]
	for remaining: float in _recharging:
		soonest = minf(soonest, remaining)
	return 1.0 - clampf(soonest / _cooldown, 0.0, 1.0)


func refill() -> void:
	_recharging.clear()
