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

## Cuanto baja el arma en el medio de la recarga. Sale y vuelve con el mismo
## seno, asi que no deja residuo. Brazos y arma son una sola malla, sin manos que
## se muevan: la recarga se cuenta con todo el bloque, y por eso baja bastante.
@export var reload_dip: float = 0.11
## Que fraccion de la recarga tarda el arma en inclinarse a
## `WeaponData.reload_tilt_degrees`, y lo mismo en volver al final.
@export var reload_tilt_ease: float = 0.18
## El golpe del cargador entrando: un tiron corto hacia arriba en ese momento de
## la recarga. Sin el, la recarga era bajar y subir, y no se sabia cuando
## "entraba" la bala.
@export var reload_seat_at: float = 0.68
@export var reload_seat_kick: float = 0.025
@export var reload_seat_width: float = 0.06

## Sacar el arma: sube desde abajo de la pantalla con la punta hacia abajo.
@export var equip_time: float = 0.3
@export var equip_drop: Vector3 = Vector3(0.0, -0.3, 0.08)
@export var equip_pitch_degrees: float = -35.0
## La respiracion en reposo: el arma nunca queda clavada en la pantalla.
@export var idle_breath_height: float = 0.004
@export var idle_breath_roll_degrees: float = 0.6
@export var idle_breath_speed: float = 1.4
## Al tirar el gancho el bloque gira y se corre para mostrar el lanzador de la
## muñeca izquierda, de donde sale el cable.
@export var grapple_roll_degrees: float = 14.0
@export var grapple_offset: Vector3 = Vector3(0.05, -0.03, 0.02)
@export var grapple_blend_time: float = 0.12

## El punto de la boca del cañon dentro del modelo (tools/blender/build_viewmodels.py).
const MUZZLE_NODE: StringName = &"Muzzle"
## Por preload y no por class_name: asi no depende de que la cache de clases
## globales ya se haya regenerado (CLI de tests en una copia recien clonada).
const LAUNCHER_SCRIPT := preload("res://scripts/components/viewmodel_grapple_launcher.gd")

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
## La esfera del daño de area, reusada entre disparos. Ver `_splash()`.
var _splash_shape: SphereShape3D
## La dispersion sale de la semilla de la run (RunSeed), una corriente para todas
## las armas: el recoil es determinista por diseño, y con esto el cono tambien lo
## es dada la misma secuencia de disparos.
var _rng: RandomNumberGenerator:
	get:
		return RunSeed.rng(&"spread")

var _view: Node3D
var _view_rest_position: Vector3 = Vector3.ZERO
## Sits at the barrel tip with the model's own orientation, inside the viewmodel
## rig - the flash hangs off this, never off `muzzle` (see the comment on
## `muzzle` itself for why those are two different points in two different worlds).
var _muzzle_marker: Node3D
var _muzzle_flash: MuzzleFlash
var _view_kick_offset: Vector3 = Vector3.ZERO
var _view_kick_rot: float = 0.0
## El lanzador del gancho, colgado del pivot en la muñeca izquierda del modelo.
var _launcher: LAUNCHER_SCRIPT
## Segundos que le quedan a la animacion de sacar el arma.
var _equip_left: float = 0.0
## 0 con el arma en reposo, 1 con el bloque girado mostrando el lanzador.
var _grapple_blend: float = 0.0
var _breath_time: float = 0.0


func _ready() -> void:
	if data == null:
		push_warning("WeaponComponent on %s has no WeaponData" % get_path())
		set_process(false)
		return
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


## Cuanto va de la recarga, 0 cuando no esta recargando y 1 al terminar. Lo lee
## el viewmodel para el giro, y sirve igual a cualquier cosa que quiera dibujar
## una barra de recarga sin duplicar el temporizador.
func get_reload_progress() -> float:
	if not is_reloading:
		return 0.0
	var total: float = get_reload_time()
	if total <= 0.0:
		return 0.0
	return clampf(1.0 - (_reload_timer / total), 0.0, 1.0)


func get_reload_time() -> float:
	return maxf(_stat(StatsComponent.RELOAD_TIME, data.reload_time), 0.05)


func get_fire_rate() -> float:
	return maxf(_stat(StatsComponent.FIRE_RATE, data.fire_rate), 0.01)


func get_damage() -> float:
	var damage: float = _stat(StatsComponent.WEAPON_DAMAGE, data.damage)
	# Air Ace: el tiro en el aire pega mas. Base 1, asi que sin la mejora no cambia.
	if body != null and not body.is_on_floor():
		damage *= _stat(StatsComponent.AIRBORNE_DAMAGE_MULTIPLIER, 1.0)
	return damage


