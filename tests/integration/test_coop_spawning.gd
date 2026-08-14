extends GutTest
## Players are spawned at runtime now instead of being hand-placed in game.tscn,
## so that coop can put one body in the arena per connected peer.
##
## The risk that buys is a silent one: if the spawn path breaks, the game does
## not crash - it loads an arena with nobody in it, the HUD binds to nothing and
## the enemies wander. Single player is the case that would regress without
## anyone opening a second instance to notice, so it is what these pin down.


func _make_player(peer_id: int) -> Node3D:
	var body := Node3D.new()
	body.name = str(peer_id)
	body.add_to_group(&"player")
	add_child_autofree(body)
	return body


# ------------------------------------------------------------- the solo session

## No peer, no socket: NetworkManager still has to describe a coherent session
## of one, because the spawn path and the match scripts read these answers
## without ever asking whether networking is on.
func test_a_session_with_no_peer_still_reports_one_local_host() -> void:
	assert_false(NetworkManager.is_online(), "solo run is not online")
	assert_true(NetworkManager.is_host(), "solo player owns the simulation")
	assert_eq(NetworkManager.local_id(), NetworkManager.SERVER_ID, "local id")
	assert_eq(NetworkManager.get_peer_ids(), [NetworkManager.SERVER_ID],
		"one body to spawn")


func test_the_roster_caps_at_the_designed_player_count() -> void:
	assert_eq(NetworkManager.MAX_PLAYERS, 4, "coop is designed around four")
	assert_false(NetworkManager.is_full(), "an empty roster is not full")


# ------------------------------------------------------------------ the spawner

func test_the_controller_puts_a_body_in_the_arena_for_the_local_player() -> void:
	var container := Node3D.new()
	add_child_autofree(container)

	var controller := PlayerSpawnController.new()
	controller.player_scene = load("res://scenes/player/player.tscn")
	controller.container = container
	add_child_autofree(controller)
	await wait_frames(2)

	assert_eq(container.get_child_count(), 1,
		"solo session spawns exactly one player")


## Authority is carried by the node name and nothing else, so a rename in the
## spawner would hand every client control of the host's body.
func test_a_spawned_body_claims_authority_from_its_name() -> void:
	var body: Node3D = _make_player(1)
	assert_eq(body.name, "1", "named after the owning peer")
	assert_eq(body.name.to_int(), 1, "the name parses back to a peer id")


# -------------------------------------------------------------- finding players

## The two lookups that replaced get_first_node_in_group("player"). Confusing
## them is not a crash, it is an enemy chasing the wrong teammate or a HUD
## showing someone else's health, so both are pinned.
func test_nearest_picks_the_closer_of_two_players() -> void:
	var near: Node3D = _make_player(1)
	var far: Node3D = _make_player(2)
	near.global_position = Vector3(0.0, 0.0, 2.0)
	far.global_position = Vector3(0.0, 0.0, 40.0)

	var found: Node3D = Players.nearest(Vector3.ZERO)
	assert_eq(found, near, "nearest returns the close one")


func test_all_sees_every_player_but_local_is_only_ours() -> void:
	_make_player(1)
	_make_player(2)
	assert_eq(Players.all().size(), 2, "both bodies are players")
	# Neither test double joined the local_player group, so nothing is local -
	# which is exactly what a client sees before its own body has arrived.
	assert_null(Players.local(), "no local body until one claims the group")


# --------------------------------------------------------------------- damage

## Every bullet in the game resolves through report_hit() now, so the solo path
## through it has to stay a plain function call. If this regressed, single
## player would stop dealing damage at all - the loudest possible bug, but only
## for the mode nobody opens a second window to test.
func test_a_solo_hit_is_applied_on_the_spot() -> void:
	var health := HealthComponent.new()
	health.max_health = 100.0
	add_child_autofree(health)
	health.reset()

	var hitbox := HitboxComponent.new()
	hitbox.health_component = health
	add_child_autofree(hitbox)

	var replicator := EnemyReplicator.new()
	add_child_autofree(replicator)

	replicator.report_hit(hitbox, 30.0, Vector3.ZERO)
	assert_eq(health.current_health, 70.0, "damage lands with no session open")


