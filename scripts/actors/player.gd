class_name Player
extends CharacterBody3D
## First-person player root: look and weapon input only. All movement physics,
## including jump, lives in MovementComponent; grappling in GrappleComponent.

const MAX_PITCH_DEGREES: float = 89.0

## Degrees of extra FOV per m/s of ground speed above the base run.
const SPEED_FOV_PER_UNIT: float = 1.1
const SPEED_FOV_MAX: float = 12.0
const SPEED_FOV_BLEND: float = 5.0

@export_group("Nodes")
@export var head: Node3D
@export var camera: Camera3D
@export var weapon_holder: WeaponHolder
@export var recoil: CameraRecoilComponent
@export var health: HealthComponent
@export var stats: StatsComponent
@export var movement: MovementComponent
@export var grapple: GrappleComponent
@export var utility: UtilityComponent

## The equipped weapon. Everything that used to read `player.weapon` still can;
## the holder owns which one that is.
var weapon: WeaponComponent:
	get:
		return weapon_holder.current if weapon_holder != null else null

## Out of the fight. Set on every peer at once by _report_downed(), so a body
## that is down is down on all of them - teammates never see a corpse still
## running around, and the host never keeps aiming enemies at it.
var is_downed: bool = false

var _look_yaw: float = 0.0
var _look_pitch: float = 0.0
var _base_fov: float = 95.0
var _base_max_health: float = 100.0
var _speed_fov: float = 0.0


## Authority is read off the node name, which the spawner sets to the owning peer
## id. Claiming it here rather than in _ready() means it is already correct when
## the components' own _ready() runs and they ask whether they should simulate.
func _enter_tree() -> void:
	var owner_id: int = name.to_int()
	if owner_id > 0:
		set_multiplayer_authority(owner_id)
		# ...but not over our own health. set_multiplayer_authority() is
		# recursive, so it just handed the owning client the right to declare
		# its own hit points, and the enemies that do the damage are simulated
		# on the host. Handing this one node back is what keeps damage a thing
		# that happens *to* a player rather than something they report.
		var health_sync := get_node_or_null("HealthSync")
		if health_sync != null:
			health_sync.set_multiplayer_authority(NetworkManager.SERVER_ID)


func _ready() -> void:
	add_to_group(&"player")
	# One player per session answers true here. Everything that used to mean
	# "the player" - HUD binding, the reticle, mouse capture - means this one,
	# and remote bodies are just other actors in the world.
	if is_local():
		add_to_group(&"local_player")
	# Enemy projectiles raycast straight onto this body (no HitboxComponent on
	# the player) - tag it flesh directly so its impact VFX matches the
	# enemy-hit case rather than reading as a wall.
	set_meta(SurfaceMaterials.META_KEY, &"flesh")
	_base_fov = float(SettingsManager.get_value("video/fov"))
	EventBus.settings_applied.connect(_on_settings_applied)
	if health != null:
		health.damaged.connect(_on_damaged)
		health.died.connect(_on_died)
		_base_max_health = health.max_health
	# Survivability upgrades live on HealthComponent, which knows nothing about
	# UpgradeManager - the player is what bridges them.
	UpgradeManager.upgrades_changed.connect(_apply_survivability_stats)
	_apply_survivability_stats()
	_apply_local_only_nodes()
	if is_local():
		EventBus.local_player_spawned.emit(self)


## True for the body this machine drives. In single player there is no peer, so
## the default authority of 1 makes the only player local - no branch needed.
func is_local() -> bool:
	return is_multiplayer_authority()


## A remote player is scenery: it must not steal the viewport or paint its
## first-person arms over ours. The ViewmodelLayer is a CanvasLayer living
## inside the player scene, so without this every connected peer would render
## their own gun on top of everyone else's screen.
func _apply_local_only_nodes() -> void:
	var local: bool = is_local()
	if camera != null:
		camera.current = local
	var viewmodel := get_node_or_null("ViewmodelLayer") as CanvasLayer
	if viewmodel != null:
		viewmodel.visible = local
	# The third-person body is what other people see of us; hiding it locally
	# keeps it out of our own first-person view.
	var third_person := get_node_or_null("Body") as Node3D
	if third_person != null:
		third_person.visible = not local
	if local:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	# Input drives only our own body. Without this every peer's keyboard would
	# move every player on their screen at once. A downed player keeps its mouse
	# free for the spectator camera, which reads input on its own.
	if not is_local() or is_downed:
		return
	var motion := event as InputEventMouseMotion
	if motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity: float = SettingsManager.get_mouse_sensitivity(_is_ads())
		if bool(SettingsManager.get_value("input/invert_y")):
			sensitivity = -sensitivity
		_look_yaw -= motion.relative.x * sensitivity
		_look_pitch = clampf(_look_pitch - motion.relative.y * sensitivity,
			-MAX_PITCH_DEGREES, MAX_PITCH_DEGREES)
		return

	if weapon_holder != null and weapon_holder.handle_input(event):
		return
	if utility != null and utility.handle_input(event):
		return

	var equipped: WeaponComponent = weapon
	if equipped == null:
		return
	# A weapon mid-swap is not in the player's hands yet.
	if weapon_holder != null and weapon_holder.is_swapping:
		equipped.set_trigger(false)
		return

	if event.is_action_pressed("fire"):
		equipped.set_trigger(true)
	elif event.is_action_released("fire"):
		equipped.set_trigger(false)
	elif event.is_action_pressed("ads"):
		equipped.set_ads(true)
	elif event.is_action_released("ads"):
		equipped.set_ads(false)
	elif event.is_action_pressed("reload"):
		equipped.try_reload()
	elif event.is_action_pressed("interact"):
		_try_interact()


