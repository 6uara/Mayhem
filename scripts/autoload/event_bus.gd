extends Node
## Global signal hub. Declares signals only - zero logic, zero state.
## Anything that crosses system boundaries goes through here.

# Combat
signal damage_dealt(target: Node, amount: float, is_headshot: bool)
signal enemy_killed(enemy_type: StringName, position: Vector3, reward: int)
signal player_damaged(amount: float, remaining: float)
signal player_died()
## A kill this machine's player is being paid for.
##
## Split off from enemy_killed because the two answer different questions once
## there is more than one player. enemy_killed means "an enemy died" and drives
## everything that reacts to that - the wave count, the announcer, kill feel.
## This one means "and you get the money", which is true on exactly one machine
## per kill: the host resolves every death, but the bounty follows whoever was
## shooting. Paying off enemy_killed instead handed the host the whole arena's
## income and left the clients broke in front of the shop.
signal kill_credited(reward: int)

# Weapons
signal weapon_fired(weapon_id: StringName)
signal weapon_reloaded(weapon_id: StringName)
signal ammo_changed(current: int, reserve: int)
signal weapon_switched(weapon_id: StringName)
## The equipped weapon's ADS state, whichever weapon that is - a global hook so
## listeners (TutorialHintManager) don't have to re-subscribe to each
## WeaponComponent's own local ads_changed on every swap.
signal weapon_ads_changed(is_ads: bool)

# Movement
signal dash_used(charges_remaining: int)
## El charco de atrapado agarró al jugador, o lo soltó.
##
## Existe porque estar atrapado no se veía ni se oía: `apply_snare()` bajaba la
## velocidad y nada más, así que el jugador no tenía cómo saber **por qué** estaba
## lento - y sin eso la salida que el charco tiene (dash o gancho) no se le ocurre
## a nadie, y el sistema entero se lee como que el juego se trabó.
signal player_snared(multiplier: float)
## `was_broken` distingue las dos salidas: romperlo a propósito (dash o gancho) o
## simplemente haberse ido caminando. Sólo la primera enseña algo.
signal player_snare_ended(was_broken: bool)
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

# Player lifecycle
## The player entered the arena. Everything that binds to "the player" waits on
## this rather than looking it up at _ready(): the body is spawned by
## PlayerSpawnController, a frame or two after the scene itself is up.
signal local_player_spawned(player: Node3D)

# Settings
signal settings_applied()