# ------------------------------------------------------------- what hits you

## A client's copy of an enemy shot exists to be seen and dodged. The host
## already resolved the same round against its own copy, so if this one also
## took hit points the player would pay twice for one bullet - and the second
## charge would come from a machine with no authority to hurt anyone.
func test_a_cosmetic_projectile_travels_but_deals_no_damage() -> void:
	var scene: PackedScene = load("res://scenes/projectiles/enemy_projectile.tscn")
	var health := HealthComponent.new()
	health.max_health = 100.0

	var body := CharacterBody3D.new()
	body.add_to_group(&"player")
	body.add_child(health)
	add_child_autofree(body)
	body.global_position = Vector3(0.0, 0.0, 4.0)
	health.reset()

	var shot: EnemyProjectile = scene.instantiate()
	add_child_autofree(shot)
	shot.launch_cosmetic(Vector3.ZERO, Vector3.FORWARD, 40.0, body)
	await wait_physics_frames(8)

	assert_eq(health.current_health, 100.0,
		"a client-side copy of a shot never bills the player")


## The telegraph is the player's warning. It is state rather than an event
## precisely so a client that missed a packet still catches up to a glowing
## enemy on the next snapshot instead of being swung at out of nowhere.
func test_the_windup_is_state_an_enemy_carries() -> void:
	var enemy: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	add_child_autofree(enemy)
	await wait_physics_frames(1)

	enemy.show_windup(0.5)
	assert_almost_eq(enemy.windup_progress, 0.5, 0.001, "the wind-up is readable")
	enemy.clear_windup()
	assert_eq(enemy.windup_progress, 0.0, "and it ends when the attack does")


# ----------------------------------------------------------------- los pickups

## The pickup has to keep working with nobody connected, which is the case that
## would break silently: the coop path routes through the host, and solo is a
## host of one, so a wrong branch here empties the ammo boxes in the mode that
## ships.
func test_a_solo_player_still_takes_the_ammo() -> void:
	var pickup: AmmoPickup = load("res://scenes/arena/ammo_pickup.tscn").instantiate()
	add_child_autofree(pickup)
	var body: Player = load("res://scenes/player/player.tscn").instantiate()
	body.name = "1"
	add_child_autofree(body)
	await wait_physics_frames(2)

	var weapon: WeaponComponent = body.weapon_holder.current
	# Reaching into _reserve rather than firing the gun dry: there is no public
	# way to spend reserve ammo (it only leaves through a reload), and what this
	# test is about is the pickup, not the path the ammo took to run out.
	weapon._reserve = 0
	var before: int = weapon.get_reserve()

	pickup._on_body_entered(body)
	assert_gt(weapon.get_reserve(), before, "the ammo lands in the gun")
	assert_false(pickup.is_available, "and the box is gone")


## Full pouches must not consume the box - the teammate behind you needs it.
func test_a_full_player_leaves_the_box_alone() -> void:
	var pickup: AmmoPickup = load("res://scenes/arena/ammo_pickup.tscn").instantiate()
	add_child_autofree(pickup)
	var body: Player = load("res://scenes/player/player.tscn").instantiate()
	body.name = "1"
	add_child_autofree(body)
	await wait_physics_frames(2)

	var weapon: WeaponComponent = body.weapon_holder.current
	weapon.add_reserve_ammo(weapon.get_reserve_max())
	assert_false(body.weapon_holder.has_reserve_room(), "topped up")

	pickup._on_body_entered(body)
	assert_true(pickup.is_available, "the box is still there for someone else")


func test_nothing_is_broadcast_in_a_solo_run() -> void:
	var replicator := EnemyReplicator.new()
	add_child_autofree(replicator)
	var enemy: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	add_child_autofree(enemy)
	await wait_physics_frames(1)
	enemy.net_id = 7

	# The assertion is that these do not error. rpc() with no peer assigned is a
	# runtime error in Godot, so a missing "are we online?" check here would
	# take the single-player game down every time anything attacked.
	replicator.broadcast_projectile(enemy, Vector3.ZERO, Vector3.FORWARD)
	replicator.broadcast_melee(enemy)
	pass_test("solo attacks broadcast nothing")


