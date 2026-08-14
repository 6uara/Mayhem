class_name AmmoPickup
extends Area3D
## Reserve ammo, sitting somewhere spatially risky.
##
## This is a deliberate design pressure (CLAUDE.md 5.1): limited reserve forces the
## player to move and take positional risk, which feeds the mobility pillar. So the
## pickup is loud - it spins, bobs, glows and can be heard from a distance.

signal collected()

## Fraction of each owned weapon's reserve capacity granted.
@export var reserve_fraction: float = 0.25
@export var respawn_time: float = 20.0
@export var mesh: Node3D
@export var light: OmniLight3D
@export var pickup_sound: AudioStream
@export var idle_sound: AudioStream
## How far the hum carries. Ammo must be audible before it is visible.
@export var idle_audible_range: float = 26.0

var is_available: bool = true

var _respawn_left: float = 0.0
var _bob_time: float = 0.0
var _rest_height: float = 0.0
var _idle_player: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group(&"ammo_pickup")
	body_entered.connect(_on_body_entered)
	if mesh != null:
		_rest_height = mesh.position.y
		# Amber and circular, always - amber only ever means 'the house': money,
		# pickups and the Host.
		var material := StandardMaterial3D.new()
		material.albedo_color = Tokens.WORLD_PICKUP
		material.emission_enabled = true
		material.emission = Tokens.WORLD_PICKUP
		material.emission_energy_multiplier = 1.4
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override = material
	if light != null:
		light.light_color = Tokens.WORLD_PICKUP
	_start_idle_sound()


func _process(delta: float) -> void:
	if not is_available:
		# The host owns the respawn clock. Left to run on every peer it drifts:
		# each machine starts counting when its own copy was taken, and a pickup
		# that is back on one screen and still gone on another is worse than one
		# that comes back a few frames late everywhere.
		if not NetworkManager.is_host():
			return
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			_announce_available(true)
		return

	_bob_time += delta
	if mesh != null:
		mesh.rotate_y(delta * 1.6)
		mesh.position.y = _rest_height + sin(_bob_time * 2.2) * 0.12


# Private

## Only ever reacts to the body this machine drives.
##
## A teammate walking over a pickup trips this on every peer, and reserve ammo
## lives on the machine that owns the gun - the host topping up its copy of a
## client's weapon would be filling a magazine nobody is holding. Whoever
## touched it asks for it from their own machine, and everyone else finds out
## the pickup is gone.
func _on_body_entered(body: Node3D) -> void:
	if not is_available or not body.is_in_group(&"player"):
		return
	var player := body as Player
	if player == null or player.weapon_holder == null or not player.is_local():
		return
	# Asked before claiming rather than after: a player with full pouches must
	# not take a pickup away from the teammate two steps behind them.
	if not player.weapon_holder.has_reserve_room():
		return

	# Solo is the host branch: a session of one, taking the pickup from itself.
	if NetworkManager.is_host():
		_claim_for(NetworkManager.SERVER_ID)
		return
	# The ammo is not granted here and now. It arrives with the host's answer,
	# which is what stops two players a ping apart both walking away with the
	# same box - the second one is told the box is already gone.
	_request_claim.rpc_id(NetworkManager.SERVER_ID)


# Coop
#
# The pickup is host-owned state: whether it is there, and who got it. Only the
# grant itself happens on the claimant's machine, because that is where its
# weapon's ammo actually lives.

@rpc("any_peer", "call_remote", "reliable")
func _request_claim() -> void:
	if not multiplayer.is_server():
		return
	_claim_for(multiplayer.get_remote_sender_id())


## Host: hand the pickup to one peer and tell everyone it is gone.
func _claim_for(peer_id: int) -> void:
	if not is_available:
		return  # Someone else got here first. Their claim already went out.
	_announce_available(false)
	if peer_id == NetworkManager.SERVER_ID:
		var player := Players.local() as Player
		if player != null:
			_grant_to(player)
		return
	_receive_grant.rpc_id(peer_id)


@rpc("authority", "call_remote", "reliable")
func _receive_grant() -> void:
	var player := Players.local() as Player
	if player != null:
		_grant_to(player)


@rpc("authority", "call_local", "reliable")
func _receive_available(available: bool) -> void:
	_set_available(available)


func _announce_available(available: bool) -> void:
	if NetworkManager.is_online():
		_receive_available.rpc(available)
		return
	_set_available(available)


func _grant_to(player: Player) -> void:
	if player.weapon_holder == null:
		return
	player.weapon_holder.add_reserve_ammo_fraction(reserve_fraction)
	AudioPool.play_3d(pickup_sound, global_position, AudioPool.BUS_WORLD)
	collected.emit()


func _set_available(available: bool) -> void:
	is_available = available
	_respawn_left = respawn_time if not available else 0.0
	if mesh != null:
		mesh.visible = available
	if light != null:
		light.visible = available
	if _idle_player != null and is_instance_valid(_idle_player):
		if available:
			_idle_player.play()
		else:
			_idle_player.stop()


## A dedicated looping player rather than an AudioPool voice - this one has to
## persist, and the pool is for one-shots.
func _start_idle_sound() -> void:
	if idle_sound == null:
		return
	_idle_player = AudioStreamPlayer3D.new()
	_idle_player.stream = idle_sound
	_idle_player.bus = String(AudioPool.BUS_WORLD)
	_idle_player.max_distance = idle_audible_range
	_idle_player.unit_size = 8.0
	_idle_player.volume_db = -6.0
	add_child(_idle_player)
	_idle_player.finished.connect(func() -> void:
		if is_available:
			_idle_player.play())
	_idle_player.play()
