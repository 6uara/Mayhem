class_name WeaponComponent
extends Node3D
## One equipped weapon: firing, deterministic recoil, spread, ADS, reload and ammo.
## All numbers come from `data`; upgrades layer on through StatsComponent.

## How far down the aim ray a shot converges when it meets nothing. Past this the
## angular difference between muzzle and crosshair is far under one pixel.
const CONVERGE_DISTANCE: float = 300.0
## Slack past the muzzle before a target counts as point blank.
const MUZZLE_CLEARANCE: float = 0.25

const MUZZLE_FLASH_SCENE: PackedScene = preload("res://scenes/vfx/muzzle_flash.tscn")
const EJECTED_SHELL_SCENE: PackedScene = preload("res://scenes/vfx/ejected_shell.tscn")

signal fired(shot_index: int)
signal reload_started(duration: float)
signal reload_finished()
signal ammo_changed(current: int, reserve: int)
signal ads_changed(is_ads: bool)

@export var data: WeaponData
## Aim source - the head pivot, not the camera, so cosmetic kick never moves bullets.
@export var aim_node: Node3D
## Where shots actually spawn - deliberately in the main world, not the viewmodel
## rig, so damage math never depends on which world a cosmetic model happens to
## render in. This is NOT where the muzzle flash renders: that lives on
## `_muzzle_marker`, inside the rig, because the viewmodel's camera has a fixed
## orientation independent of where the player is looking - a flash placed here,
## in the main world, would drift out of alignment with the gun the moment the
## player turns.
@export var muzzle: Node3D
@export var recoil: CameraRecoilComponent
@export var stats: StatsComponent
@export var body: CharacterBody3D
## Where the viewmodel is rendered. Left unset the model hangs off this node in the
## main world; pointed at the SubViewport rig it renders in its own world instead,
## which is what keeps a half-metre-long rifle from poking through walls.
@export var viewmodel_parent: Node3D

@export_group("Audio")
@export var fire_sound: AudioStream
@export var reload_sound: AudioStream
@export var empty_sound: AudioStream

@export_group("Viewmodel feel")
## Purely cosmetic kick on the viewmodel mesh - it moves the model, never the aim.
@export var view_kick_back: float = 0.05
@export var view_kick_up_degrees: float = 3.0
@export var view_kick_recovery: float = 10.0
## Ceilings on the accumulated kick.
##
## Recovery is a rate, so without a ceiling a weapon that fires faster than the
## kick recovers accumulates without bound: the rifle adds 3 degrees nine times a
## second against a 10 degree/second return, and the gun simply rotates away.
## These are what make the kick a wobble instead of a spin.
@export var view_kick_max_degrees: float = 6.0
@export var view_kick_max_back: float = 0.12

var is_reloading: bool = false
var is_ads: bool = false
## 0 = hipfire, 1 = fully aimed. Drives FOV and spread interpolation.
var ads_progress: float = 0.0

var _ammo: int = 0
var _reserve: int = 0
var _shot_index: int = 0
## Cuenta balas para el intervalo de trazadora. Por bala y no por disparo: una
## escopeta manda nueve de una, y son justo las que mas conviene ralear.
var _tracer_counter: int = 0
var _time_since_shot: float = 999.0
var _cooldown: float = 0.0
var _is_trigger_held: bool = false
var _reload_timer: float = 0.0
var _rng := RandomNumberGenerator.new()

var _view: Node3D
var _view_rest_position: Vector3 = Vector3.ZERO
## Sits at the barrel tip with the model's own orientation, inside the viewmodel
## rig - flash and shell VFX hang off this, never off `muzzle` (see the comment on
## `muzzle` itself for why those are two different points in two different worlds).
var _muzzle_marker: Node3D
var _view_kick_offset: Vector3 = Vector3.ZERO
var _view_kick_rot: float = 0.0


func _ready() -> void:
	if data == null:
		push_warning("WeaponComponent on %s has no WeaponData" % get_path())
		set_process(false)
		return
	_rng.randomize()
	_ammo = get_magazine_size()
	_reserve = get_reserve_max()
	_emit_ammo()
	_spawn_viewmodel()


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_time_since_shot += delta
	_tick_reload(delta)
	_tick_ads(delta)
	_tick_recoil_reset()
	_tick_viewmodel(delta)
	if _is_trigger_held:
		_try_fire()


# Public API

func set_trigger(held: bool) -> void:
	_is_trigger_held = held
	if held:
		_try_fire()


func set_ads(value: bool) -> void:
	if is_ads == value:
		return
	is_ads = value
	ads_changed.emit(is_ads)
	EventBus.weapon_ads_changed.emit(is_ads)


