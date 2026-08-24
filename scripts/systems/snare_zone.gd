class_name SnareZone
extends HazardZone
## El charco de atrapado del Environmental: no lastima, te frena.
##
## Es un `HazardZone` y no un área propia por el mismo motivo que el charco de
## ácido: así hereda la ley entera - el aviso de 0.6s antes de armarse y el decal
## dibujado al radio exacto del efecto. Un área nueva podría haberse salteado las
## dos cosas y ningún test habría fallado.
##
## `damage` queda en 0 a propósito. Frenar y quemar a la vez es dos castigos por
## una misma decisión, y el que importa acá es el de posición: lo que este charco
## le cobra al jugador es la movilidad, que es su pilar (PLAN_NEW_ENEMY_TYPES
## §4.2). Si algún día se le quiere poner daño, la clase base ya lo hace.
##
## No inmoviliza: ralentiza fuerte y tiene salida (`MovementComponent.break_snare()`
## - dash o gancho). Ver el comentario de `apply_snare()` para el porqué.

## Cada cuánto se vuelve a mirar quién está adentro.
##
## Mismo número y mismo motivo que `SlowField.REFRESH_INTERVAL`: nadie ve la
## diferencia entre enterarse ahora o dentro de una décima de que alguien cruzó el
## borde, y a 60 por segundo esto recorría a todos los cuerpos por cada charco.
## El efecto se re-aplica en cada refresco, así que no parpadea entre uno y otro.
const REFRESH_INTERVAL: float = 0.1

## Qué fracción de su velocidad conserva el que está adentro.
@export_range(0.05, 1.0, 0.05) var snare_multiplier: float = 0.35

var _refresh_timer: float = 0.0
## A quiénes está frenando ahora mismo, para poder soltarlos al salir. Sin esta
## lista un charco que expira deja al jugador lento para siempre.
var _snared: Array[Node3D] = []


func _physics_process(delta: float) -> void:
	super(delta)
	if not is_armed:
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = REFRESH_INTERVAL
		_refresh_snared()


## El charco se reusa desde el pool, así que lo primero de cada vida es no
## arrastrar a los del charco anterior.
func setup(hazard_damage: float, hazard_radius: float, hazard_duration: float,
		hazard_attacker: Node = null) -> void:
	_release_all()
	# Inmediato: el charco tiene que frenar a quien ya estaba parado ahí cuando
	# cayó, no una décima después.
	_refresh_timer = 0.0
	super(hazard_damage, hazard_radius, hazard_duration, hazard_attacker)


func _on_released() -> void:
	_release_all()


# Private

func _refresh_snared() -> void:
	var inside: Array[Node3D] = []
	for body: Node3D in _bodies_inside:
		if is_instance_valid(body) and _affects(body) and _is_standing_in_it(body):
			inside.push_back(body)
	for body: Node3D in _snared:
		if is_instance_valid(body) and not inside.has(body):
			_release(body)
	for body: Node3D in inside:
		_snare(body)
	_snared = inside


## A quién agarra: sólo hostiles del que lo tiró, igual que el daño de la clase
## base. Un charco sin dueño -una trampa del arena- agarra a todo el mundo.
func _affects(body: Node3D) -> bool:
	if not body.is_in_group(&"player") and not body.is_in_group(&"enemy"):
		return false
	if is_instance_valid(attacker) and not Factions.hostile(attacker, body):
		return false
	return true


func _snare(body: Node3D) -> void:
	var player := body as Player
	if player != null:
		if player.movement != null:
			player.movement.apply_snare(snare_multiplier)
		return
	var enemy := body as Enemy
	if enemy != null:
		enemy.apply_slow(snare_multiplier)


func _release(body: Node3D) -> void:
	var player := body as Player
	if player != null:
		if player.movement != null:
			player.movement.clear_snare()
		return
	var enemy := body as Enemy
	if enemy != null:
		enemy.clear_slow()


func _release_all() -> void:
	for body: Node3D in _snared:
		if is_instance_valid(body):
			_release(body)
	_snared.clear()


func _expire() -> void:
	_release_all()
	super()
