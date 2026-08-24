class_name MovementComponent
extends Node
## The movement state machine: GROUNDED, AIRBORNE, SLIDING, DASHING, GRAPPLING.
## Owns all of the player's physics; the Player script keeps look and weapon input.
##
## Design intent from CLAUDE.md 5.2: momentum is a resource the player builds and
## keeps. Slide conserves and chains speed, bhop chaining is intended, and nothing
## here caps speed to make AI "fair" - AI is aggro-locked, so speed is safe.

signal state_changed(new_state: State)
signal landed(fall_speed: float)
## Fires once ever, the first frame movement input produces nonzero wish_direction -
## TutorialHintManager's hook for the "how do I move" hint. Never fires again.
signal started_moving()
signal jumped()
## Fires only when a mantle actually boosts the player up a ledge - a probe that
## finds nothing mantleable is not "mantling".
signal mantled()

enum State { GROUNDED, AIRBORNE, SLIDING, DASHING, GRAPPLING }

## Cuánto dura la inmunidad al atrapado después de romperlo. Tiene que alcanzar
## para salir del charco: un dash son 0.16s a 16 m/s, o sea ~2.5m, y el charco de
## atrapado mide 2.6m de radio - así que la gracia tiene que cubrir también el par
## de pasos que siguen al dash, o el borde te agarra de nuevo al salir.
const SNARE_GRACE: float = 0.9

@export var body: CharacterBody3D
@export var head: Node3D
@export var stats: StatsComponent
@export var grapple: GrappleComponent

@export_group("Ground")
@export var base_move_speed: float = 7.5
@export var acceleration: float = 60.0
@export var friction: float = 45.0
## Apex under `gravity` alone is jump_velocity^2 / (2*gravity) - 1.33m at the
## default. Raised from 5.5 (a 0.63m apex, barely a hop) because a jump that
## doesn't clear a knee-height ledge reads as a movement bug, not restraint.
@export var jump_velocity: float = 8.0
@export var gravity: float = 24.0

@export_group("Air")
## Steering acceleration while airborne. Horizontal speed itself is never damped in
## air - that is what makes slide-jump chaining conserve momentum.
@export var air_control: float = 18.0
## Falling is heavier than rising.
##
## A symmetric arc is the single loudest source of "floaty": real weight is sold on
## the way down, and holding the same gravity both ways makes the descent read as a
## slow drift back to the ground. The rise keeps its full hang time; only the fall
## is accelerated (CLAUDE.md 5.2 protects momentum, and this taxes none of it).
@export var fall_gravity_scale: float = 1.7
## Releasing jump mid-rise ends the climb early, so a tap and a hold are different
## heights. Without it every jump is one committed arc the player cannot shape,
## which is most of what reads as an animation playing rather than a jump.
@export var jump_cut_multiplier: float = 0.45
## Grace period after walking off a ledge where a jump still counts.
@export var coyote_time: float = 0.10
## A jump pressed this long before touchdown is honoured on landing.
@export var jump_buffer_time: float = 0.12

@export_group("Slide")
## One-time boost when entering a slide from a run. Not applied on bhop re-entry,
## otherwise crouch-spam would be a free accelerator.
@export var slide_boost: float = 2.5
@export var slide_friction: float = 3.0
## Below this speed the slide collapses back to a crouch-walk (we just stand up).
@export var slide_min_speed: float = 3.0
## Downhill acceleration: gravity projected on the floor plane, scaled by this.
@export var slope_accel_scale: float = 1.35
@export var slide_head_drop: float = 0.55

@export_group("Dash")
@export var dash_speed: float = 16.0
@export var dash_duration: float = 0.16
## Tokens.DASH_CHARGES - the HUD reserves three pips, so three is the design.
@export var dash_charges_max: int = 3
@export var dash_cooldown: float = 5.0
## Fraction of dash speed kept when the dash ends - this is the momentum handoff
## that makes dash -> slide chains worth learning.
@export var dash_exit_speed_fraction: float = 0.75

@export_group("Mantle")
## Forward distance probed for a wall at chest height.
@export var mantle_reach: float = 1.0
## The same probe at head height must be clear - that clearance is the ledge.
@export var mantle_clear_height: float = 1.9
@export var mantle_boost: float = 6.5

@export_group("Audio")
@export var jump_sound: AudioStream
@export var land_sound: AudioStream
@export var dash_sound: AudioStream
@export var slide_sound: AudioStream

var state: State = State.GROUNDED:
	set(value):
		if state == value:
			return
		state = value
		state_changed.emit(value)

var dash_charges := DashCharges.new()

