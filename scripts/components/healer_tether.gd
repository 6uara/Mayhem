class_name HealerTether
extends Node3D
## Los haces que unen a un Healer con todo lo que esta curando.
##
## Por que reemplaza al haz unico que habia antes: el Healer cura a **todos** los
## heridos que tiene al alcance, pero solo dibujaba una linea, al mas lastimado.
## Desde afuera eso se lee como "esta curando a ese", cuando en realidad esta
## sosteniendo a media oleada - y el jugador que decide a quien dispara primero
## estaba decidiendo con informacion falsa.
##
## Ademas el haz viejo no se apagaba nunca: se quedaba apuntando al ultimo
## objetivo mientras el Healer caminaba sin curar a nadie, asi que la linea dejo
## de significar "esto esta pasando ahora".
##
## Los haces se crean la primera vez que hacen falta y se quedan con el cuerpo.
## Un cuerpo pooleado que despues renace como Rusher se los lleva apagados, que
## cuesta menos que destruirlos y volver a crearlos cada vez que spawnea un
## Healer.

## Cuantos haces pueden dibujarse a la vez.
##
## Cuatro y no "todos": mas que eso es una maraña que ya no dice a quien esta
## curando, y el Healer con cinco heridos alrededor es exactamente el caso en
## que la respuesta es "matalo a el" y no "fijate a cual cura". Se priorizan los
## mas lastimados, que son los que mas justifican el gasto de balas.
const MAX_BEAMS: int = 4

## Grosor del haz, en metros. Mas fino que el viejo (0.07): son varios ahora, y
## cuatro lineas gordas tapan a los enemigos que estan senalando.
const BEAM_THICKNESS: float = 0.05

## Cuanto dura el destello de un pulso de cura y cuanto brilla en el pico.
##
## El haz de base es tenue a proposito: lo que tiene que saltar a la vista no es
## que exista una conexion sino **cada vez que entra cura**, que es lo que
## convierte la linea en un caudal y no en un adorno.
const PULSE_TIME: float = 0.30
const PULSE_ENERGY: float = 4.5
const IDLE_ENERGY: float = 1.1
## Alpha del haz en reposo y en el pico del pulso.
const IDLE_ALPHA: float = 0.35
const PULSE_ALPHA: float = 0.95

## Cuanto tarda en apagarse el haz cuando el objetivo deja de necesitar cura.
## No es instantaneo para que un Healer curando de a pulsos no parpadee entre
## uno y otro.
const FADE_TIME: float = 0.45

## Altura del ancla sobre el objetivo, en metros. Apunta al cuerpo y no a los
## pies para que la linea no se hunda en el piso.
const TARGET_HEIGHT: float = 1.0

var _beams: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
## Objetivo de cada haz y cuanto le queda de vida a ese haz.
var _targets: Array[Node3D] = []
var _lifetimes: PackedFloat32Array = PackedFloat32Array()
## Tiempo restante del destello de cada haz.
var _pulses: PackedFloat32Array = PackedFloat32Array()

## Desde donde salen los haces, relativo al Healer.
var _origin_height: float = 1.4
var _color: Color = Tokens.HEAL


func _ready() -> void:
	set_process(false)


# Public API

## Prende el componente para este arquetipo. Un arquetipo sin tether lo apaga y
## no paga nada mas.
func configure(enabled: bool, origin_height: float) -> void:
	_origin_height = origin_height
	clear()
	set_process(enabled)
	visible = enabled


## Quienes estan recibiendo cura **ahora**. Se llama en cada pulso del Healer,
## no cada frame: entre pulso y pulso los haces siguen vivos por su cuenta y se
## apagan solos con FADE_TIME.
##
## El color es siempre Tokens.HEAL y nunca el del arquetipo: el mint existe
## justamente para esto, y pintar el haz del violeta del Healer lo volvia una
## parte mas de su cuerpo en vez de un efecto que se puede leer a la distancia.
func pulse(targets: Array) -> void:
	if not is_processing():
		return
	var count: int = mini(targets.size(), MAX_BEAMS)
	for i: int in count:
		var target := targets[i] as Node3D
		if target == null:
			continue
		var index: int = _slot_for(target)
		_ensure_beam(index)
		_targets[index] = target
		_lifetimes[index] = FADE_TIME
		_pulses[index] = PULSE_TIME


## Apaga todos los haces ya. Lo llama el cuerpo al volver del pool: un Rusher no
## puede heredar las lineas del Healer que ocupaba ese cuerpo.
func clear() -> void:
	for i: int in _beams.size():
		_targets[i] = null
		_lifetimes[i] = 0.0
		_pulses[i] = 0.0
		_beams[i].visible = false