func try_reload() -> bool:
	if is_reloading or data == null:
		return false
	if _ammo >= get_magazine_size() or _reserve <= 0:
		return false
	is_reloading = true
	_reload_timer = get_reload_time()
	reload_started.emit(_reload_timer)
	AudioPool.play_3d(reload_sound, global_position, AudioPool.BUS_WEAPONS)
	return true


## Adds reserve ammo from a pickup. Returns the amount actually taken -
## the overflow is left in the world rather than silently discarded.
func add_reserve_ammo(amount: int) -> int:
	var space: int = get_reserve_max() - _reserve
	var taken: int = clampi(amount, 0, maxi(space, 0))
	_reserve += taken
	if taken > 0:
		_emit_ammo()
	return taken


## Re-announces this weapon's ammo. Called by WeaponHolder on equip so the HUD
## shows the new weapon's counts rather than the previous one's.
func notify_equipped() -> void:
	_is_trigger_held = false
	is_ads = false
	ads_progress = 0.0
	_emit_ammo()


## Back to a full magazine and reserve. Used between runs, not between waves -
## nothing carries across runs (CLAUDE.md 5.5).
func reset() -> void:
	is_reloading = false
	_reload_timer = 0.0
	_shot_index = 0
	_cooldown = 0.0
	_is_trigger_held = false
	is_ads = false
	ads_progress = 0.0
	_ammo = get_magazine_size()
	_reserve = get_reserve_max()
	_emit_ammo()


func get_ammo() -> int:
	return _ammo


func get_reserve() -> int:
	return _reserve


func get_shot_index() -> int:
	return _shot_index


func is_empty() -> bool:
	return _ammo <= 0


func get_current_fov(base_fov: float) -> float:
	if data == null:
		return base_fov
	return lerpf(base_fov, data.ads_fov, ads_progress)


func get_move_speed_multiplier() -> float:
	if data == null:
		return 1.0
	return lerpf(1.0, data.ads_move_speed_multiplier, ads_progress)


# Upgrade-aware stat reads

func get_magazine_size() -> int:
	return int(round(_stat(StatsComponent.MAGAZINE_SIZE, float(data.magazine_size))))


func get_reserve_max() -> int:
	return int(round(_stat(StatsComponent.RESERVE_AMMO_MAX, float(data.reserve_ammo_max))))


func get_reload_time() -> float:
	return maxf(_stat(StatsComponent.RELOAD_TIME, data.reload_time), 0.05)


func get_fire_rate() -> float:
	return maxf(_stat(StatsComponent.FIRE_RATE, data.fire_rate), 0.01)


func get_damage() -> float:
	return _stat(StatsComponent.WEAPON_DAMAGE, data.damage)


# Private

func _try_fire() -> void:
	if data == null or is_reloading or _cooldown > 0.0:
		return
	if _ammo <= 0:
		_on_empty()
		return

	_ammo -= 1
	_cooldown = 1.0 / get_fire_rate()
	_time_since_shot = 0.0

	var aim_origin: Vector3 = aim_node.global_position
	var aim: Vector3 = -aim_node.global_transform.basis.z
	var spread: float = get_current_spread()
	for _i: int in maxi(data.projectiles_per_shot, 1):
		var direction: Vector3 = _apply_spread(aim, spread)
		var hit: Dictionary = _aim_hit(aim_origin, direction)
		var target: Vector3 = _hit_point(aim_origin, direction, hit)
		var origin: Vector3 = _shot_origin(aim_origin, target)
		if data.is_hitscan:
			_resolve_hitscan(origin, target, hit)
			continue
		var travel: Vector3 = target - origin
		_spawn_projectile(origin,
			travel.normalized() if travel.length_squared() > 0.0001 else direction)

	_apply_recoil()
	_view_kick_offset.z = minf(_view_kick_offset.z + view_kick_back, view_kick_max_back)
	_view_kick_rot = maxf(_view_kick_rot - view_kick_up_degrees, -view_kick_max_degrees)
	_spawn_muzzle_vfx()
	AudioPool.play_3d(fire_sound, global_position, AudioPool.BUS_WEAPONS)
	fired.emit(_shot_index)
	EventBus.weapon_fired.emit(data.id)
	_shot_index += 1
	_emit_ammo()

	if _ammo <= 0:
		try_reload()