## El frasco de atrapado del Environmental (PLAN_NEW_ENEMY_TYPES §4.2). Es lo
## único del juego que le baja la velocidad al jugador, y por eso tiene salida:
## ver `apply_snare()`.
var _snare_multiplier: float = 1.0
## Segundos de inmunidad al charco después de romperlo. Sin esto, salir dashando
## de un charco de 3m no sirve de nada - el refresco del charco te vuelve a
## agarrar en el aire, dentro del mismo charco del que estás saliendo.
var _snare_grace_left: float = 0.0

var _dash_time_left: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO
var _head_rest_height: float = 0.0
var _was_on_floor: bool = true
## Set when a slide entry already paid its boost; cleared on standing up.
var _slide_boost_spent: bool = false
var _coyote_left: float = 0.0
var _jump_buffer_left: float = 0.0
var _has_moved: bool = false


func _ready() -> void:
	dash_charges.setup(get_dash_charges_max(), get_dash_cooldown())
	if stats != null:
		stats.stats_changed.connect(_on_stats_changed)
	if head != null:
		_head_rest_height = head.position.y


func _physics_process(delta: float) -> void:
	# Antes del `body == null`: la gracia del atrapado corre igual que el reloj de
	# la carga de dash, sin depender de que haya un cuerpo al que mover.
	_snare_grace_left = maxf(_snare_grace_left - delta, 0.0)
	if body == null:
		return
	dash_charges.tick(delta)

	if Input.is_action_just_pressed("jump"):
		_jump_buffer_left = jump_buffer_time
	_jump_buffer_left = maxf(_jump_buffer_left - delta, 0.0)

	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_direction: Vector3 = (body.transform.basis * Vector3(input.x, 0.0, input.y))
	wish_direction = wish_direction.normalized() if wish_direction.length_squared() > 0.0 \
		else Vector3.ZERO
	if not _has_moved and wish_direction != Vector3.ZERO:
		_has_moved = true
		started_moving.emit()

	_handle_action_input(wish_direction)

	match state:
		State.GROUNDED:
			_tick_grounded(wish_direction, delta)
		State.AIRBORNE:
			_tick_airborne(wish_direction, delta)
		State.SLIDING:
			_tick_sliding(wish_direction, delta)
		State.DASHING:
			_tick_dashing(delta)
		State.GRAPPLING:
			_tick_grappling(delta)

	var fall_speed: float = -body.velocity.y
	body.move_and_slide()
	_post_move(fall_speed, delta)


# Public API

func get_dash_charges_available() -> int:
	return dash_charges.get_available()


func get_dash_charges_max() -> int:
	return int(round(_stat(StatsComponent.DASH_CHARGES, float(dash_charges_max))))


func get_dash_cooldown() -> float:
	return maxf(_stat(StatsComponent.DASH_COOLDOWN, dash_cooldown), 0.1)


func get_move_speed() -> float:
	var speed: float = _stat(StatsComponent.MOVE_SPEED, base_move_speed)
	# Which weapon is equipped changes between waves, so ask the player rather
	# than caching a reference the holder will invalidate on the next swap.
	var player := body as Player
	if player != null and player.weapon != null:
		speed *= player.weapon.get_move_speed_multiplier()
	return speed * _snare_multiplier


func is_sliding() -> bool:
	return state == State.SLIDING


func is_snared() -> bool:
	return _snare_multiplier < 1.0


## Frena al jugador mientras esté parado en el charco. Lo aplica `SnareZone`, en
## cada refresco, y por eso no lleva duración: el charco es el que dura.
##
## No es inmovilización, a propósito. Quitarle el control al jugador es lo más
## hostil que puede hacer un shooter, y este se apoya entero en movilidad
## (CLAUDE.md 5.2): un charco que congela pelea contra el pilar del juego. Lo que
## hace es volver caro caminar, con dos salidas que el jugador ya tiene en los
## dedos - el dash y el gancho, ver `break_snare()`. Siempre hay algo que hacer.
##
## Se ignora durante la gracia: si no, romperlo no significaría nada.
func apply_snare(multiplier: float) -> void:
	if _snare_grace_left > 0.0:
		return
	_snare_multiplier = clampf(multiplier, 0.05, 1.0)


func clear_snare() -> void:
	_snare_multiplier = 1.0


## La salida. El dash y el gancho lo rompen y compran unos segundos de gracia,
## que es lo que convierte al charco en una pregunta ("¿gasto una carga?") en vez
## de en un castigo. Las dos son acciones que ya existían y cuestan un recurso.
func break_snare() -> void:
	_snare_multiplier = 1.0
	_snare_grace_left = SNARE_GRACE


# States

func _tick_grounded(wish_direction: Vector3, delta: float) -> void:
	_apply_gravity(delta)
	var horizontal: Vector3 = _horizontal()
	var speed: float = get_move_speed()
	if wish_direction != Vector3.ZERO:
		horizontal = horizontal.move_toward(wish_direction * speed, acceleration * delta)
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, friction * delta)
	_set_horizontal(horizontal)

	if _consume_jump():
		_jump()


