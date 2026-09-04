@tool
class_name CurveEvaluator
extends RefCounted
## Projects what a run pays out, wave by wave, from the tuning values alone.
##
## The whole point of the balance editor: the numbers in the inspector say what a
## rusher is worth, and this says what that means for the player's wallet on wave
## seven, which is the question a designer actually has.


class WavePayout extends RefCounted:
	var wave_index: int = 0
	var kills: int = 0
	## Kill money only.
	var kill_income: int = 0
	## Completion, speed and no-damage bonuses.
	var bonus_income: int = 0
	var total_income: int = 0
	## Money the player is holding after this wave, before shopping.
	var cumulative: int = 0


## One entry per wave. `skill` is how well the projected player performs: 1.0
## clears at the fastest bonus tier and takes no damage, 0.0 earns neither.
static func project(waves: Array, config: EconomyConfig, skill: float = 0.75) -> Array:
	var payouts: Array = []
	if config == null:
		return payouts
	var running: int = config.starting_currency
	for wave: Variant in waves:
		var wave_data := wave as WaveData
		if wave_data == null:
			continue
		var payout := WavePayout.new()
		payout.wave_index = wave_data.wave_index
		payout.kills = wave_data.get_total_enemy_count()
		payout.kill_income = _kill_income(wave_data, config)
		payout.bonus_income = _bonus_income(wave_data, config, skill)
		payout.total_income = payout.kill_income + payout.bonus_income
		running += payout.total_income
		payout.cumulative = running
		payouts.append(payout)
	return payouts


## Cumulative money per wave, ready to plot against a price line.
static func cumulative_series(waves: Array, config: EconomyConfig,
		skill: float = 0.75) -> PackedInt32Array:
	var series := PackedInt32Array()
	for payout: WavePayout in project(waves, config, skill):
		series.append(payout.cumulative)
	return series


## The cheapest-to-dearest price ladder of everything on sale, so the curve can
## be read as "by wave N the player can afford the third-tier gun".
static func price_ladder(catalog: ShopCatalog) -> PackedInt32Array:
	var prices := PackedInt32Array()
	if catalog == null:
		return prices
	for price: int in catalog.weapon_prices:
		prices.append(price)
	for upgrade: Variant in catalog.upgrades:
		var cost: Variant = upgrade.get(&"cost") if upgrade != null else null
		if cost != null:
			prices.append(int(cost))
	# Los gadgets ya no estan en la escalera: salieron del shop cuando pasaron a
	# caer de las gradas, y una escalera de precios que incluye cosas que no se
	# venden dice que hace falta menos plata de la que hace falta.
	var sortable: Array = []
	for price: int in prices:
		sortable.append(price)
	sortable.sort()
	var out := PackedInt32Array()
	for price: Variant in sortable:
		out.append(int(price))
	return out


# Private

static func _kill_income(wave: WaveData, config: EconomyConfig) -> int:
	var total: int = 0
	for group: SpawnGroup in wave.spawn_groups:
		if group == null or group.enemy_data == null:
			continue
		total += config.get_kill_reward(group.enemy_data.archetype) * group.count
	return int(round(float(total) * config.currency_multiplier))


static func _bonus_income(wave: WaveData, config: EconomyConfig, skill: float) -> int:
	var total: int = wave.completion_bonus
	var clamped: float = clampf(skill, 0.0, 1.0)
	# A perfect run clears at the tightest tier; a poor one misses every tier.
	var duration: float = wave.par_time * lerpf(1.4, 0.4, clamped)
	total += config.get_speed_bonus(duration, wave.par_time)
	total += int(round(float(config.no_damage_bonus) * clamped))
	return int(round(float(total) * config.currency_multiplier))