## Where the shot is actually going: the first thing the aim ray meets, or a point
## far enough down it that the difference stops mattering.
##
## Rounds used to spawn on the aim ray itself, which put the tracer inside the
## player's own head - the round was correct and the picture was a lie. Firing from
## the muzzle parallel to the aim instead would be a different lie: parallel lines
## never meet, so every shot would sit beside the crosshair by the muzzle's offset,
## at every range. Aiming the muzzle at the point the crosshair reaches is what
## makes both true at once.
## Este rayo ya existia: se tiraba en cada disparo solo para saber a donde
## apuntar el caño. Ahora devuelve el impacto entero, porque es exactamente la
## pregunta que la bala volaba a repetir - contra que pego y donde.
func _aim_hit(aim_origin: Vector3, direction: Vector3) -> Dictionary:
	var far_point: Vector3 = aim_origin + direction * CONVERGE_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(aim_origin, far_point,
		PhysicsLayers.WORLD | PhysicsLayers.HITBOX)
	query.collide_with_areas = true
	if body != null:
		query.exclude = [body.get_rid()]
	return aim_node.get_world_3d().direct_space_state.intersect_ray(query)


func _hit_point(aim_origin: Vector3, direction: Vector3, hit: Dictionary) -> Vector3:
	if hit.is_empty():
		return aim_origin + direction * CONVERGE_DISTANCE
	return hit["position"]


## Aplica el disparo ahora y manda la trazadora a mostrarlo.
##
## El orden importa y es a proposito: el daño entra al apretar el gatillo, la
## trazadora tarda lo suyo en llegar. A 160 m/s son menos de dos decimas a veinte
## metros - nadie ve morir al enemigo antes que la bala. Al reves si se notaria:
## una bala que ya llego y todavia no hizo nada.
func _resolve_hitscan(origin: Vector3, target: Vector3, hit: Dictionary) -> void:
	var normal := Vector3.UP
	var surface: SurfaceMaterialData = null
	var landed: bool = not hit.is_empty()
	if landed:
		normal = hit["normal"]
		var collider: Object = hit["collider"]
		surface = SurfaceMaterials.resolve(collider)
		var hitbox := collider as HitboxComponent
		if hitbox != null:
			var distance: float = origin.distance_to(target)
			# get_damage() y no data.damage: ahi es donde entran las mejoras de
			# daño compradas. El proyectil las recibia por damage_override, y al
			# resolver el disparo aca hay que volver a pedirlas o la tienda deja
			# de tener efecto sobre las cuatro armas del jugador.
			var damage: float = get_damage() * _falloff_at(distance)
			if hitbox.is_headshot_zone:
				damage *= data.headshot_multiplier
			hitbox.take_hit(damage, target)

	if not _wants_tracer() or data.projectile_scene == null:
		return
	var tracer := ObjectPool.acquire(data.projectile_scene) as Projectile
	if tracer == null:
		return
	tracer.launch_tracer(origin, target, data.projectile_speed, normal, surface, landed)


## Si esta bala se dibuja o no.
##
## Medido: el gasto de disparar no esta en resolver el impacto, esta en tener un
## nodo por bala volando. Una trazadora sin raycast cuesta casi lo mismo que
## costaba el proyectil completo, porque lo caro es el nodo -su _physics_process,
## su transform, el pool- y no la cuenta que hace adentro.
##
## Asi que se dibujan menos. Es lo que hacen los shooters desde siempre: la
## munición trazadora real viene una cada varias, y a quince disparos por segundo
## el ojo lee una linea de fuego igual. Con el intervalo en 1 se dibujan todas.
func _wants_tracer() -> bool:
	var interval: int = maxi(data.tracer_every_n_shots, 1)
	if interval == 1:
		return true
	_tracer_counter += 1
	if _tracer_counter < interval:
		return false
	_tracer_counter = 0
	return true


## La misma curva que aplicaba la bala. Vive aca ahora porque el disparo se
## resuelve aca, y la bala dejo de tener nada que decidir.
func _falloff_at(distance: float) -> float:
	if distance <= data.falloff_start or data.falloff_end <= data.falloff_start:
		return 1.0
	if distance >= data.falloff_end:
		return data.falloff_min_multiplier
	return lerpf(1.0, data.falloff_min_multiplier,
		(distance - data.falloff_start) / (data.falloff_end - data.falloff_start))


## Point blank, the muzzle is already past whatever is being shot at - firing from
## there would send the round out the far side of it. The aim origin is behind the
## target in that case, so it stays honest where the muzzle cannot.
func _shot_origin(aim_origin: Vector3, target: Vector3) -> Vector3:
	if muzzle == null:
		return aim_origin
	var muzzle_reach: float = aim_origin.distance_to(muzzle.global_position)
	if aim_origin.distance_to(target) <= muzzle_reach + MUZZLE_CLEARANCE:
		return aim_origin
	return muzzle.global_position