func _tick_airborne(wish_direction: Vector3, delta: float) -> void:
	_apply_gravity(delta)
	# Coyote and buffered jumps both resolve while technically airborne: walking off
	# a ledge puts the player here a frame before they press, and a press made just
	# before touchdown is still waiting when the floor arrives.
	if _consume_jump():
		_jump()
		return
	if Input.is_action_just_released("jump") and body.velocity.y > 0.0:
		body.velocity.y *= jump_cut_multiplier
	# Mantle: holding jump against a low ledge boosts up it instead of face-planting.
	# Momentum-killing geometry snags are a bug by decree of CLAUDE.md 5.2.
	if Input.is_action_pressed("jump") and wish_direction != Vector3.ZERO:
		_try_mantle(wish_direction)
	# Steering only - no drag. Whatever speed was earned is kept until the floor
	# or a wall takes it away.
	if wish_direction != Vector3.ZERO:
		var horizontal: Vector3 = _horizontal()
		var steering: float = _stat(StatsComponent.AIR_CONTROL, air_control)
		var target: Vector3 = horizontal + wish_direction * steering * delta
		# Air control may redirect but never accelerate past current speed.
		if target.length() > maxf(horizontal.length(), get_move_speed()):
			target = target.normalized() * maxf(horizontal.length(), get_move_speed())
		_set_horizontal(target)


func _tick_sliding(wish_direction: Vector3, delta: float) -> void:
	_apply_gravity(delta)
	var horizontal: Vector3 = _horizontal()

	# Downhill conservation: project gravity onto the floor plane and feed it back.
	var floor_normal: Vector3 = body.get_floor_normal()
	var slope: Vector3 = (Vector3.DOWN - floor_normal * Vector3.DOWN.dot(floor_normal))
	if slope.length_squared() > 0.0001:
		horizontal += slope * gravity * slope_accel_scale * delta

	# Gentle steering, much weaker than running - a slide is a commitment.
	if wish_direction != Vector3.ZERO:
		horizontal = horizontal.rotated(Vector3.UP,
			signf(wish_direction.cross(horizontal.normalized()).y) * -1.2 * delta)

	horizontal = horizontal.move_toward(Vector3.ZERO, slide_friction * delta)
	_set_horizontal(horizontal)

	if _consume_jump():
		# Slide-jump: full horizontal speed carries into the air. This is the bhop.
		_jump()
		return
	if not Input.is_action_pressed("crouch_slide") or horizontal.length() < slide_min_speed:
		_stand_up()


func _tick_dashing(delta: float) -> void:
	_dash_time_left -= delta
	# Flat, gravity-free burst: dashes go where you point, including in air.
	body.velocity = _dash_direction * dash_speed
	if _dash_time_left <= 0.0:
		_set_horizontal(_dash_direction * dash_speed * dash_exit_speed_fraction)
		body.velocity.y = 0.0
		state = State.SLIDING if Input.is_action_pressed("crouch_slide") \
			and body.is_on_floor() else _fallback_state()


func _tick_grappling(delta: float) -> void:
	if grapple == null or grapple.should_release():
		if grapple != null:
			grapple.release()
		state = _fallback_state()
		return
	body.velocity = grapple.get_pull_velocity(body.velocity, delta)
	if Input.is_action_just_released("grapple") or Input.is_action_just_pressed("jump"):
		grapple.release()
		state = _fallback_state()


# Transitions

func _handle_action_input(wish_direction: Vector3) -> void:
	if state == State.DASHING or state == State.GRAPPLING:
		return

	if Input.is_action_just_pressed("dash"):
		_try_dash(wish_direction)
		return

	if Input.is_action_just_pressed("grapple") and grapple != null and grapple.try_fire():
		state = State.GRAPPLING
		break_snare()
		return

	if Input.is_action_just_pressed("crouch_slide") and state == State.GROUNDED:
		_try_slide(true)


func _try_dash(wish_direction: Vector3) -> void:
	dash_charges.set_max_charges(get_dash_charges_max())
	dash_charges.set_cooldown(get_dash_cooldown())
	if not dash_charges.try_consume():
		return
	# Dash follows input; with no input it goes where the player faces.
	_dash_direction = wish_direction if wish_direction != Vector3.ZERO \
		else -(body.global_transform.basis.z)
	_dash_direction.y = 0.0
	_dash_direction = _dash_direction.normalized()
	_dash_time_left = dash_duration
	state = State.DASHING
	break_snare()
	AudioPool.play_3d(dash_sound, body.global_position, AudioPool.BUS_WORLD)
	EventBus.dash_used.emit(dash_charges.get_available())