## Mete balas en el cargador sin recargar: de la reserva, o gratis. Devuelve
## cuantas entraron. Lo usan las mejoras que recargan deslizando o con headshots.
func load_rounds(rounds: int, from_reserve: bool = true) -> int:
	if data == null or rounds <= 0:
		return 0
	var room: int = get_magazine_size() - _ammo
	var taken: int = mini(rounds, room)
	if from_reserve:
		taken = mini(taken, _reserve)
		_reserve -= maxi(taken, 0)
	if taken <= 0:
		return 0
	_ammo += taken
	_emit_ammo()
	return taken


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
	var shot_multiplier: float = _shot_damage_multiplier()
	for _i: int in get_projectiles_per_shot():
		var direction: Vector3 = _apply_spread(aim, spread)
		var hit: Dictionary = _aim_hit(aim_origin, direction)
		var target: Vector3 = _hit_point(aim_origin, direction, hit)
		var origin: Vector3 = _shot_origin(aim_origin, target)
		if data.is_hitscan:
			_resolve_hitscan(origin, target, hit, shot_multiplier)
			continue
		var travel: Vector3 = target - origin
		_spawn_projectile(origin,
			travel.normalized() if travel.length_squared() > 0.0001 else direction,
			shot_multiplier)

	_apply_self_knockback(aim)
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
func _resolve_hitscan(origin: Vector3, target: Vector3, hit: Dictionary,
		shot_multiplier: float = 1.0) -> void:
	var normal := Vector3.UP
	var surface: SurfaceMaterialData = null
	var landed: bool = not hit.is_empty()
	# get_damage() y no data.damage: ahi es donde entran las mejoras de daño
	# compradas. El proyectil las recibia por damage_override, y al resolver el
	# disparo aca hay que volver a pedirlas o la tienda deja de tener efecto sobre
	# las cuatro armas del jugador.
	var base_damage: float = get_damage() * shot_multiplier
	var impact: Vector3 = target
	# Los que ya recibieron esta bala: ni la perforacion ni el area les pegan dos
	# veces.
	var struck: Array[HealthComponent] = []
	if landed:
		normal = hit["normal"]
		var collider: Object = hit["collider"]
		surface = SurfaceMaterials.resolve(collider)
		var hitbox := collider as HitboxComponent
		if hitbox != null:
			_hit_hitbox(hitbox, base_damage, origin.distance_to(target), target)
			struck.append(hitbox.health_component)
			impact = _pierce(origin, target, hitbox, base_damage, struck)
	if landed:
		_splash(impact, base_damage, struck)

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


## The flash, hung off `_muzzle_marker` - see that variable's comment
## for why it can't go anywhere near `muzzle` itself. One flash per weapon,
## created on the first shot and restarted on every one after: see MuzzleFlash.
func _spawn_muzzle_vfx() -> void:
	if _muzzle_marker == null:
		return
	if _muzzle_flash == null:
		_muzzle_flash = MUZZLE_FLASH_SCENE.instantiate()
		_muzzle_marker.add_child(_muzzle_flash)
	_muzzle_flash.play()


func _spawn_projectile(origin: Vector3, direction: Vector3, shot_multiplier: float = 1.0) -> void:
	if data.projectile_scene == null:
		push_warning("WeaponComponent: %s has no projectile_scene" % data.id)
		return
	var projectile: Node = ObjectPool.acquire(data.projectile_scene)
	var typed := projectile as Projectile
	if typed == null:
		push_error("WeaponComponent: %s projectile_scene is not a Projectile" % data.id)
		return
	typed.launch(origin, direction, data, body, get_damage() * shot_multiplier,
		headshot_multiplier_for(data))


## Perdigones por disparo, con las mejoras: el slug de la escopeta los vuelve uno.
func get_projectiles_per_shot() -> int:
	return maxi(int(round(_stat(StatsComponent.PROJECTILES_PER_SHOT,
		float(data.projectiles_per_shot)))), 1)


func get_pierce_count() -> int:
	return maxi(int(round(_stat(StatsComponent.PIERCE_COUNT, float(data.pierce_count)))), 0)


func get_splash_radius() -> float:
	return maxf(_stat(StatsComponent.SPLASH_RADIUS, data.splash_radius), 0.0)