## Flash and shell, both hung off `_muzzle_marker` - see that variable's comment
## for why they can't go anywhere near `muzzle` itself. Plain instantiate, not
## ObjectPool: the pool's container lives in the main world, and pooling something
## into the wrong World3D is worse than not pooling it at all. Nothing here fires
## often enough for that cost to matter - even the SMG tops out at 15/s.
func _spawn_muzzle_vfx() -> void:
	if _muzzle_marker == null:
		return

	var flash: MuzzleFlash = MUZZLE_FLASH_SCENE.instantiate()
	_muzzle_marker.add_child(flash)
	flash.play()

	var shell: EjectedShell = EJECTED_SHELL_SCENE.instantiate()
	_muzzle_marker.add_child(shell)
	# Reparented to the rig's static slot container immediately: staying under
	# _muzzle_marker would make the casing ride the weapon's own kick and sway
	# instead of tumbling on its own, which is the entire point of ejecting it.
	if viewmodel_parent != null:
		var eject_transform: Transform3D = shell.global_transform
		_muzzle_marker.remove_child(shell)
		viewmodel_parent.add_child(shell)
		shell.global_transform = eject_transform
	shell.eject(Vector3.RIGHT, Vector3.UP)


func _spawn_projectile(origin: Vector3, direction: Vector3) -> void:
	if data.projectile_scene == null:
		push_warning("WeaponComponent: %s has no projectile_scene" % data.id)
		return
	var projectile: Node = ObjectPool.acquire(data.projectile_scene)
	var typed := projectile as Projectile
	if typed == null:
		push_error("WeaponComponent: %s projectile_scene is not a Projectile" % data.id)
		return
	typed.launch(origin, direction, data, body, get_damage())


## Spread cone half-angle in degrees, including ADS, movement and airborne penalties.
func get_current_spread() -> float:
	var base: float = lerpf(data.spread_hipfire, data.spread_ads, ads_progress)
	if body != null:
		if not body.is_on_floor():
			base *= data.spread_airborne_multiplier
		elif body.velocity.length() > 0.1:
			base *= data.spread_moving_multiplier
	return _stat(StatsComponent.SPREAD_MULTIPLIER, base)


## Random cone deviation. Spread is allowed to be random; the recoil pattern is not.
func _apply_spread(direction: Vector3, spread_degrees: float) -> Vector3:
	if spread_degrees <= 0.0:
		return direction
	var aim_basis: Basis = aim_node.global_transform.basis
	var angle: float = _rng.randf_range(0.0, TAU)
	var magnitude: float = deg_to_rad(spread_degrees) * sqrt(_rng.randf())
	var offset: Vector3 = (aim_basis.x * cos(angle) + aim_basis.y * sin(angle)) * tan(magnitude)
	return (direction + offset).normalized()


func _apply_recoil() -> void:
	if recoil == null or data.recoil_pattern == null:
		return
	var pattern: RecoilPattern = data.recoil_pattern
	var magnitude: float = _stat(StatsComponent.RECOIL_MAGNITUDE, 1.0)
	recoil.apply_shot(pattern.get_offset(_shot_index, magnitude), pattern.recovery_speed,
		pattern.visual_kick_multiplier)


## The pattern index resets after `reset_time` without firing - this is what makes
## a spray learnable: the same trigger discipline always produces the same pattern.
func _tick_recoil_reset() -> void:
	if _shot_index == 0 or data.recoil_pattern == null:
		return
	if _time_since_shot >= data.recoil_pattern.reset_time:
		_shot_index = 0


func _tick_reload(delta: float) -> void:
	if not is_reloading:
		return
	_reload_timer -= delta
	if _reload_timer > 0.0:
		return
	is_reloading = false
	var needed: int = get_magazine_size() - _ammo
	var taken: int = mini(needed, _reserve)
	_ammo += taken
	_reserve -= taken
	_shot_index = 0
	reload_finished.emit()
	EventBus.weapon_reloaded.emit(data.id)
	_emit_ammo()


func _tick_ads(delta: float) -> void:
	var transition: float = maxf(_stat(StatsComponent.ADS_TRANSITION_TIME,
		data.ads_transition_time), 0.01)
	var target: float = 1.0 if is_ads else 0.0
	ads_progress = move_toward(ads_progress, target, delta / transition)


func _on_empty() -> void:
	if _cooldown > 0.0:
		return
	_cooldown = 0.25
	AudioPool.play_3d(empty_sound, global_position, AudioPool.BUS_WEAPONS)
	try_reload()