func _try_slide(with_boost: bool) -> void:
	var horizontal: Vector3 = _horizontal()
	if horizontal.length() < slide_min_speed:
		return
	if with_boost and not _slide_boost_spent:
		_set_horizontal(horizontal + horizontal.normalized() * slide_boost)
		_slide_boost_spent = true
	state = State.SLIDING
	AudioPool.play_3d(slide_sound, body.global_position, AudioPool.BUS_WORLD)
	_set_head_height(_head_rest_height - slide_head_drop)


func _stand_up() -> void:
	state = State.GROUNDED
	_slide_boost_spent = false
	_set_head_height(_head_rest_height)


## True when a jump should fire this frame, and consumes whatever allowed it.
##
## Three ways in, and they are distinct affordances rather than redundancy: holding
## the button is auto-bhop, so chaining slides never demands frame-perfect taps; the
## buffer honours a press made just before the floor arrived; coyote covers a press
## made just after walking off a ledge. The last two are what separate "the game
## dropped my input" from "I mistimed that" - the arena is built on jump links and
## disappearing platforms, where both misses happen constantly.
func _consume_jump() -> bool:
	if not body.is_on_floor() and _coyote_left <= 0.0:
		return false
	if not Input.is_action_pressed("jump") and _jump_buffer_left <= 0.0:
		return false
	_jump_buffer_left = 0.0
	_coyote_left = 0.0
	return true


func _jump() -> void:
	body.velocity.y = _stat(StatsComponent.JUMP_VELOCITY, jump_velocity)
	state = State.AIRBORNE
	_set_head_height(_head_rest_height)
	AudioPool.play_3d(jump_sound, body.global_position, AudioPool.BUS_WORLD)
	jumped.emit()


func _post_move(fall_speed: float, delta: float) -> void:
	var on_floor: bool = body.is_on_floor()

	# The rising check matters: on the frame a jump fires the body is often still
	# touching the floor, and refreshing coyote there would hand out a second jump.
	if on_floor and body.velocity.y <= 0.0:
		_coyote_left = coyote_time
	else:
		_coyote_left = maxf(_coyote_left - delta, 0.0)

	if state == State.GROUNDED and not on_floor:
		state = State.AIRBORNE
	elif state == State.AIRBORNE and on_floor:
		landed.emit(fall_speed)
		if fall_speed > 4.0:
			AudioPool.play_3d(land_sound, body.global_position, AudioPool.BUS_WORLD)
		# Landing with crouch held re-enters the slide at full speed, boost-free:
		# this is the chain that makes downhill runs and pad routes flow.
		if Input.is_action_pressed("crouch_slide") \
				and _horizontal().length() >= slide_min_speed:
			_try_slide(false)
		else:
			_stand_up()
	elif state == State.SLIDING and not on_floor:
		state = State.AIRBORNE

	_was_on_floor = on_floor


## A wall at chest height with clear space at head height is a mantleable ledge.
func _try_mantle(wish_direction: Vector3) -> void:
	if body.velocity.y > 2.0:
		return  # Already rising fast enough; do not stack boosts.
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var chest: Vector3 = body.global_position + Vector3.UP * 0.9
	var chest_query := PhysicsRayQueryParameters3D.create(
		chest, chest + wish_direction * mantle_reach, PhysicsLayers.WORLD)
	if space.intersect_ray(chest_query).is_empty():
		return
	var head_level: Vector3 = body.global_position + Vector3.UP * mantle_clear_height
	var head_query := PhysicsRayQueryParameters3D.create(
		head_level, head_level + wish_direction * mantle_reach, PhysicsLayers.WORLD)
	if not space.intersect_ray(head_query).is_empty():
		return
	body.velocity.y = mantle_boost
	mantled.emit()


# Helpers

func _fallback_state() -> State:
	return State.GROUNDED if body.is_on_floor() else State.AIRBORNE


func _apply_gravity(delta: float) -> void:
	if body.is_on_floor():
		return
	var scale: float = 1.0 if body.velocity.y > 0.0 else fall_gravity_scale
	body.velocity.y -= gravity * scale * delta


func _horizontal() -> Vector3:
	return Vector3(body.velocity.x, 0.0, body.velocity.z)


func _set_horizontal(horizontal: Vector3) -> void:
	body.velocity.x = horizontal.x
	body.velocity.z = horizontal.z


func _set_head_height(height: float) -> void:
	if head == null:
		return
	var tween: Tween = create_tween()
	tween.tween_property(head, "position:y", height, 0.12)


func _stat(stat_key: StringName, base_value: float) -> float:
	if stats == null:
		return base_value
	return stats.get_stat_from(stat_key, base_value)


func _on_stats_changed() -> void:
	dash_charges.set_max_charges(get_dash_charges_max())
	dash_charges.set_cooldown(get_dash_cooldown())
