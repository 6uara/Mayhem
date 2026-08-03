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
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			_set_available(true)
		return

	_bob_time += delta
	if mesh != null:
		mesh.rotate_y(delta * 1.6)
		mesh.position.y = _rest_height + sin(_bob_time * 2.2) * 0.12


# Private

func _on_body_entered(body: Node3D) -> void:
	if not is_available or not body.is_in_group(&"player"):
		return
	var player := body as Player
	if player == null or player.weapon_holder == null:
		return

	var taken: int = player.weapon_holder.add_reserve_ammo_fraction(reserve_fraction)
	if taken <= 0:
		return  # Already full: leave the pickup for when it is actually needed.

	AudioPool.play_3d(pickup_sound, global_position, AudioPool.BUS_WORLD)
	collected.emit()
	_set_available(false)


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
