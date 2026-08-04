extends Node
## Global signal hub. Declares signals only - zero logic, zero state.
## Anything that crosses system boundaries goes through here.

# Combat
signal damage_dealt(target: Node, amount: float, is_headshot: bool)
signal enemy_killed(enemy_type: StringName, position: Vector3, reward: int)
signal player_damaged(amount: float, remaining: float)
signal player_died()

# Weapons
signal weapon_fired(weapon_id: StringName)
signal weapon_reloaded(weapon_id: StringName)
signal ammo_changed(current: int, reserve: int)
signal weapon_switched(weapon_id: StringName)

# Movement
signal dash_used(charges_remaining: int)
signal grapple_started(anchor: Vector3)
signal grapple_ended()

# Waves
signal wave_started(wave_index: int, config: WaveData)
signal wave_completed(wave_index: int, duration: float, damage_taken: float)
signal match_completed(score: int, total_time: float)

# Economy
signal currency_changed(new_total: int)
signal purchase_made(item_id: StringName, cost: int)
signal shop_opened()
signal shop_closed()

# Match state
signal game_state_changed(new_state: int)
## Pause is not a game state - it can interrupt any of them and leaves the run
## intact - so it rides its own signal rather than widening the state enum.
signal game_paused(is_paused: bool)

# Settings
signal settings_applied()
