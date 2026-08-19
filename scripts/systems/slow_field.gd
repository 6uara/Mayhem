class_name SlowField
extends ThrownUtility
## Puddle of slow. Enemies inside move at `slow_multiplier` speed, which turns a
## rusher pack into something you can outrun and shoot.

## Cada cuanto se vuelve a mirar quien esta adentro.
##
## Misma idea que el intervalo de separacion del enemigo: nadie ve la diferencia
## entre enterarse ahora o dentro de una decima de que un rusher cruzo el borde
## del charco, y a 60 por segundo esto recorria a todos los enemigos vivos por
## cada charco en el piso. El multiplicador se re-aplica en cada refresco, asi
## que el efecto no parpadea entre uno y otro.
const REFRESH_INTERVAL: float = 0.1

@export var slow_multiplier: float = 0.45
@export var field_mesh: MeshInstance3D

var _time_left: float = 0.0
var _refresh_timer: float = 0.0
## Enemies currently slowed by this field, so the effect is lifted on exit.
var _affected: Array[Enemy] = []


func _physics_process(delta: float) -> void:
	super(delta)
	if _time_left <= 0.0:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_dismiss()
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = REFRESH_INTERVAL
		_refresh_affected()


func _activate() -> void:
	_time_left = data.effect_duration if data != null else 5.0
	# El primer refresco es inmediato: el charco tiene que frenar a quien ya
	# estaba parado ahi cuando cayo, no una decima despues.
	_refresh_timer = 0.0
	if field_mesh != null:
		var radius: float = data.effect_radius if data != null else 5.0
		field_mesh.visible = true
		field_mesh.scale = Vector3(radius, 1.0, radius)


func _on_released() -> void:
	super()
	_clear_affected()
	_time_left = 0.0
	if field_mesh != null:
		field_mesh.visible = false


func _refresh_affected() -> void:
	var inside: Array[Enemy] = _enemies_in_radius(data.effect_radius if data != null else 5.0)
	for enemy: Enemy in _affected:
		if is_instance_valid(enemy) and not inside.has(enemy):
			enemy.clear_slow()
	for enemy: Enemy in inside:
		enemy.apply_slow(slow_multiplier)
	_affected = inside


func _clear_affected() -> void:
	for enemy: Enemy in _affected:
		if is_instance_valid(enemy):
			enemy.clear_slow()
	_affected.clear()


func _dismiss() -> void:
	_clear_affected()
	if field_mesh != null:
		field_mesh.visible = false
	ObjectPool.release(self)