func get_self_knockback() -> float:
	return maxf(_stat(StatsComponent.SELF_KNOCKBACK, data.self_knockback), 0.0)


## Spread cone half-angle in degrees, including ADS, movement and airborne penalties.
##
## La penalidad por moverse se escala con `MOVING_SPREAD_PENALTY` (base 1): una
## mejora la puede borrar sin tocar la dispersion quieto, que es la que define al
## arma.
func get_current_spread() -> float:
	var base: float = lerpf(data.spread_hipfire, data.spread_ads, ads_progress)
	if body != null:
		var penalty: float = clampf(_stat(StatsComponent.MOVING_SPREAD_PENALTY, 1.0), 0.0, 1.0)
		if not body.is_on_floor():
			base *= lerpf(1.0, data.spread_airborne_multiplier, penalty)
		elif body.velocity.length() > 0.1:
			base *= lerpf(1.0, data.spread_moving_multiplier, penalty)
	return _stat(StatsComponent.SPREAD_MULTIPLIER, base)


## Lo que multiplica el daño de **este** disparo por cuando sale: la ultima bala
## del cargador y el primer tiro de una rafaga. Las dos bases son 1, asi que sin
## las mejoras que las mueven no cambia nada. Se lee con el cargador ya
## descontado: `_ammo == 0` es que esta era la ultima.
func _shot_damage_multiplier() -> float:
	var multiplier: float = 1.0
	if _ammo <= 0:
		multiplier *= _stat(StatsComponent.LAST_ROUND_DAMAGE, 1.0)
	if _shot_index == 0:
		multiplier *= _stat(StatsComponent.FIRST_SHOT_DAMAGE, 1.0)
	return multiplier


## Un impacto en un hitbox, con la caida por distancia y el multiplicador de la
## cabeza.
##
## `body` y no el arma como atacante: el dueño de la muerte es el que aprieta el
## gatillo, no el fierro. Es el mismo nodo que recibe Projectile.launch() como
## shooter, así que hitscan y bala atribuyen igual.
func _hit_hitbox(hitbox: HitboxComponent, damage: float, distance: float, point: Vector3) -> void:
	var dealt: float = damage * _falloff_at(distance)
	if hitbox.is_headshot_zone:
		dealt *= headshot_multiplier_for(data)
	hitbox.take_hit(dealt, point, body)


## La bala sigue de largo despues del primer enemigo, hasta `get_pierce_count()`
## enemigos mas o hasta la primera pared. Devuelve donde termino.
##
## Un enemigo tiene varios hitboxes (cabeza y cuerpo): el rayo que sale de la
## cabeza puede tocar el cuerpo del mismo, y eso no cuenta como otro enemigo.
func _pierce(origin: Vector3, from_point: Vector3, first: HitboxComponent,
		base_damage: float, struck: Array[HealthComponent]) -> Vector3:
	var remaining: int = get_pierce_count()
	if remaining <= 0:
		return from_point
	var direction: Vector3 = (from_point - origin).normalized()
	var exclude: Array[RID] = [first.get_rid()]
	if body != null:
		exclude.append(body.get_rid())
	var space: PhysicsDirectSpaceState3D = aim_node.get_world_3d().direct_space_state
	var point: Vector3 = from_point
	var damage: float = base_damage
	# Tope de rayos: cada hitbox del mismo enemigo es un rayo mas, y una bala no
	# puede costar una cantidad sin techo de consultas.
	for _attempt: int in remaining * 3 + 2:
		if remaining <= 0:
			break
		var query := PhysicsRayQueryParameters3D.create(point,
			point + direction * CONVERGE_DISTANCE, PhysicsLayers.WORLD | PhysicsLayers.HITBOX)
		query.collide_with_areas = true
		query.exclude = exclude
		var next: Dictionary = space.intersect_ray(query)
		if next.is_empty():
			break
		var hitbox := next["collider"] as HitboxComponent
		if hitbox == null:
			return next["position"]
		exclude.append(hitbox.get_rid())
		point = next["position"]
		if struck.has(hitbox.health_component):
			continue
		damage *= data.pierce_damage_falloff
		_hit_hitbox(hitbox, damage, origin.distance_to(point), point)
		struck.append(hitbox.health_component)
		remaining -= 1
	return point


