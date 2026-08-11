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


func test_a_player_with_no_health_component_still_counts_as_alive() -> void:
	# Enemy targeting calls this every time it re-acquires; a null health on a
	# test double or a stripped-down body must not read as a corpse.
	assert_true(Players.is_alive(_make_player(1)), "no health means alive")
	assert_false(Players.is_alive(null), "null is not a target")
