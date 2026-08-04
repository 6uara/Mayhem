class_name TelegraphComponent
extends Node
## The one telegraph system every interactive object in the arena runs on.
##
## SPEC-VIEWMODELS 3.4: all seven telegraph types are the same thing - a mesh, an
## unlit emissive material and a state enum. Centralising it is what makes the
## arena legible: "cyan pulsing" means the same thing on an anchor, a pad and a
## zip line, because it is literally the same code.
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

## The one law (SPEC-VIEWMODELS 3.2). No other colour may appear on an
## interactive surface, and none of these four is ever reused for another meaning.
enum Meaning {
	TRAVERSAL,  ## cyan: you can use this
	HAZARD,     ## acid: this will hurt you
	PICKUP,     ## amber: take this
	SPAWN,      ## magenta: enemies come from here
}

@export var meaning: Meaning = Meaning.TRAVERSAL
## Meshes driven by this telegraph. All get the same unlit emissive material, so
## an interactive object can never disappear into shadow.
@export var meshes: Array[MeshInstance3D] = []

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
var _time: float = 0.0
var _blink_step: float = 0.25
var _is_blinking: bool = false
var _pulse_period: float = 0.0


func _ready() -> void:
	_build_materials()
	_enter_state()


func _process(delta: float) -> void:
	if _materials.is_empty():
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
	var tint: Color = get_color()
	for mesh: MeshInstance3D in meshes:
		if mesh == null:
			continue
		var material := StandardMaterial3D.new()
		material.albedo_color = tint
		material.emission_enabled = true
		material.emission = tint
		# Unlit, so the arena's own lighting can never hide an affordance.
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override = material
		_materials.push_back(material)


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
	for material: StandardMaterial3D in _materials:
		material.emission_energy_multiplier = energy
