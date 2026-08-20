class_name GrappleComponent
extends Node
## Fires at surfaces on the grapple_anchor layer, pulls the player along a controlled
## arc and preserves exit momentum. Cooldown-based, hard max range, and the HUD reads
## `is_anchor_in_range` every frame to drive the reticle state change.

signal anchor_state_changed(is_available: bool)

@export var body: CharacterBody3D
## Ray source - the head pivot, so the grapple goes where the player looks.
@export var aim_node: Node3D
@export var stats: StatsComponent

@export_group("Tuning")
@export var max_range: float = 28.0
@export var pull_speed: float = 22.0
## How hard velocity bends toward the anchor. Lower = wider, floatier arcs.
@export var pull_acceleration: float = 40.0
@export var cooldown: float = 5.0
@export var arrive_distance: float = 2.5
## Small upward kick on release so ledge exits feel generous, not sticky.
@export var release_up_boost: float = 2.0
## Grace window where should_release() ignores "moving away from the anchor".
##
## should_release() is evaluated the same physics frame try_fire() succeeds, before
## the pull has touched velocity even once. Firing while backpedaling, strafing, or
## carrying any residual velocity with a component away from the anchor made that
## check true on frame one - the grapple ended before it started, and all the
## player felt was release_up_boost: a small hop, not a swing. Distance-to-anchor
## still ends a grapple instantly regardless of this window; only the velocity
## direction check waits for the pull to actually have a say.
@export var min_flight_time: float = 0.15
## Cuanto hay que quedarse en el piso para que un encadenado se cobre el cooldown.
##
## Soltar un grapple en el aire no arranca el cooldown: se puede reenganchar al
## instante y encadenar tantos como el terreno aguante. La cuenta empieza recien
## al tocar el piso, y solo si el jugador se queda ahi este tiempo seguido.
## Rebotar en el suelo y volver a saltar antes de que termine no gasta nada, que
## es lo que mantiene vivo un recorrido que pasa rozando una plataforma.
##
## Es el limite que el playtest pidio explicitamente: encadenar libre mientras
## estas en movimiento, y el costo lo pagas cuando frenas.
@export var ground_grace: float = 2.0

@export_group("Audio")
@export var fire_sound: AudioStream
@export var release_sound: AudioStream

var is_grappling: bool = false
## Cached each physics frame; true when the reticle is over a usable anchor.
var is_anchor_in_range: bool = false

var _anchor: Vector3 = Vector3.ZERO
var _cooldown_left: float = 0.0
var _fired_at_msec: int = 0
## Hay un grapple soltado en el aire cuyo cooldown todavia no se cobro.
var _chain_pending: bool = false
## Segundos seguidos con los pies en el piso desde que se debe ese cooldown.
var _grounded_time: float = 0.0


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_tick_chain_debt(delta)
	var available: bool = not is_grappling and _cooldown_left <= 0.0 \
		and not _find_anchor().is_empty()
	if available != is_anchor_in_range:
		is_anchor_in_range = available
		anchor_state_changed.emit(available)


# Public API

func try_fire() -> bool:
	if is_grappling or _cooldown_left > 0.0:
		return false
	var hit: Dictionary = _find_anchor()
	if hit.is_empty():
		return false
	_anchor = hit["position"]
	is_grappling = true
	_fired_at_msec = Time.get_ticks_msec()
	AudioPool.play_3d(fire_sound, body.global_position, AudioPool.BUS_WORLD)
	EventBus.grapple_started.emit(_anchor)
	return true


## Soltar en el aire no cobra el cooldown, solo lo deja anotado: el grapple
## queda disponible para reengancharse en el mismo salto.
##
## El cooldown no desaparece, se difiere. Lo cobra _tick_chain_debt() cuando el
## jugador se queda quieto en el piso, asi que el recurso sigue siendo limitado
## para quien lo usa como escape y deja de serlo para quien lo usa para moverse.
## Esa es la distincion que el cooldown plano no podia hacer: castigaba igual al
## que encadenaba tres anclas cruzando el arena que al que se colgaba una vez
## para salir de un apuro.
func release() -> void:
	if not is_grappling:
		return
	is_grappling = false
	if _is_airborne():
		_chain_pending = true
		_grounded_time = 0.0
	else:
		_cooldown_left = get_cooldown()
	body.velocity.y += release_up_boost
	AudioPool.play_3d(release_sound, body.global_position, AudioPool.BUS_WORLD)
	EventBus.grapple_ended.emit()


## Bends the current velocity toward the anchor; exit momentum is whatever the
## arc built up - nothing is zeroed on release.
func get_pull_velocity(current: Vector3, delta: float) -> Vector3:
	var desired: Vector3 = (_anchor - body.global_position).normalized() * pull_speed
	return current.move_toward(desired, pull_acceleration * delta)


## True when the player has arrived or the anchor ended up behind them.
func should_release() -> bool:
	if not is_grappling:
		return true
	var to_anchor: Vector3 = _anchor - body.global_position
	if to_anchor.length() <= arrive_distance:
		return true
	var flight_time: float = float(Time.get_ticks_msec() - _fired_at_msec) / 1000.0
	if flight_time < min_flight_time:
		return false
	return to_anchor.dot(body.velocity) < 0.0 and body.velocity.length() > 1.0


func get_anchor() -> Vector3:
	return _anchor


func get_cooldown() -> float:
	if stats == null:
		return cooldown
	return maxf(stats.get_stat_from(StatsComponent.GRAPPLE_COOLDOWN, cooldown), 0.1)


func get_max_range() -> float:
	if stats == null:
		return max_range
	return stats.get_stat_from(StatsComponent.GRAPPLE_RANGE, max_range)


# Private

## Cobra el cooldown diferido despues de `ground_grace` segundos seguidos de
## piso. El contador se reinicia al despegar, no se acumula: tocar el suelo tres
## veces medio segundo cada una no suma un segundo y medio, porque quien hace eso
## se sigue moviendo y es justo a quien el encadenado esta pensado para premiar.
func _tick_chain_debt(delta: float) -> void:
	if not _chain_pending:
		return
	if _is_airborne():
		_grounded_time = 0.0
		return
	_grounded_time += delta
	if _grounded_time < ground_grace:
		return
	_chain_pending = false
	_grounded_time = 0.0
	_cooldown_left = get_cooldown()


## Un body sin `is_on_floor` (los stubs de los tests, o cualquier cosa que no sea
## un CharacterBody3D) cuenta como si estuviera en el piso: es la respuesta
## conservadora - cobra el cooldown - y nunca regala grapples infinitos por un
## error de wiring.
func _is_airborne() -> bool:
	if body == null:
		return false
	return not body.is_on_floor()


func _find_anchor() -> Dictionary:
	if aim_node == null or body == null:
		return {}
	var from: Vector3 = aim_node.global_position
	var to: Vector3 = from - aim_node.global_transform.basis.z * get_max_range()
	# World geometry blocks the ray, so anchors cannot be grappled through walls.
	var query := PhysicsRayQueryParameters3D.create(from, to,
		PhysicsLayers.WORLD | PhysicsLayers.GRAPPLE_ANCHOR)
	query.exclude = [body.get_rid()]
	var hit: Dictionary = body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider := hit["collider"] as CollisionObject3D
	if collider == null or (collider.collision_layer & PhysicsLayers.GRAPPLE_ANCHOR) == 0:
		return {}
	return hit
