extends Node3D
## Lo que un gadget le hizo a un enemigo, a la vista: aturdido o ralentizado.
##
## Antes los dos efectos cambiaban como se movia el enemigo y nada mas, y en una
## horda eso no se distingue de un enemigo que frena solo. Ahora:
##
## - Aturdido: chispas girando sobre la cabeza y el contorno pulsando en el color
##   de la granada (Tokens.GADGET_STUN), hasta que se le pasa.
## - Ralentizado: el contorno pasa al color del campo lento (Tokens.GADGET_SLOW)
##   mientras esta adentro.
##
## Solo procesa mientras hay algo que mostrar: el pool tiene decenas de enemigos
## y casi todos, casi siempre, no tienen nada.

const SPARK_COUNT: int = 4
const SPARK_SIZE: float = 0.07
const ORBIT_RADIUS: float = 0.3
## Pulsos por segundo del contorno de un aturdido.
const PULSE_RATE: float = 3.0

var _enemy: Enemy
var _pivot: Node3D
var _stun_left: float = 0.0
var _slowed: bool = false
var _time: float = 0.0


func setup(enemy: Enemy) -> void:
	_enemy = enemy
	if _pivot == null:
		_build_sparks()
	reset()


## Vuelta a nada: un cuerpo que sale del pool no puede traer las chispas del
## enemigo anterior.
func reset() -> void:
	_stun_left = 0.0
	_slowed = false
	if _pivot != null:
		_pivot.visible = false
	set_process(false)
	_apply_outline()


func stun(duration: float) -> void:
	_stun_left = maxf(_stun_left, duration)
	_place_sparks()
	_pivot.visible = true
	set_process(true)


func set_slowed(on: bool) -> void:
	if on == _slowed:
		return
	_slowed = on
	set_process(_stun_left > 0.0 or _slowed)
	_apply_outline()


func is_stunned() -> bool:
	return _stun_left > 0.0


func _process(delta: float) -> void:
	_time += delta
	if _stun_left > 0.0:
		_stun_left = maxf(_stun_left - delta, 0.0)
		_pivot.rotate_y(Tokens.STATUS_RING_SPEED * delta)
		if _stun_left <= 0.0:
			_pivot.visible = false
	if _stun_left <= 0.0 and not _slowed:
		set_process(false)
	_apply_outline()


func _apply_outline() -> void:
	if _enemy == null or _enemy.data == null:
		return
	var colour: Color = _enemy.data.body_color
	if _slowed:
		colour = Tokens.GADGET_SLOW
	if _stun_left > 0.0:
		var pulse: float = 0.5 + 0.5 * sin(_time * TAU * PULSE_RATE)
		colour = colour.lerp(Tokens.GADGET_STUN, pulse)
	_enemy.set_outline_color(colour)


## Sobre la cabeza del arquetipo, que es lo que el jugador esta mirando.
func _place_sparks() -> void:
	if _enemy != null and _enemy.data != null:
		_pivot.position = Vector3(0.0, _enemy.data.head_offset + Tokens.STATUS_RING_LIFT, 0.0)


func _build_sparks() -> void:
	_pivot = Node3D.new()
	_pivot.name = "StunSparks"
	add_child(_pivot)
	var spark := SphereMesh.new()
	spark.radius = SPARK_SIZE
	spark.height = SPARK_SIZE * 2.0
	spark.radial_segments = 4
	spark.rings = 2
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Tokens.GADGET_STUN
	material.emission_enabled = true
	material.emission = Tokens.GADGET_STUN
	material.emission_energy_multiplier = 2.5
	spark.material = material
	for index: int in SPARK_COUNT:
		var angle: float = TAU * float(index) / float(SPARK_COUNT)
		var instance := MeshInstance3D.new()
		instance.mesh = spark
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.position = Vector3(cos(angle), 0.0, sin(angle)) * ORBIT_RADIUS
		_pivot.add_child(instance)
	_pivot.visible = false