## Instances the weapon's viewmodel under a pivot this component owns. Visibility
## already follows this node (WeaponHolder toggles it), so nothing else needs wiring.
##
## The pivot is not ceremony. Kick is a pitch, and pitch has to happen in the
## player's frame - but Godot composes a node's local euler as Y * X * Z, so
## pitching the model itself would rotate about an axis the model's own yaw has
## already turned. Every current weapon is authored with a 90 degree yaw, which
## turns that pitch a quarter turn sideways: on screen the gun rolls over instead
## of kicking up. Keeping the pivot unrotated and letting the model carry its own
## orientation underneath means the kick axis is always the screen's.
func _spawn_viewmodel() -> void:
	if data.viewmodel == null:
		return
	_view = Node3D.new()
	_view.name = &"ViewPivot"
	var host: Node3D = viewmodel_parent if viewmodel_parent != null else self
	host.add_child(_view)
	_view_rest_position = data.viewmodel_offset
	_view.position = _view_rest_position

	var model: Node3D = data.viewmodel.instantiate()
	_view.add_child(model)
	model.rotation_degrees = data.viewmodel_rotation_degrees
	model.scale = Vector3.ONE * data.viewmodel_scale

	# The pivot no longer lives under this node when a rig is in play, so it cannot
	# inherit the visibility WeaponHolder toggles here.
	visibility_changed.connect(_sync_viewmodel_visibility)
	_sync_viewmodel_visibility()
	_align_muzzle_to_barrel(model)


func _sync_viewmodel_visibility() -> void:
	if _view != null:
		_view.visible = visible


## Puts the muzzle node at the model's own barrel tip.
##
## It was authored at a fixed offset guessed before there were models, and guessed
## short: the rifle's barrel ends 0.38m further out than the node sat, so rounds
## spawned inside the receiver and appeared to leave from behind the gun. Measuring
## the mesh means every weapon is right, including ones added later.
func _align_muzzle_to_barrel(model: Node3D) -> void:
	if muzzle == null:
		return
	var bounds: AABB = _model_bounds(model)
	if bounds.size == Vector3.ZERO:
		return
	# Forward is -Z, so the tip is the near face; X and Y take the barrel's centre.
	var centre: Vector3 = bounds.position + bounds.size * 0.5
	var tip: Vector3 = Vector3(centre.x, centre.y, bounds.position.z)
	muzzle.position = _view_rest_position + tip

	# The marker is a sibling of the model (both children of _view), so it needs
	# the model's own rotation to point the same way the barrel actually renders -
	# _view itself only carries kick, never the weapon's authored orientation.
	if _muzzle_marker == null:
		_muzzle_marker = Node3D.new()
		_muzzle_marker.name = &"MuzzleMarker"
		_view.add_child(_muzzle_marker)
	var model_basis := Basis.from_euler(data.viewmodel_rotation_degrees * (PI / 180.0))
	_muzzle_marker.transform = Transform3D(model_basis, tip)


## Combined bounds of every mesh under `model`, in `model`'s parent's space.
func _model_bounds(model: Node3D) -> AABB:
	var out := AABB()
	var found: bool = false
	for node: Node in _descendants(model):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var local: AABB = _relative_transform(model, mesh_instance) * mesh_instance.mesh.get_aabb()
		out = local if not found else out.merge(local)
		found = true
	return model.transform * out if found else AABB()


func _descendants(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child: Node in node.get_children():
		out.append_array(_descendants(child))
	return out


func _relative_transform(root: Node3D, target: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var node: Node3D = target
	while node != null and node != root:
		result = node.transform * result
		node = node.get_parent() as Node3D
	return result


## Cosmetic-only recoil on the pivot - never touches `aim_node`, so it can never
## nudge where a shot actually lands.
func _tick_viewmodel(delta: float) -> void:
	if _view == null:
		return
	_view_kick_offset = _view_kick_offset.move_toward(Vector3.ZERO, view_kick_recovery * delta * 0.1)
	_view_kick_rot = move_toward(_view_kick_rot, 0.0, view_kick_recovery * delta)
	_view.position = _view_rest_position + _view_kick_offset
	_view.rotation_degrees.x = _view_kick_rot


## Scoped to this weapon's own id, so WEAPON-category upgrades bought for a
## different (previously equipped) weapon never leak into this one's stats.
func _stat(stat_key: StringName, base_value: float) -> float:
	if stats == null:
		return base_value
	return stats.get_stat_from(stat_key, base_value, data.id if data != null else &"")


func _emit_ammo() -> void:
	ammo_changed.emit(_ammo, _reserve)
	EventBus.ammo_changed.emit(_ammo, _reserve)