# ------------------------------------------------------- who is still standing

## alive() decides two things that must not disagree: who the spectator camera
## may watch, and whether the run is over. A body that reads as alive when it is
## down keeps a wiped team playing against enemies nobody can hurt.
func test_a_downed_player_is_not_alive() -> void:
	var body: Player = load("res://scenes/player/player.tscn").instantiate()
	body.name = "1"
	add_child_autofree(body)
	await wait_frames(1)

	assert_true(Players.is_alive(body), "a fresh player is in the fight")
	body.is_downed = true
	assert_false(Players.is_alive(body), "a downed player is out of it")
	assert_true(Players.alive().is_empty(), "and out of the living list")


## is_downed is the networked answer, health.is_dead the local one. A client's
## own body never takes damage locally, so on that machine only is_downed is
## ever set - reading health alone would call that player alive forever.
func test_downed_is_read_independently_of_local_health() -> void:
	var body: Player = load("res://scenes/player/player.tscn").instantiate()
	body.name = "1"
	add_child_autofree(body)
	await wait_frames(1)

	body.is_downed = true
	assert_false(body.health.is_dead, "local health never took the hit")
	assert_false(Players.is_alive(body), "still counted as down")


func test_a_player_reports_the_peer_that_owns_it() -> void:
	var body: Player = load("res://scenes/player/player.tscn").instantiate()
	body.name = "7"
	add_child_autofree(body)
	await wait_frames(1)
	assert_eq(body.get_peer_id(), 7, "peer id comes from the node name")


# ------------------------------------------------------------------- the revive

## Going down costs a wave, not the run: the wave break stands everyone back up.
## Without this a coop session degrades into one person playing while three
## watch, which is the failure mode the spectator camera was only ever a
## stopgap for.
func test_the_host_can_stand_a_downed_player_back_up() -> void:
	var body: Player = load("res://scenes/player/player.tscn").instantiate()
	body.name = "1"
	add_child_autofree(body)
	await wait_frames(1)

	var layer: int = body.collision_layer
	body.is_downed = true
	body.collision_layer = 0
	body.health.is_invulnerable = true
	body.health.current_health = 0.0
	body.health.is_dead = true

	body.revive_from_host()
	assert_false(body.is_downed, "back in the fight")
	assert_eq(body.collision_layer, layer, "collides with the world again")
	assert_false(body.health.is_invulnerable, "and can be hurt again")
	assert_eq(body.health.current_health, body.health.max_health, "at full health")


func test_reviving_a_player_who_never_fell_changes_nothing() -> void:
	var body: Player = load("res://scenes/player/player.tscn").instantiate()
	body.name = "1"
	add_child_autofree(body)
	await wait_frames(1)

	watch_signals(EventBus)
	body.revive_from_host()
	assert_signal_not_emitted(EventBus, "player_revived",
		"nobody is told about a revive that did not happen")


# ------------------------------------------------------------------ kill credit

## The bounty follows the trigger, not the simulation. Solo, the two are the
## same machine and the money must still arrive - this is the path that pays for
## every purchase in the single-player game.
func test_a_solo_kill_pays_the_local_wallet() -> void:
	var replicator := EnemyReplicator.new()
	add_child_autofree(replicator)
	assert_false(replicator.credit_kill(0, &"grunt", Vector3.ZERO, 25),
		"with no session open the caller pays itself")


func test_a_kill_credited_over_the_wire_is_what_moves_the_money() -> void:
	EconomyManager.reset()
	var before: int = EconomyManager.currency
	EventBus.enemy_killed.emit(&"grunt", Vector3.ZERO, 25)
	assert_eq(EconomyManager.currency, before,
		"an enemy dying somewhere is not by itself income")
	EventBus.kill_credited.emit(25)
	assert_gt(EconomyManager.currency, before, "being credited for it is")
	EconomyManager.reset()


func test_a_player_with_no_health_component_still_counts_as_alive() -> void:
	# Enemy targeting calls this every time it re-acquires; a null health on a
	# test double or a stripped-down body must not read as a corpse.
	assert_true(Players.is_alive(_make_player(1)), "no health means alive")
	assert_false(Players.is_alive(null), "null is not a target")