## Daño de area donde termino la bala, a todo enemigo en el radio que la bala no
## haya tocado ya. Solo hitboxes de cuerpo -la cabeza no paga headshot por estar
## cerca de una explosion- y uno por enemigo.
##
## Sin VFX propio a proposito: el SMG lo dispara quince veces por segundo, y una
## explosion por bala es ruido, no informacion. El numero de daño ya marca a quien
## alcanzo.
func _splash(point: Vector3, base_damage: float, struck: Array[HealthComponent]) -> void:
	var radius: float = get_splash_radius()
	if radius <= 0.0:
		return
	if _splash_shape == null:
		_splash_shape = SphereShape3D.new()
	_splash_shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _splash_shape
	params.transform = Transform3D(Basis.IDENTITY, point)
	params.collision_mask = PhysicsLayers.HITBOX
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var space: PhysicsDirectSpaceState3D = aim_node.get_world_3d().direct_space_state
	var splashed: Array[HealthComponent] = []
	for result: Dictionary in space.intersect_shape(params, 32):
		var hitbox := result["collider"] as HitboxComponent
		if hitbox == null or hitbox.is_headshot_zone or hitbox.health_component == null:
			continue
		if struck.has(hitbox.health_component) or splashed.has(hitbox.health_component):
			continue
		splashed.append(hitbox.health_component)
		hitbox.take_hit(base_damage * data.splash_damage_fraction, point, body)


## El empujon del disparo, en contra de donde se apunta. Ver
## `WeaponData.self_knockback`.
func _apply_self_knockback(aim: Vector3) -> void:
	var push: float = get_self_knockback()
	if push <= 0.0 or body == null:
		return
	body.velocity += -aim * push


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
## The model is the arms and the weapon in one mesh (tools/blender/build_viewmodels.py),
## so everything that moves on screen - kick, reload, equip, breathing, the grapple
## turn - moves the whole block through this pivot.
##
## The pivot is not ceremony. Kick is a pitch, and pitch has to happen in the
## player's frame - but Godot composes a node's local euler as Y * X * Z, so
## pitching the model itself would rotate about an axis the model's own yaw has
## already turned. Keeping the pivot unrotated and letting the model carry its own
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
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Solo en el rig: el cable sale de la camara del viewmodel hacia el mundo del
	# juego, y sin rig no hay dos camaras entre las que traducirlo.
	if viewmodel_parent != null:
		_mount_launcher(model)

	# The pivot no longer lives under this node when a rig is in play, so it cannot
	# inherit the visibility WeaponHolder toggles here.
	visibility_changed.connect(_sync_viewmodel_visibility)
	_sync_viewmodel_visibility()
	_align_muzzle_to_barrel(model)


## El lanzador del gancho sobre la muñeca izquierda del modelo, mirando adonde
## mira el arma. Colgado del pivot y no del modelo: asi no hereda su escala, que
## cambia de arma a arma, y el lanzador mide lo mismo en las cuatro.
func _mount_launcher(model: Node3D) -> void:
	_launcher = LAUNCHER_SCRIPT.new()
	_launcher.name = &"GrappleLauncher"
	# Los cuatro viewmodels traen el lanzador modelado en la muñeca: el nodo queda
	# como el punto de donde sale el cable, sin dibujar otro encima.
	_launcher.show_body = false
	_view.add_child(_launcher)
	_launcher.transform = Transform3D(
		model.basis.orthonormalized().scaled(Vector3.ONE * data.viewmodel_launcher_scale),
		model.transform * data.viewmodel_launcher_position)


func _sync_viewmodel_visibility() -> void:
	if _view != null:
		_view.visible = visible
	# Cada vez que el arma aparece, sube desde abajo: cambiar de arma se ve.
	if visible:
		_equip_left = equip_time


## Puts the muzzle node at the model's own barrel tip.
##
## It was authored at a fixed offset guessed before there were models, and guessed
## short: rounds spawned inside the receiver and appeared to leave from behind the
## gun. The model carries a `Muzzle` node at the tip of its barrel; one without it
## falls back to the front face of its bounds.
func _align_muzzle_to_barrel(model: Node3D) -> void:
	if muzzle == null:
		return
	var tip: Vector3
	var marked := model.find_child(MUZZLE_NODE, true, false) as Node3D
	if marked != null:
		tip = model.transform * _relative_transform(model, marked).origin
	else:
		var bounds: AABB = _model_bounds(model)
		if bounds.size == Vector3.ZERO:
			return
		# Forward is -Z, so the tip is the near face; X and Y take the centre.
		var centre: Vector3 = bounds.position + bounds.size * 0.5
		tip = Vector3(centre.x, centre.y, bounds.position.z)
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
		var relative: Transform3D = _relative_transform(model, mesh_instance)
		var local: AABB = relative * mesh_instance.mesh.get_aabb()
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


