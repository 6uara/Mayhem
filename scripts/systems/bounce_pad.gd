class_name BouncePad
extends Area3D
## Static momentum source: launches anything in the player group straight up while
## leaving horizontal velocity alone, so pads combo with dash and slide by design.

@export var bounce_velocity: float = 13.0
## Pads never *reduce* an incoming upward velocity - a fast arrival stays fast.
@export var preserve_higher_velocity: bool = true
@export var bounce_sound: AudioStream

@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	body_entered.connect(_on_body_entered)


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
