class_name TelegraphComponent
extends Node
## The one telegraph system every interactive object in the arena runs on.
##
## SPEC-VIEWMODELS 3.4: all seven telegraph types are the same thing - a mesh, an
## unlit emissive material and a state enum. Centralising it is what makes the
## arena legible: "cyan pulsing" means the same thing on a pad and on a
## platform, because it is literally the same code.
##
## Every state pairs colour with MOTION (pulse, fill, rise, blink), so a
## colour-blind player reads the signal from the animation alone.

signal state_changed(new_state: State)

enum State {
	IDLE,       ## present but not offering anything right now
	AVAILABLE,  ## usable, and saying so
	WARNING,    ## about to become dangerous, or about to vanish
	ACTIVE,     ## doing its thing
}

## The one law (SPEC-VIEWMODELS 3.2), with a fifth meaning added for grapple
## anchors (2026-10-28). No other colour may appear on an
## interactive surface, and none of these five is ever reused for another meaning.
enum Meaning {
	TRAVERSAL,  ## cyan: you can use this
	HAZARD,     ## acid: this will hurt you
	PICKUP,     ## amber: take this
	SPAWN,      ## magenta: enemies come from here
	GRAPPLE,    ## violet: you can hook onto this
}

@export var meaning: Meaning = Meaning.TRAVERSAL
## Meshes driven by this telegraph. All get the same unlit emissive material, so
## an interactive object can never disappear into shadow.
@export var meshes: Array[MeshInstance3D] = []
## Para meshes que son un modelo con textura (el gancho del ancla, la plataforma
## movil): el color va encima como material_overlay, un brillo aditivo que pulsa
## igual que el material plano, en vez de reemplazar la textura por un color liso.
## El modelo se sigue leyendo como lo que es y el estado se sigue viendo en el
## color y el movimiento.
@export var overlay: bool = false
## Que fraccion de la energia de emision llega al overlay. Sumado sobre la
## textura, la energia del material plano lavaba el modelo hasta dejarlo cyan.
@export var overlay_strength: float = 0.1

@export_group("Emission")
@export var idle_energy: float = 0.6
@export var available_energy: float = 1.0
@export var warning_energy: float = 1.6
@export var active_energy: float = 2.0

var state: State = State.IDLE:
	set(value):
		if state == value:
			return
		state = value
		_enter_state()
		state_changed.emit(value)

var _materials: Array[StandardMaterial3D] = []
## Meshes that arrived with their own ShaderMaterial - a lava pool, a portal - keep
## it. Driving "glow_energy" on it is how the same WARNING blink / ACTIVE pulse the
## flat materials get still reaches a custom surface, without this component ever
## needing to know what that surface looks like.
var _shader_materials: Array[ShaderMaterial] = []
var _time: float = 0.0
var _blink_step: float = 0.25
var _is_blinking: bool = false
var _pulse_period: float = 0.0


func _ready() -> void:
	_build_materials()
	_enter_state()


func _process(delta: float) -> void:
	if _materials.is_empty() and _shader_materials.is_empty():
		return
	_time += delta
	if _is_blinking:
		# A hard on/off step, not a fade: cheaper to read at a glance.
		var lit: bool = fmod(_time, _blink_step * 2.0) < _blink_step
		_set_energy(warning_energy if lit else idle_energy * 0.25)
	elif _pulse_period > 0.0:
		var wave: float = 0.5 + 0.5 * sin(_time * TAU / _pulse_period)
		_set_energy(lerpf(available_energy * 0.55, available_energy, wave))


# Public API

func get_color() -> Color:
	match meaning:
		Meaning.HAZARD: return Tokens.WORLD_HAZARD
		Meaning.PICKUP: return Tokens.WORLD_PICKUP
		Meaning.SPAWN: return Tokens.SPAWN
		Meaning.GRAPPLE: return Tokens.WORLD_GRAPPLE
	return Tokens.WORLD_TRAVERSAL


## Blink rate accelerates as a deadline approaches - the platform warning goes from
## a 0.25s step to 0.1s in its final 0.4s, so urgency is legible without a number.
func set_blink_step(step: float) -> void:
	_blink_step = maxf(step, 0.02)


func refresh_materials() -> void:
	_build_materials()
	_enter_state()


# Private

func _build_materials() -> void:
	_materials.clear()
	_shader_materials.clear()
	var tint: Color = get_color()
	for mesh: MeshInstance3D in meshes:
		if mesh == null:
			continue
		if overlay:
			var glow := StandardMaterial3D.new()
			glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			glow.albedo_color = Color.BLACK
			glow.metallic_specular = 0.0
			glow.emission_enabled = true
			glow.emission = tint
			# Si el modelo trae mapa de brillo, el overlay pulsa solo ahi: sumado
			# parejo sobre toda la malla, el gancho se leia como un bloque violeta
			# liso y se perdia la textura. Sin mapa (la plataforma) va sobre todo.
			var glow_map: Texture2D = _glow_map(mesh)
			if glow_map != null:
				glow.emission_texture = glow_map
				glow.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
			mesh.material_overlay = glow
			_materials.push_back(glow)
			continue
		var existing := mesh.material_override as ShaderMaterial
		if existing != null:
			_shader_materials.push_back(existing)
			continue
		var material := StandardMaterial3D.new()
		material.albedo_color = tint
		material.emission_enabled = true
		material.emission = tint
		# Unlit, so the arena's own lighting can never hide an affordance.
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override = material
		_materials.push_back(material)
	_attach_outlines(tint)


## El borde de "esto se usa" del estilo Claridad (SemanticOutline). Los peligros
## no: son charcos y zonas planas, sin silueta que delinear, y ya brillan solos.
func _attach_outlines(tint: Color) -> void:
	if meaning == Meaning.HAZARD:
		return
	for mesh: MeshInstance3D in meshes:
		if mesh != null and not (mesh.material_override is ShaderMaterial):
			SemanticOutline.attach(mesh, tint)


## El mapa de emision del material propio del modelo, si tiene.
func _glow_map(mesh: MeshInstance3D) -> Texture2D:
	if mesh.mesh == null:
		return null
	for surface: int in mesh.mesh.get_surface_count():
		var material := mesh.get_active_material(surface) as BaseMaterial3D
		if material != null and material.emission_enabled and material.emission_texture != null:
			return material.emission_texture
	return null


func _enter_state() -> void:
	_time = 0.0
	_is_blinking = false
	_pulse_period = 0.0
	match state:
		State.IDLE:
			_set_energy(idle_energy)
		State.AVAILABLE:
			_set_energy(available_energy)
			_pulse_period = Tokens.ANCHOR_PULSE
		State.WARNING:
			_is_blinking = true
		State.ACTIVE:
			_set_energy(active_energy)


func _set_energy(energy: float) -> void:
	var scaled: float = energy * overlay_strength if overlay else energy
	for material: StandardMaterial3D in _materials:
		material.emission_energy_multiplier = scaled
	for material: ShaderMaterial in _shader_materials:
		material.set_shader_parameter(&"glow_energy", energy)
