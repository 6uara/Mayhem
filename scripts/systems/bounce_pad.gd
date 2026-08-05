class_name BouncePad
extends Area3D
## Static momentum source: launches anything in the player group straight up while
## leaving horizontal velocity alone, so pads combo with dash and slide by design.

## Apex under the player's gravity (24.0) is v^2/48. At the default that's 4.69m -
## comfortable clearance over the mid platforms (3.4m), where 13.0 (3.52m apex)
## used to leave only 0.12m of margin. Pads that specifically target the high
## level (6.4m) should override this rather than relying on the default's margin.
@export var bounce_velocity: float = 15.0
## Pads never *reduce* an incoming upward velocity - a fast arrival stays fast.
@export var preserve_higher_velocity: bool = true
@export var bounce_sound: AudioStream

@onready var _mesh: MeshInstance3D = $Mesh


## Cyan, because a pad is something you use. The chevron motion states the
## direction; the colour only confirms it.
func _apply_colour_law() -> void:
	if _mesh == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = Tokens.WORLD_TRAVERSAL
	material.emission_enabled = true
	material.emission = Tokens.WORLD_TRAVERSAL
	material.emission_energy_multiplier = 0.9
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh.material_override = material


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_apply_colour_law.call_deferred()


func _on_body_entered(entered: Node3D) -> void:
	var player_body := entered as CharacterBody3D
	if player_body == null or not player_body.is_in_group(&"player"):
		return
	var launch: float = bounce_velocity
	if preserve_higher_velocity:
		launch = maxf(launch, player_body.velocity.y)
	player_body.velocity.y = launch
	AudioPool.play_3d(bounce_sound, global_position, AudioPool.BUS_WORLD)
	_pulse()


## Placeholder feedback: a quick scale pop until the VFX pass.
func _pulse() -> void:
	if _mesh == null:
		return
	var tween: Tween = create_tween()
	_mesh.scale = Vector3(1.15, 0.6, 1.15)
	tween.tween_property(_mesh, "scale", Vector3.ONE, 0.18)
