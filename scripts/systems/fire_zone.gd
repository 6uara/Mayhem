class_name FireZone
extends HazardZone
## El piso que arde de Scorched Earth: un `HazardZone` con cara de fuego.
##
## Quema igual que el charco de acido -mismo aviso, mismo contorno, mismo tick-
## pero no puede verse igual. El acido es de un enemigo (un frasco, una trampa);
## este es de la transmision, sin dueño, y quema a todos. Si se vieran iguales,
## el jugador leeria "hay un Flask vivo cerca" donde no lo hay.
##
## Lo que suma sobre la clase base es lo vertical: llamas, chispas y una luz
## que titila. Todo eso sale de la misma `spread`/`evaporate` que mueve el
## decal, asi que crece mientras avisa y se apaga mientras se seca, sin un
## reloj propio que se pueda desincronizar.
##
## Las llamas nacen adentro del radio mas chico que el contorno puede tener
## (`radius * (1 - shape_irregularity)`): ninguna llama sale de piso que no
## quema, ni siquiera en el hueco entre dos lobulos.

@export var flames: GPUParticles3D
@export var embers: GPUParticles3D
@export var glow_light: OmniLight3D
@export var light_energy: float = 1.4
## Alcance de la luz, en multiplos del radio: ilumina un poco mas alla del
## fuego, que es como se ve un fuego, sin pintar de naranja media arena.
@export var light_range_multiplier: float = 2.0

## Cuanto fuego hay ahora mismo, 0..1: `spread * (1 - evaporate)`.
var _intensity: float = 0.0
var _flicker_time: float = 0.0


func _process(delta: float) -> void:
	if glow_light == null:
		return
	_flicker_time += delta
	# Dos senos que no comparten periodo: titila sin que se note el loop.
	var flicker: float = 0.82 + 0.1 * sin(_flicker_time * 17.0) \
		+ 0.08 * sin(_flicker_time * 29.0 + 1.3)
	glow_light.light_energy = light_energy * _intensity * flicker


# Private

func _apply_radius() -> void:
	super()
	var inner: float = radius * (1.0 - shape_irregularity)
	for particles: GPUParticles3D in [flames, embers]:
		var process := particles.process_material as ParticleProcessMaterial if particles != null else null
		if process != null:
			process.emission_ring_radius = inner
	if glow_light != null:
		glow_light.omni_range = radius * light_range_multiplier


## Cada vida arranca sin las llamas de la anterior: un fuego reusado del pool
## no puede aparecer ya ardiendo donde estaba el otro.
func _spread_in() -> void:
	for particles: GPUParticles3D in [flames, embers]:
		if particles != null:
			particles.restart()
			particles.emitting = true
	super()


func _set_look(spread: float, evaporate: float) -> void:
	super(spread, evaporate)
	_intensity = spread * (1.0 - evaporate)
	for particles: GPUParticles3D in [flames, embers]:
		if particles != null:
			particles.amount_ratio = _intensity


func _on_released() -> void:
	super()
	_intensity = 0.0
	for particles: GPUParticles3D in [flames, embers]:
		if particles != null:
			particles.emitting = false
	if glow_light != null:
		glow_light.light_energy = 0.0