## Todo lo que mueve el bloque en pantalla, sumado sobre el pivot: kick, recarga,
## sacar el arma, respiracion y el giro del gancho. Derivado de estado y tiempo y
## no de tweens, por la misma razon que `_reload_tilt()`: este tick reescribe el
## pivot cada frame, y una recarga o un cambio cortados vuelven solos al reposo.
## Cosmetic only - never touches `aim_node`, so it can never nudge where a shot
## actually lands.
func _tick_viewmodel(delta: float) -> void:
	if _view == null:
		return
	_view_kick_offset = _view_kick_offset.move_toward(Vector3.ZERO, view_kick_recovery * delta * 0.1)
	_view_kick_rot = move_toward(_view_kick_rot, 0.0, view_kick_recovery * delta)
	_equip_left = maxf(_equip_left - delta, 0.0)
	_breath_time += delta
	var grappling: bool = _launcher != null and _launcher.is_grappling()
	_grapple_blend = move_toward(_grapple_blend, 1.0 if grappling else 0.0,
		delta / maxf(grapple_blend_time, 0.01))

	var reload_progress: float = get_reload_progress()
	var equip: float = _equip_amount()
	var grapple: float = smoothstep(0.0, 1.0, _grapple_blend)
	var breath: float = sin(_breath_time * idle_breath_speed)
	_view.position = _view_rest_position + _view_kick_offset \
		+ Vector3.DOWN * (reload_dip * sin(PI * reload_progress)) \
		+ Vector3.UP * _reload_seat(reload_progress) \
		+ equip_drop * equip \
		+ grapple_offset * grapple \
		+ Vector3.UP * (idle_breath_height * breath)
	_view.rotation_degrees = Vector3(_view_kick_rot + equip_pitch_degrees * equip, 0.0,
			idle_breath_roll_degrees * breath * 0.5 - grapple_roll_degrees * grapple) \
		+ _reload_tilt(reload_progress)


## 1 recien sacada, 0 en posicion. Con smoothstep: arranca rapido y frena al
## llegar, que es como se levanta un arma.
func _equip_amount() -> float:
	if equip_time <= 0.0:
		return 0.0
	return 1.0 - smoothstep(0.0, 1.0, 1.0 - _equip_left / equip_time)


## El tiron del cargador al entrar: una campana angosta alrededor de
## `reload_seat_at`, en cero fuera de ella.
func _reload_seat(progress: float) -> float:
	if progress <= 0.0 or reload_seat_width <= 0.0:
		return 0.0
	var distance: float = absf(progress - reload_seat_at) / reload_seat_width
	return reload_seat_kick * maxf(1.0 - distance * distance, 0.0)


## La inclinacion de recarga, derivada del progreso en vez de animada por un Tween.
##
## Un tween sobre _view pelearia con este mismo tick, que le reescribe posicion y
## rotacion todos los frames; el ultimo en escribir ganaria y saldria a los
## tirones. Derivarlo ademas resuelve solo el caso feo: si la recarga se corta,
## el progreso vuelve a cero y el arma con el, sin ningun estado que limpiar.
func _reload_tilt(progress: float) -> Vector3:
	if progress <= 0.0:
		return Vector3.ZERO
	var amount: float = smoothstep(0.0, reload_tilt_ease, progress) \
		* (1.0 - smoothstep(1.0 - reload_tilt_ease, 1.0, progress))
	return data.reload_tilt_degrees * amount


## Scoped to this weapon's own id, so WEAPON-category upgrades bought for a
## different (previously equipped) weapon never leak into this one's stats.
## El multiplicador de cabeza del arma con lo que el build le suma (Deadeye). El
## mismo para hitscan y para bala: la bala lo recibe al salir.
static func headshot_multiplier_for(weapon: WeaponData) -> float:
	if weapon == null:
		return 1.0
	return weapon.headshot_multiplier * UpgradeManager.get_stat(
		StatsComponent.HEADSHOT_DAMAGE_MULTIPLIER, 1.0, weapon.id)


func _stat(stat_key: StringName, base_value: float) -> float:
	if stats == null:
		return base_value
	return stats.get_stat_from(stat_key, base_value, data.id if data != null else &"")


func _emit_ammo() -> void:
	ammo_changed.emit(_ammo, _reserve)
	EventBus.ammo_changed.emit(_ammo, _reserve)