func _process(delta: float) -> void:
	# A remote player's yaw and head pitch arrive over the network. Running the
	# look code on them would immediately overwrite what was replicated with our
	# own (never-updated) angles, pinning every other player to a fixed stare.
	if not is_local() or is_downed:
		return
	_apply_look()
	_apply_fov(delta)


# Public API

## Where bullets actually go: look plus recoil aim offset, never the cosmetic kick.
func get_aim_transform() -> Transform3D:
	return head.global_transform if head != null else global_transform


# Private

## Zip lines are the only interactable in the slice, so this stays a direct look-up
## rather than a general interaction system.
func _try_interact() -> void:
	var ray: RayCast3D = head.get_node_or_null("InteractionRay") if head != null else null
	if ray == null:
		return
	ray.force_raycast_update()
	if not ray.is_colliding():
		return
	var line := ray.get_collider() as Node
	while line != null and not (line is ZipLine):
		line = line.get_parent()
	if line is ZipLine:
		(line as ZipLine).try_mount(self)


func _apply_look() -> void:
	var offset: Vector2 = recoil.aim_offset if recoil != null else Vector2.ZERO
	rotation.y = deg_to_rad(_look_yaw + offset.x)
	if head != null:
		head.rotation.x = deg_to_rad(clampf(_look_pitch + offset.y,
			-MAX_PITCH_DEGREES, MAX_PITCH_DEGREES))


func _apply_fov(delta: float) -> void:
	if camera == null:
		return
	var target: float = weapon.get_current_fov(_base_fov) if weapon != null else _base_fov
	camera.fov = target + _tick_speed_fov(delta)


## Widens the view as ground speed climbs past a normal run.
##
## Sense of speed is a camera property, not a physics one. The movement system hands
## out real momentum through slides, dashes and pads, but without this the screen
## looks identical at 7 m/s and 14 - so the reward for chaining well is invisible,
## and the whole thing reads as gliding. Suppressed while aiming, where a drifting
## FOV would fight the sight picture rather than sell anything.
func _tick_speed_fov(delta: float) -> float:
	var goal: float = 0.0
	if movement != null:
		var speed: float = Vector3(velocity.x, 0.0, velocity.z).length()
		var excess: float = speed - movement.base_move_speed
		if excess > 0.0:
			goal = minf(excess * SPEED_FOV_PER_UNIT, SPEED_FOV_MAX)
	if weapon != null:
		goal *= 1.0 - weapon.ads_progress
	_speed_fov = lerpf(_speed_fov, goal, clampf(SPEED_FOV_BLEND * delta, 0.0, 1.0))
	return _speed_fov


func _is_ads() -> bool:
	return weapon != null and weapon.is_ads


## Max health preserves the current fraction, so buying Plating mid-run tops the
## player up proportionally rather than handing out a free full heal.
func _apply_survivability_stats() -> void:
	if health == null or stats == null:
		return
	health.set_max_health(stats.get_stat_from(StatsComponent.MAX_HEALTH, _base_max_health))
	health.damage_taken_multiplier = stats.get_stat_from(
		StatsComponent.DAMAGE_TAKEN_MULTIPLIER, 1.0)


func _on_settings_applied() -> void:
	_base_fov = float(SettingsManager.get_value("video/fov"))


func _on_damaged(amount: float, remaining: float) -> void:
	EventBus.player_damaged.emit(amount, remaining)


func _on_died() -> void:
	# Solo: nothing to coordinate. The run ends the moment you fall.
	if not NetworkManager.is_online():
		EventBus.player_died.emit()
		return
	# Only the host's simulation gets to decide anyone is dead. A client's own
	# copy of its body never takes damage - the enemies that could deal it are
	# puppets there, with no brain and no attacks - so in practice this fires on
	# the authoritative machine and the broadcast carries the news outward.
	if NetworkManager.is_host():
		_report_downed.rpc()


## Broadcast: this player is out of the fight.
##
## Marked any_peer and checked by hand rather than declared "authority", which
## would be the obvious choice and is wrong here. This node's authority is the
## client that drives it - that is what makes its movement responsive - so an
## "authority" rpc on it is one the *host* is not allowed to send, and the host
## is the only machine that simulates the enemies doing the killing. Declaring
## it that way silently dropped every client death: the host's own body died and
## announced it, a client's died on the host and nobody downstream ever heard.
##
## call_local so the host walks the same path as everyone else - a downed player
## that behaves differently depending on whose machine it is standing on is a
## bug that only shows up in the one configuration nobody tests.
@rpc("any_peer", "call_local", "reliable")
func _report_downed() -> void:
	# 0 is a local call (the host announcing on its own machine); anything else
	# has to be the host. A client cannot declare itself - or anyone else - dead.
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != NetworkManager.SERVER_ID:
		return
	if is_downed:
		return
	is_downed = true
	_apply_downed_state()
	EventBus.player_downed.emit(get_peer_id())


## The peer that owns this body. Carried by the node name, which is how
## authority was resolved in the first place.
func get_peer_id() -> int:
	return name.to_int()


## A downed body stops being part of the fight everywhere at once: it takes no
## more hits, blocks nothing, and stops steering. It is left in the world rather
## than removed so teammates can see where you fell.
func _apply_downed_state() -> void:
	collision_layer = 0
	collision_mask = 0
	if movement != null:
		movement.set_physics_process(false)
	if health != null:
		health.is_invulnerable = true
	velocity = Vector3.ZERO