## Cuantos haces estan dibujados ahora mismo. Para los tests y para el bono de
## prioridad: "lo mataste mientras curaba" es exactamente esto siendo mayor a
## cero.
func get_active_count() -> int:
	var count: int = 0
	for i: int in _beams.size():
		if _lifetimes[i] > 0.0 and _targets[i] != null and is_instance_valid(_targets[i]):
			count += 1
	return count


func is_active() -> bool:
	return get_active_count() > 0


# Private

func _process(delta: float) -> void:
	for i: int in _beams.size():
		if _lifetimes[i] <= 0.0:
			continue
		_lifetimes[i] -= delta
		if _pulses[i] > 0.0:
			_pulses[i] -= delta
		var target: Node3D = _targets[i]
		if _lifetimes[i] <= 0.0 or target == null or not is_instance_valid(target):
			_targets[i] = null
			_lifetimes[i] = 0.0
			_beams[i].visible = false
			continue
		_draw_beam(i, target)


## Estira un haz entre el Healer y su objetivo.
##
## La linea de vision no se simula: el haz atraviesa lo que haya en el medio a
## proposito. Cortarlo contra una columna esconderia la conexion justo cuando el
## Healer esta mejor cubierto, que es cuando mas falta hace verla.
func _draw_beam(index: int, target: Node3D) -> void:
	var from: Vector3 = global_position + Vector3.UP * _origin_height
	var to: Vector3 = target.global_position + Vector3.UP * TARGET_HEIGHT
	var offset: Vector3 = to - from
	var length: float = offset.length()
	var beam: MeshInstance3D = _beams[index]
	if length < 0.1:
		beam.visible = false
		return
	beam.visible = true
	beam.global_position = from
	beam.look_at(to, Vector3.UP)
	beam.scale = Vector3(1.0, 1.0, length)

	# El pulso viaja de tenue a brillante y vuelve, en vez de encenderse y
	# apagarse: lo que se tiene que leer es que algo corrio por la linea.
	var pulse: float = clampf(_pulses[index] / PULSE_TIME, 0.0, 1.0)
	# Y se apaga con lo que le queda de vida, para que el final sea un fundido y
	# no un corte.
	var fade: float = clampf(_lifetimes[index] / FADE_TIME, 0.0, 1.0)
	var material: StandardMaterial3D = _materials[index]
	material.emission_energy_multiplier = lerpf(IDLE_ENERGY, PULSE_ENERGY, pulse)
	var tint: Color = _color
	tint.a = lerpf(IDLE_ALPHA, PULSE_ALPHA, pulse) * fade
	material.albedo_color = tint
	material.emission = _color


## El haz que ya esta apuntando a este objetivo, o el mas gastado si es nuevo.
## Reusar el mismo slot para el mismo objetivo es lo que hace que un objetivo
## curado dos veces seguidas pulse en vez de saltar entre lineas distintas.
func _slot_for(target: Node3D) -> int:
	for i: int in _beams.size():
		if _targets[i] == target:
			return i
	var weakest: int = 0
	var weakest_life: float = INF
	for i: int in MAX_BEAMS:
		if i >= _beams.size():
			return i
		if _lifetimes[i] < weakest_life:
			weakest_life = _lifetimes[i]
			weakest = i
	return weakest


## Crea el haz `index` si todavia no existe. Perezoso: un Rusher nunca paga
## cuatro MeshInstance3D que no va a usar.
func _ensure_beam(index: int) -> void:
	while _beams.size() <= index:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(BEAM_THICKNESS, BEAM_THICKNESS, 1.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = _color
		material.emission_enabled = true
		material.emission = _color
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# Aditivo y sin escribir profundidad: es luz, no un palo pintado, y asi
		# no recorta a los enemigos que cruzan por delante.
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.no_depth_test = false
		material.cull_mode = BaseMaterial3D.CULL_DISABLED

		var beam := MeshInstance3D.new()
		beam.mesh = mesh
		beam.material_override = material
		beam.visible = false
		# En espacio de mundo: el haz se estira entre dos puntos globales, asi que
		# no puede heredar la rotacion ni la escala del cuerpo que lo dispara.
		beam.top_level = true
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beam)

		_beams.append(beam)
		_materials.append(material)
		_targets.append(null)
		_lifetimes.append(0.0)
		_pulses.append(0.0)
